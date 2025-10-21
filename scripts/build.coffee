#!/usr/bin/env node
# scripts/build.coffee
# Build script: compile CoffeeScript and fix import paths

{ exec } = require 'child_process'
{ promisify } = require 'util'
fs = require 'fs'
path = require 'path'
execAsync = promisify(exec)

# Fix import paths in all .js files
fixImportPaths = (dir) ->
  return unless fs.existsSync(dir)

  for file in fs.readdirSync(dir, { withFileTypes: true })
    filePath = path.join(dir, file.name)

    if file.isDirectory()
      fixImportPaths(filePath)
    else if file.isFile() and file.name.endsWith('.js')
      content = fs.readFileSync(filePath, 'utf8')

      # Fix static imports: from './file.coffee' → from './file.js'
      content = content.replace(/from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g, "from '$1.js'")
      # Fix dynamic imports: import('./file.coffee') → import('./file.js')
      content = content.replace(/import\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g, "import('$1.js')")

      fs.writeFileSync(filePath, content, 'utf8')

build = ->
  console.log 'Building RentCoordinator...'

  try
    # Compile server-side CoffeeScript to dist/
    console.log 'Compiling server-side CoffeeScript...'
    await execAsync 'npx coffee -b -c -M -o dist .'

    # Fix import paths in dist/
    console.log 'Fixing import paths...'
    fixImportPaths('dist')

    # Compile client-side CoffeeScript to static/js
    console.log 'Compiling client-side CoffeeScript...'
    await execAsync 'npx coffee -b -c -M -o static/js static/coffee'

    console.log '✓ Build complete!'
  catch error
    console.error '✗ Build error:', error.message
    process.exit(1)

build()
