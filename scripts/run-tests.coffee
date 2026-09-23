#!/usr/bin/env coffee
#
# Runs the unit suites under test/services/. Each file is its own process so a
# suite that sets DB_PATH for a throwaway database can't affect the others.
#
# Replaces a version that did not parse (top-level `await import` destructuring)
# and searched a `tests/` directory this project has never had — so
# `npm run test:focus` had never run anything.

{ execFileSync } = require 'node:child_process'
fs               = require 'node:fs'
path             = require 'node:path'

UNIT_DIR = 'test/services'
pattern  = process.argv[2]


suites = fs.readdirSync UNIT_DIR
  .filter (name) -> name.endsWith '.coffee'
  .filter (name) -> not pattern or name.includes pattern
  .sort()
  .map (name) -> path.join UNIT_DIR, name


if suites.length is 0
  console.error if pattern
    "No unit suites matching '#{pattern}' in #{UNIT_DIR}/"
  else
    "No unit suites found in #{UNIT_DIR}/"
  process.exit 1


console.log "Running #{suites.length} unit suite(s)\n"

failed = []

for suite in suites
  console.log "── #{suite}"
  try
    execFileSync 'coffee', [suite],
      stdio: 'inherit'
      env:   Object.assign {}, process.env, NODE_ENV: process.env.NODE_ENV or 'test'
  catch
    failed.push suite
  console.log ''


if failed.length > 0
  console.error "✗ #{failed.length} suite(s) failed:"
  console.error "    #{suite}" for suite in failed
  process.exit 1

console.log "✓ All #{suites.length} unit suite(s) passed"
