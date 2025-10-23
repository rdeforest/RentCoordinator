#!/usr/bin/env node

{ exec }      = require 'child_process'
{ promisify } = require 'util'
fs            = require 'fs'
path          = require 'path'

execAsync = promisify exec


fixImportPaths = (dir) ->
  return unless fs.existsSync dir

  for file in fs.readdirSync dir, withFileTypes: true
    filePath = path.join dir, file.name

    if file.isDirectory()
      fixImportPaths filePath
    else if file.isFile() and file.name.endsWith '.js'
      content = fs.readFileSync filePath, 'utf8'
      content = content.replace /from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g,              "from '$1.js'"
      content = content.replace /import\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g, "import('$1.js')"

      fs.writeFileSync filePath, content, 'utf8'


copyDir = (src, dest) ->
  fs.mkdirSync dest, recursive: true

  for item in fs.readdirSync src, withFileTypes: true
    srcPath  = path.join src,  item.name
    destPath = path.join dest, item.name

    if item.isDirectory()
      copyDir srcPath, destPath
    else
      fs.copyFileSync srcPath, destPath


build = ->
  console.log 'Building RentCoordinator...'

  try
    console.log 'Compiling server-side CoffeeScript...'
    await execAsync 'npx coffee -b -c -M -o dist .'

    console.log 'Fixing import paths...'
    fixImportPaths 'dist'

    console.log 'Compiling client-side CoffeeScript...'
    await execAsync 'npx coffee -b -c -M -o static/js static/coffee'

    console.log 'Copying static assets...'
    copyDir 'static', 'dist/static'

    console.log '✓ Build complete!'

  catch error
    console.error '✗ Build error:', error.message
    process.exit 1


build()
