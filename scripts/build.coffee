#!/usr/bin/env node

{ exec }      = require 'child_process'
{ promisify } = require 'util'
fs            = require 'fs'
path          = require 'path'

execAsync = promisify exec

# What the running server actually needs. migrations/ ships because the boot
# migration runner executes them from the deployed tree.
SERVER_SOURCES = ['main.coffee', 'lib', 'migrations', 'scripts']

# Not CoffeeScript, so the compiler steps above skip them entirely.
SHELL_SCRIPTS = ['scripts/upgrade.sh']


fixImportPaths = (dir) ->
  return unless fs.existsSync dir

  for file in fs.readdirSync dir, withFileTypes: true
    filePath = path.join dir, file.name

    if file.isDirectory()
      fixImportPaths filePath
    else if file.isFile() and file.name.endsWith '.js'
      content = fs.readFileSync filePath, 'utf8'
      content = content.replace /from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g,               "from '$1.js'"
      content = content.replace /import\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g,  "import('$1.js')"
      # This project requires its modules by path — `require './config.coffee'`
      # — and only the two import forms above were being rewritten, so every
      # compiled file asked for a .coffee that dist/ does not contain. Together
      # with the missing package.json (bug 44) that meant the dist artifact had
      # never been able to start.
      content = content.replace /require\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g, "require('$1.js')"

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
    console.log 'Running pre-build validation...'
    await execAsync 'npx coffee scripts/validate.coffee'

    # Named sources, not '.'. Compiling the whole working tree swept in
    # scratch directories, previous dist output and anything else lying
    # around — on this checkout a stale copy of the repo under tmp/ had been
    # failing the build since May, which is why the dist artifact was never
    # exercised and bug 44 went unnoticed.
    console.log 'Compiling server-side CoffeeScript...'
    for source in SERVER_SOURCES
      # A directory keeps its own name under dist/; a lone file lands at the
      # top. `coffee -o dist lib` would flatten lib/ into dist/ instead.
      outDir = if fs.statSync(source).isDirectory() then path.join 'dist', source else 'dist'
      await execAsync "npx coffee -b -c -M -o #{outDir} #{source}"

    console.log 'Fixing import paths...'
    fixImportPaths 'dist'

    console.log 'Compiling client-side CoffeeScript...'
    await execAsync 'npx coffee -b -c -M -o static/js static/coffee'

    console.log 'Copying static assets...'
    copyDir 'static', 'dist/static'

    # lib/routing.coffee does `require '../package.json'`, which compiles to
    # dist/lib/routing.js resolving dist/package.json — a file the build never
    # produced (bug 44).
    #
    # It is not a straight copy. The root package is "type": "module", but
    # `coffee -b -c` emits CommonJS, so copying the root manifest verbatim
    # declares the compiled output to be something it is not and every require
    # in it fails. The artifact describes itself accurately instead.
    console.log 'Writing dist/package.json...'
    pkg = JSON.parse fs.readFileSync 'package.json', 'utf8'
    fs.writeFileSync 'dist/package.json',
      JSON.stringify(Object.assign({}, pkg,
        type:    'commonjs'
        main:    'main.js'
        # The source scripts run .coffee files that dist/ does not contain, so
        # the two that matter are rewritten — the rest are kept rather than
        # dropped, which replacing the whole block would have done.
        scripts: Object.assign {}, pkg.scripts,
          start:   'node main.js'
          migrate: 'node scripts/run-migrations.js'
      ), null, 2) + '\n'

    # The shell entry points are not compiled, so they have to be copied.
    # Without upgrade.sh the artifact has no documented way to migrate.
    console.log 'Copying shell scripts...'
    for script in SHELL_SCRIPTS
      fs.copyFileSync script, path.join 'dist', script
      fs.chmodSync path.join('dist', script), 0o755

    console.log '✓ Build complete!'

  catch error
    console.error '✗ Build error:', error.message
    process.exit 1


build()
