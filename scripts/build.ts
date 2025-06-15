#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env --allow-run --allow-net

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
    skip: [/node_modules/, /dist/, /\.git/]
  })) {
    const inputPath = entry.path;
    const relativePath = relative(".", inputPath);
    const outputPath = join("dist", relativePath.replace(/\.coffee$/, ".js"));

    try {
      // Read CoffeeScript file
      const coffeeCode = await Deno.readTextFile(inputPath);

      // Compile to JavaScript
      const jsCode = CoffeeScript.compile(coffeeCode, {
        bare: true,
        filename: inputPath
      });

      // Fix import paths to use .js extensions
      const fixedJsCode = jsCode.replace(
        /from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g,
        "from '$1.js'"
      );

      // Ensure output directory exists
      await ensureDir(dirname(outputPath));

      // Write JavaScript file
      await Deno.writeTextFile(outputPath, fixedJsCode);

      console.log(`✓ ${relativePath} → ${outputPath}`);
    } catch (error) {
      console.error(`✗ Error compiling ${relativePath}:`, error.message);
    }
  }

  // Copy static files
  console.log("\nCopying static files...");
  await ensureDir("dist/static");

  try {
    await Deno.copyFile("static/index.html", "dist/static/index.html");
    await ensureDir("dist/static/css");
    await Deno.copyFile("static/css/app.css", "dist/static/css/app.css");
    await ensureDir("dist/static/js");
    await Deno.copyFile("static/js/timer.js", "dist/static/js/timer.js");
    console.log("✓ Static files copied");
  } catch (error) {
    console.error("✗ Error copying static files:", error.message);
  }
}

async function runServer() {
  console.log("\nStarting server...");
  const cmd = new Deno.Command("deno", {
    args: ["run", "--allow-net", "--allow-read", "--allow-write", "--allow-env", "dist/main.js"],
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
        path.endsWith(".css") ||
        path.endsWith(".js")
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