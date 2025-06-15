#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env --allow-run --allow-net
# scripts/build.coffee

CoffeeScript = (await import("coffeescript")).default
{ walk } = await import("https://deno.land/std@0.224.0/fs/walk.ts")
{ ensureDir } = await import("https://deno.land/std@0.224.0/fs/ensure_dir.ts")
{ relative, dirname, join } = await import("https://deno.land/std@0.224.0/path/mod.ts")

WATCH_MODE = Deno.args.includes("--watch")

compileCoffeeScript = ->
  console.log "Compiling CoffeeScript files..."

  # Ensure dist directory exists
  await ensureDir("dist")

  # Walk through all .coffee files
  for await entry from walk(".",
    exts: [".coffee"]
    skip: [/node_modules/, /dist/, /\.git/, /static/])

    inputPath = entry.path
    relativePath = relative(".", inputPath)
    outputPath = join("dist", relativePath.replace(/\.coffee$/, ".js"))

    try
      # Read CoffeeScript file
      coffeeCode = await Deno.readTextFile(inputPath)

      # Compile to JavaScript
      jsCode = CoffeeScript.compile coffeeCode,
        bare: true
        filename: inputPath

      # Fix import paths - handle both static and dynamic imports
      jsCode = jsCode
        # Static imports: import ... from './file.coffee'
        .replace(/from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g, "from '$1.js'")
        # Dynamic imports: await import('./file.coffee')
        .replace(/import\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g, "import('$1.js')")

      # Ensure output directory exists
      await ensureDir(dirname(outputPath))

      # Write JavaScript file
      await Deno.writeTextFile(outputPath, jsCode)

      console.log "✓ #{relativePath} → #{outputPath}"
    catch error
      console.error "✗ Error compiling #{relativePath}:", error.message

  # Copy static files
  console.log "\nCopying static files..."
  await ensureDir("dist/static")

  try
    # Copy HTML files
    await Deno.copyFile("static/index.html", "dist/static/index.html")
    await Deno.copyFile("static/rent.html", "dist/static/rent.html")
    await Deno.copyFile("static/work.html", "dist/static/work.html")

    # Copy CSS
    await ensureDir("dist/static/css")
    await Deno.copyFile("static/css/app.css", "dist/static/css/app.css")
    await Deno.copyFile("static/css/rent.css", "dist/static/css/rent.css")
    await Deno.copyFile("static/css/work.css", "dist/static/css/work.css")

    # Copy CoffeeScript files (no compilation - browser will handle it)
    await ensureDir("dist/static/coffee")
    await Deno.copyFile("static/coffee/timer.coffee", "dist/static/coffee/timer.coffee")
    await Deno.copyFile("static/coffee/rent.coffee", "dist/static/coffee/rent.coffee")
    await Deno.copyFile("static/coffee/work.coffee", "dist/static/coffee/work.coffee")

    console.log "✓ Static files copied"
  catch error
    console.error "✗ Error copying static files:", error.message

runServer = ->
  console.log "\nStarting server..."
  cmd = new Deno.Command "deno",
    args: ["run", "--allow-net", "--allow-read", "--allow-write", "--allow-env", "--unstable-kv", "dist/main.js"]
    stdout: "inherit"
    stderr: "inherit"

  cmd.spawn()

if WATCH_MODE
  # Initial build
  await compileCoffeeScript()

  # Start server
  serverProcess = await runServer()

  console.log "\nWatching for changes..."

  # Watch for file changes
  watcher = Deno.watchFs ".",
    recursive: true

  for await event from watcher
    if event.kind in ["modify", "create"]
      changedFiles = event.paths.filter (path) ->
        path.endsWith(".coffee") or
        path.endsWith(".html") or
        path.endsWith(".css")

      if changedFiles.length > 0
        console.log "\nFiles changed, rebuilding..."

        # Kill existing server
        try
          serverProcess.kill("SIGTERM")
        catch e
          # Server might already be dead

        # Rebuild
        await compileCoffeeScript()

        # Restart server
        serverProcess = await runServer()
else
  # Just build once
  await compileCoffeeScript()
  console.log "\nBuild complete! Run 'deno task start' to start the server."