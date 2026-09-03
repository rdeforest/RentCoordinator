# Unit tests for the idle auto-backup decision (lib/services/backup.coffee).
# Pure function — no DB, no S3, no timers.

{ test } = require 'node:test'
assert   = require 'node:assert/strict'

{ shouldIdleBackup } = require '../../lib/services/backup.coffee'

HOUR = 60 * 60 * 1000
# Fixed reference "now"; times are relative to it.
NOW  = 1_000_000_000_000


test "no backup when nothing changed since the last backup", ->
  # DB last written before the last backup — even if long idle.
  assert.equal shouldIdleBackup(NOW - 5 * HOUR, NOW - 2 * HOUR, NOW, HOUR), false


test "no backup while still active (changed within the idle window)", ->
  # Changed 20 min ago → not quiet long enough.
  assert.equal shouldIdleBackup(NOW - 20 * 60 * 1000, NOW - 3 * HOUR, NOW, HOUR), false


test "backup when changed since last backup and idle past the threshold", ->
  # Last backup 3h ago, last write 90 min ago → changed and quiet.
  assert.equal shouldIdleBackup(NOW - 90 * 60 * 1000, NOW - 3 * HOUR, NOW, HOUR), true


test "idle threshold is inclusive (exactly idleMs of quiet)", ->
  assert.equal shouldIdleBackup(NOW - HOUR, NOW - 2 * HOUR, NOW, HOUR), true


test "just under the idle threshold does not back up", ->
  assert.equal shouldIdleBackup(NOW - (HOUR - 1000), NOW - 2 * HOUR, NOW, HOUR), false


test "change exactly at the last-backup instant is not a change", ->
  # dbMtime == lastBackupAt → not strictly newer → no backup.
  assert.equal shouldIdleBackup(NOW - 2 * HOUR, NOW - 2 * HOUR, NOW, HOUR), false
