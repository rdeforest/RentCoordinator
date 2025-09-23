#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env --allow-run --allow-net
// scripts/build.ts

import CoffeeScript from "coffeescript";
import { walk } from "https://deno.land/std@0.224.0/fs/walk.ts";
import { ensureDir } from "https://deno.land/std@0.224.0/fs/ensure_dir.ts";
import { relative, dirname, join } from "https://deno.land/std@0.224.0/path/mod.ts";

const WATCH_MODE = Deno.args.includes("--watch");

async function compileCoffeeScript() {
  console.log("Compiling CoffeeScript files...");

  // Ensure dist directory exists
  await ensureDir("dist");

  // Walk through all .coffee files
  for await (const entry of walk(".", {
    exts: [".coffee"],
    skip: [/node_modules/, /dist/, /\.git/, /static/]
  })) {
    const inputPath = entry.path;
    const relativePath = relative(".", inputPath);
    const outputPath = join("dist", relativePath.replace(/\.coffee$/, ".js"));

    try {
      // Read CoffeeScript file
      const coffeeCode = await Deno.readTextFile(inputPath);

      // Compile to JavaScript
      let jsCode = CoffeeScript.compile(coffeeCode, {
        bare: true,
        filename: inputPath
      });

      // Fix import paths - handle both static and dynamic imports
      jsCode = jsCode
        // Static imports: import ... from './file.coffee'
        .replace(/from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g, "from '$1.js'")
        // Dynamic imports: await import('./file.coffee')
        .replace(/import\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g, "import('$1.js')");

      // Ensure output directory exists
      await ensureDir(dirname(outputPath));

      // Write JavaScript file
      await Deno.writeTextFile(outputPath, jsCode);

      console.log(`✓ ${relativePath} → ${outputPath}`);
    } catch (error) {
      console.error(`✗ Error compiling ${relativePath}:`, error.message);
    }
  }

  // Copy static files
  console.log("\nCopying static files...");
  await ensureDir("dist/static");

  try {
    // Copy HTML files
    await Deno.copyFile("static/index.html", "dist/static/index.html");
    await Deno.copyFile("static/rent.html", "dist/static/rent.html");
    await Deno.copyFile("static/work.html", "dist/static/work.html");

    // Copy CSS
    await ensureDir("dist/static/css");
    await Deno.copyFile("static/css/app.css", "dist/static/css/app.css");
    await Deno.copyFile("static/css/rent.css", "dist/static/css/rent.css");
    await Deno.copyFile("static/css/work.css", "dist/static/css/work.css");
    await Deno.copyFile("static/css/timer.css", "dist/static/css/timer.css");

    // Copy JavaScript files (compiled from CoffeeScript)
    await ensureDir("dist/static/js");
    await Deno.copyFile("static/js/shared-utils.js", "dist/static/js/shared-utils.js");
    await Deno.copyFile("static/js/timer.js", "dist/static/js/timer.js");
    await Deno.copyFile("static/js/rent.js", "dist/static/js/rent.js");
    await Deno.copyFile("static/js/work.js", "dist/static/js/work.js");

    // Still copy CoffeeScript files for reference
    await ensureDir("dist/static/coffee");
    await Deno.copyFile("static/coffee/shared-utils.coffee", "dist/static/coffee/shared-utils.coffee");
    await Deno.copyFile("static/coffee/timer.coffee", "dist/static/coffee/timer.coffee");
    await Deno.copyFile("static/coffee/rent.coffee", "dist/static/coffee/rent.coffee");
    await Deno.copyFile("static/coffee/work.coffee", "dist/static/coffee/work.coffee");

    // Copy CoffeeScript browser compiler
    await ensureDir("dist/static/vendor");
    const possiblePaths = [
      "./node_modules/coffeescript/lib/coffeescript-browser-compiler-modern/coffeescript.js",
      "./node_modules/coffeescript/extras/coffeescript.js",
      "./node_modules/coffeescript/lib/browser-compiler-modern/coffeescript.js",
      "./node_modules/coffeescript/browser-compiler/coffeescript.js"
    ];

    let found = false;
    for (const path of possiblePaths) {
      try {
        await Deno.stat(path);
        await Deno.copyFile(path, "dist/static/vendor/coffeescript.js");
        console.log(`✓ Copied CoffeeScript browser compiler from ${path}`);
        found = true;
        break;
      } catch {
        // Try next path
      }
    }

    if (!found) {
      console.error("✗ Could not find CoffeeScript browser compiler in node_modules");
    }

    console.log("✓ Static files copied");
  } catch (error) {
    console.error("✗ Error copying static files:", error.message);
  }
}

async function runServer() {
  console.log("\nStarting server...");
  const cmd = new Deno.Command("deno", {
    args: ["run", "--allow-net", "--allow-read", "--allow-write", "--allow-env", "--unstable-kv", "dist/main.js"],
    stdout: "inherit",
    stderr: "inherit",
  });

  const child = cmd.spawn();
  return child;
}

if (WATCH_MODE) {
  // Initial build
  await compileCoffeeScript();

  // Start server
  let serverProcess = await runServer();

  console.log("\nWatching for changes...");

  // Watch for file changes
  const watcher = Deno.watchFs(".", {
    recursive: true
  });

  for await (const event of watcher) {
    if (event.kind === "modify" || event.kind === "create") {
      const changedFiles = event.paths.filter(path =>
        path.endsWith(".coffee") ||
        path.endsWith(".html") ||
        path.endsWith(".css")
      );

      if (changedFiles.length > 0) {
        console.log("\nFiles changed, rebuilding...");

        // Kill existing server
        try {
          serverProcess.kill("SIGTERM");
        } catch (e) {
          // Server might already be dead
        }

        // Rebuild
        await compileCoffeeScript();

        // Restart server
        serverProcess = await runServer();
      }
    }
  }
} else {
  // Just build once
  await compileCoffeeScript();
  console.log("\nBuild complete! Run 'deno task start' to start the server.");
}