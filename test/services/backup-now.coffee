# scripts/backup-now.sh must exit non-zero when the S3 upload fails, so a
# caller that stops on failure (the reboot procedure in docs/deployment.md)
# does not go on with only a local copy. With S3 disabled there is no upload
# to fail, and a local backup is success.
#
# S3 is pointed at a closed local port, so no request leaves the machine. HOME
# is a scratch directory so the script skips `nvm use`, which would fail on a
# workstation without the .nvmrc version installed.

{ test }      = require 'node:test'
assert        = require 'node:assert/strict'
{ spawnSync } = require 'node:child_process'
fs            = require 'node:fs'
os            = require 'node:os'
path          = require 'node:path'

SCRIPT = path.join __dirname, '../../scripts/backup-now.sh'

tmpDir = fs.mkdtempSync path.join os.tmpdir(), 'rc-backup-now-'
dbPath = path.join tmpDir, 'test.db'
fs.writeFileSync dbPath, 'not really sqlite; the backup only copies it'

runBackup = (extraEnv) ->
  env = Object.fromEntries Object.entries(process.env).filter ([key]) -> not key.startsWith 'AWS_'
  Object.assign env,
    HOME:                  tmpDir
    DB_PATH:               dbPath
    AWS_REGION:            'us-west-2'
    AWS_ACCESS_KEY_ID:     'test'
    AWS_SECRET_ACCESS_KEY: 'test'
    AWS_ENDPOINT_URL_S3:   'http://127.0.0.1:9'
    BACKUP_S3_BUCKET:      'rc-backup-now-test'
    extraEnv
  spawnSync 'bash', [SCRIPT, path.join tmpDir, 'backups'], { env, encoding: 'utf8' }


test "exits non-zero when the S3 upload fails", ->
  result = runBackup {}
  assert.match result.stdout + result.stderr, /S3 upload failed/
  assert.notEqual result.status, 0


test "exits zero with S3 disabled", ->
  result = runBackup S3_BACKUP_ENABLED: 'false'
  assert.equal result.status, 0, result.stdout + result.stderr
