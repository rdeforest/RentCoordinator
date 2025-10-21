#!/usr/bin/env node
# scripts/build.coffee
# Node.js build system for RentCoordinator

import CoffeeScript from 'coffeescript'
import fs           from 'fs'
import path         from 'path'
import { spawn }    from 'child_process'
import chokidar     from 'chokidar'
import { fileURLToPath } from 'url'
import { dirname }  from 'path'

__filename = fileURLToPath(import.meta.url)
__dirname  = dirname(__filename)
ROOT_DIR   = path.join(__dirname, '..')

WATCH_MODE = process.argv.includes('--watch')


# Recursively walk directory and find files with extension
walkSync = (dir, exts) ->
  files = fs.readdirSync(dir, { withFileTypes: true })

  for file in files
    filePath = path.join(dir, file.name)

    if file.isDirectory()
      # Skip these directories
      if file.name in ['node_modules', 'dist', '.git', 'static']
        continue
      yield from walkSync(filePath, exts)
    else if file.isFile()
      ext = path.extname(file.name)
      if ext in exts
        yield filePath


# Ensure directory exists
ensureDir = (dirPath) ->
  unless fs.existsSync(dirPath)
    fs.mkdirSync(dirPath, { recursive: true })


# Copy file or directory recursively
copyRecursive = (src, dest) ->
  if fs.statSync(src).isDirectory()
    ensureDir(dest)
    files = fs.readdirSync(src)
    for file in files
      copyRecursive(path.join(src, file), path.join(dest, file))
  else
    ensureDir(path.dirname(dest))
    fs.copyFileSync(src, dest)


compileCoffeeScript = ->
  console.log 'Compiling CoffeeScript files...'

  # Ensure dist directory exists
  ensureDir('dist')

  # Compile server-side CoffeeScript
  for inputPath in walkSync('.', ['.coffee'])
    relativePath = path.relative('.', inputPath)
    outputPath = path.join('dist', relativePath.replace(/\.coffee$/, '.js'))

    try
      # Read CoffeeScript file
      coffeeCode = fs.readFileSync(inputPath, 'utf8')

      # Compile to JavaScript
      jsCode = CoffeeScript.compile coffeeCode, {
        bare: true
        filename: inputPath
      }

      # Fix import paths - handle both static and dynamic imports
      jsCode = jsCode
        # Static imports: import ... from './file.coffee'
        .replace(/from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g, "from '$1.js'")
        # Dynamic imports: await import('./file.coffee')
        .replace(/import\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g, "import('$1.js')")

      # Ensure output directory exists
      ensureDir(path.dirname(outputPath))

      # Write JavaScript file
      fs.writeFileSync(outputPath, jsCode, 'utf8')

      console.log "✓ #{relativePath} → #{outputPath}"
    catch error
      console.error "✗ Error compiling #{relativePath}:", error.message

  # Compile client-side CoffeeScript
  console.log '\nCompiling client-side CoffeeScript...'
  ensureDir('static/js')

  try
    if fs.existsSync('static/coffee')
      for inputPath in walkSync('static/coffee', ['.coffee'])
        outputPath = inputPath.replace('static/coffee/', 'static/js/').replace('.coffee', '.js')

        try
          coffeeCode = fs.readFileSync(inputPath, 'utf8')
          jsCode = CoffeeScript.compile coffeeCode, {
            bare: true
            filename: inputPath
          }

          fs.writeFileSync(outputPath, jsCode, 'utf8')
          console.log "✓ #{inputPath} → #{outputPath}"
        catch error
          console.error "✗ Error compiling #{inputPath}:", error.message
  catch error
    console.error '✗ Error compiling client-side CoffeeScript:', error.message

  # Copy static files
  console.log '\nCopying static files...'
  ensureDir('dist/static')

  try
    # Copy HTML files from static root
    if fs.existsSync('static')
      staticFiles = fs.readdirSync('static')
      for file in staticFiles
        if file.endsWith('.html')
          fs.copyFileSync(
            path.join('static', file)
            path.join('dist/static', file)
          )

    # Copy entire directories
    if fs.existsSync('static/css')
      copyRecursive('static/css', 'dist/static/css')
    if fs.existsSync('static/js')
      copyRecursive('static/js', 'dist/static/js')
    if fs.existsSync('static/coffee')
      copyRecursive('static/coffee', 'dist/static/coffee')

    console.log '✓ Static files copied'
  catch error
    console.error '✗ Error copying static files:', error.message


runServer = ->
  console.log '\nStarting server...'
  serverProcess = spawn 'node', ['dist/main.js'], {
    stdio: 'inherit'
    env: process.env
  }
  return serverProcess


if WATCH_MODE
  # Initial build
  await compileCoffeeScript()

  # Start server
  serverProcess = runServer()

  console.log '\nWatching for changes...'

  # Watch for file changes
  watcher = chokidar.watch '.', {
    ignored: /(^|[\/\\])(node_modules|dist|\.git)([\/\\]|$)/
    persistent: true
    ignoreInitial: true
  }

  watcher.on 'change', (filePath) ->
    if filePath.endsWith('.coffee') or filePath.endsWith('.html') or filePath.endsWith('.css')
      console.log "\nFile changed: #{filePath}, rebuilding..."

      # Kill existing server
      try
        serverProcess.kill('SIGTERM')
      catch e
        # Server might already be dead

      # Rebuild
      await compileCoffeeScript()

      # Restart server
      serverProcess = runServer()

  # Handle process termination
  process.on 'SIGINT', ->
    console.log '\nShutting down...'
    serverProcess.kill('SIGTERM')
    process.exit(0)
else
  # Just build once
  await compileCoffeeScript()
  console.log "\nBuild complete! Run 'npm start' to start the server."
