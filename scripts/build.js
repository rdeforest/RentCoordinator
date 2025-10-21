  //!/usr/bin/env node
  // scripts/build.coffee
  // Node.js build system for RentCoordinator
var ROOT_DIR, WATCH_MODE, __dirname, __filename, compileCoffeeScript, copyRecursive, ensureDir, runServer, serverProcess, walkSync, watcher,
  indexOf = [].indexOf;

import CoffeeScript from 'coffeescript';

import fs from 'fs';

import path from 'path';

import {
  spawn
} from 'child_process';

import chokidar from 'chokidar';

import {
  fileURLToPath
} from 'url';

import {
  dirname
} from 'path';

__filename = fileURLToPath(import.meta.url);

__dirname = dirname(__filename);

ROOT_DIR = path.join(__dirname, '..');

WATCH_MODE = process.argv.includes('--watch');

// Recursively walk directory and find files with extension
walkSync = function*(dir, exts) {
  var ext, file, filePath, files, i, len, ref, results;
  files = fs.readdirSync(dir, {
    withFileTypes: true
  });
  results = [];
  for (i = 0, len = files.length; i < len; i++) {
    file = files[i];
    filePath = path.join(dir, file.name);
    if (file.isDirectory()) {
      // Skip these directories
      if ((ref = file.name) === 'node_modules' || ref === 'dist' || ref === '.git' || ref === 'static') {
        continue;
      }
      results.push((yield* walkSync(filePath, exts)));
    } else if (file.isFile()) {
      ext = path.extname(file.name);
      if (indexOf.call(exts, ext) >= 0) {
        results.push((yield filePath));
      } else {
        results.push(void 0);
      }
    } else {
      results.push(void 0);
    }
  }
  return results;
};

// Ensure directory exists
ensureDir = function(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return fs.mkdirSync(dirPath, {
      recursive: true
    });
  }
};

// Copy file or directory recursively
copyRecursive = function(src, dest) {
  var file, files, i, len, results;
  if (fs.statSync(src).isDirectory()) {
    ensureDir(dest);
    files = fs.readdirSync(src);
    results = [];
    for (i = 0, len = files.length; i < len; i++) {
      file = files[i];
      results.push(copyRecursive(path.join(src, file), path.join(dest, file)));
    }
    return results;
  } else {
    ensureDir(path.dirname(dest));
    return fs.copyFileSync(src, dest);
  }
};

compileCoffeeScript = function() {
  var coffeeCode, error, file, i, inputPath, j, jsCode, k, len, len1, len2, outputPath, ref, ref1, relativePath, staticFiles;
  console.log('Compiling CoffeeScript files...');
  // Ensure dist directory exists
  ensureDir('dist');
  ref = walkSync('.', ['.coffee']);
  // Compile server-side CoffeeScript
  for (i = 0, len = ref.length; i < len; i++) {
    inputPath = ref[i];
    relativePath = path.relative('.', inputPath);
    outputPath = path.join('dist', relativePath.replace(/\.coffee$/, '.js'));
    try {
      // Read CoffeeScript file
      coffeeCode = fs.readFileSync(inputPath, 'utf8');
      // Compile to JavaScript
      jsCode = CoffeeScript.compile(coffeeCode, {
        bare: true,
        filename: inputPath
      });
      // Fix import paths - handle both static and dynamic imports
      // Static imports: import ... from './file.js'
      // Dynamic imports: await import('./file.js')
      jsCode = jsCode.replace(/from\s+['"](\.\.?\/[^'"]+)\.coffee['"]/g, "from '$1.js'").replace(/import\s*\(\s*['"](\.\.?\/[^'"]+)\.coffee['"]\s*\)/g, "import('$1.js')");
      // Ensure output directory exists
      ensureDir(path.dirname(outputPath));
      // Write JavaScript file
      fs.writeFileSync(outputPath, jsCode, 'utf8');
      console.log(`✓ ${relativePath} → ${outputPath}`);
    } catch (error1) {
      error = error1;
      console.error(`✗ Error compiling ${relativePath}:`, error.message);
    }
  }
  // Compile client-side CoffeeScript
  console.log('\nCompiling client-side CoffeeScript...');
  ensureDir('static/js');
  try {
    if (fs.existsSync('static/coffee')) {
      ref1 = walkSync('static/coffee', ['.coffee']);
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        inputPath = ref1[j];
        outputPath = inputPath.replace('static/coffee/', 'static/js/').replace('.coffee', '.js');
        try {
          coffeeCode = fs.readFileSync(inputPath, 'utf8');
          jsCode = CoffeeScript.compile(coffeeCode, {
            bare: true,
            filename: inputPath
          });
          fs.writeFileSync(outputPath, jsCode, 'utf8');
          console.log(`✓ ${inputPath} → ${outputPath}`);
        } catch (error1) {
          error = error1;
          console.error(`✗ Error compiling ${inputPath}:`, error.message);
        }
      }
    }
  } catch (error1) {
    error = error1;
    console.error('✗ Error compiling client-side CoffeeScript:', error.message);
  }
  // Copy static files
  console.log('\nCopying static files...');
  ensureDir('dist/static');
  try {
    // Copy HTML files from static root
    if (fs.existsSync('static')) {
      staticFiles = fs.readdirSync('static');
      for (k = 0, len2 = staticFiles.length; k < len2; k++) {
        file = staticFiles[k];
        if (file.endsWith('.html')) {
          fs.copyFileSync(path.join('static', file), path.join('dist/static', file));
        }
      }
    }
    // Copy entire directories
    if (fs.existsSync('static/css')) {
      copyRecursive('static/css', 'dist/static/css');
    }
    if (fs.existsSync('static/js')) {
      copyRecursive('static/js', 'dist/static/js');
    }
    if (fs.existsSync('static/coffee')) {
      copyRecursive('static/coffee', 'dist/static/coffee');
    }
    return console.log('✓ Static files copied');
  } catch (error1) {
    error = error1;
    return console.error('✗ Error copying static files:', error.message);
  }
};

runServer = function() {
  var serverProcess;
  console.log('\nStarting server...');
  serverProcess = spawn('node', ['dist/main.js'], {
    stdio: 'inherit',
    env: process.env
  });
  return serverProcess;
};

if (WATCH_MODE) {
  // Initial build
  await compileCoffeeScript();
  // Start server
  serverProcess = runServer();
  console.log('\nWatching for changes...');
  // Watch for file changes
  watcher = chokidar.watch('.', {
    ignored: /(^|[\/\\])(node_modules|dist|\.git)([\/\\]|$)/,
    persistent: true,
    ignoreInitial: true
  });
  watcher.on('change', async function(filePath) {
    var e;
    if (filePath.endsWith('.coffee') || filePath.endsWith('.html') || filePath.endsWith('.css')) {
      console.log(`\nFile changed: ${filePath}, rebuilding...`);
      try {
        // Kill existing server
        serverProcess.kill('SIGTERM');
      } catch (error1) {
        e = error1;
      }
      // Server might already be dead

      // Rebuild
      await compileCoffeeScript();
      // Restart server
      return serverProcess = runServer();
    }
  });
  // Handle process termination
  process.on('SIGINT', function() {
    console.log('\nShutting down...');
    serverProcess.kill('SIGTERM');
    return process.exit(0);
  });
} else {
  // Just build once
  await compileCoffeeScript();
  console.log("\nBuild complete! Run 'npm start' to start the server.");
}
