# Runtime error visibility: a beacon endpoint for client-side errors and a
# tail-the-log endpoint for review. Both sit behind requireAuth (registered
# after it), so only whitelisted users reach them. CloudWatch shipping is
# dead on the Devuan AMI, so /admin/logs is the practical review surface.

logger                       = require '../logger.coffee'
config                       = require '../config.coffee'
{ readFileSync, existsSync } = require 'node:fs'

LOG_PATH  = process.env.APP_LOG_PATH or '/var/log/rent-coordinator/application.log'
ADMIN     = 'robert@defore.st'
MAX_LINES = 2000


setup = (app) ->
  # Client error beacon. The browser posts window.onerror / unhandledrejection
  # and anomaly canaries here; we log them server-side (PII tokenized). Fields
  # are length-capped so a runaway loop can't bloat the log.
  app.post '/client-errors', (req, res) ->
    b = req.body or {}
    logger.clientError
      kind:    b.kind or 'error'
      message: String(b.message ? '').slice 0, 2000
      source:  b.source
      line:    b.line
      col:     b.col
      stack:   String(b.stack ? '').slice 0, 4000
      page:    b.url
      detail:  b.detail
      user:    req.session?.email
    , req.id
    res.json ok: true

  # Admin-only log tail — the review surface. Robert only, since logs can
  # carry more than the tokenizer catches.
  app.get '/admin/logs', (req, res) ->
    unless req.session?.email is ADMIN
      return res.status(403).json error: 'Admin only'

    lines = Math.min (parseInt(req.query.lines) or 200), MAX_LINES

    unless existsSync LOG_PATH
      return res.json { path: LOG_PATH, lines: [], note: 'log file not found on this host' }

    try
      rows = readFileSync(LOG_PATH, 'utf8').split('\n').filter (l) -> l.length > 0
      res.json { path: LOG_PATH, total: rows.length, lines: rows.slice -lines }
    catch err
      logger.error 'observability.logs', err, {}, req.id
      res.status(500).json error: err.message


module.exports = { setup }
