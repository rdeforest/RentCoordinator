# Bug 62 — landlord-only routes over the consistency checks. Reads go through
# lib/models/consistency.coffee (stored runs), writes either trigger a fresh
# run or record/remove an acknowledgment. See docs/event-model.md's neighbor,
# docs/bugs/62-no-consistency-checking.md, for the design.

config               = require '../config.coffee'
middleware           = require '../middleware.coffee'
consistencyModel     = require '../models/consistency.coffee'
consistencyScheduler = require '../services/consistency-scheduler.coffee'
{ asyncRoute }       = middleware


decorate = (findings) ->
  findings.map (f) -> Object.assign {}, f, acknowledgment: consistencyModel.getAck(f.key) ? null


# Acknowledgments whose finding the latest run didn't report: resolved, re-keyed,
# or hidden by a check that errored. Shown, never deleted.
unreported = (findings) ->
  reported = new Set (f.key for f in findings)
  (a for a in consistencyModel.listAcknowledgments() when not reported.has a.finding_key)


setup = (app) ->
  app.get '/admin/consistency', middleware.requireAdmin, asyncRoute 'consistency.get', (req, res) ->
    run = consistencyModel.latestRun()
    return res.json { ran_at: null, findings: [], unreported_acknowledgments: unreported [] } unless run

    res.json
      ran_at:                     run.ran_at
      findings:                   decorate run.findings
      unreported_acknowledgments: unreported run.findings

  app.get '/admin/consistency/summary', middleware.requireAdmin, asyncRoute 'consistency.summary', (req, res) ->
    run = consistencyModel.latestRun()
    return res.json { open: 0, ran_at: null } unless run

    acked = consistencyModel.acknowledgedKeys()
    open  = run.findings.filter((f) -> not acked.has f.key).length
    res.json { open, ran_at: run.ran_at }

  app.post '/admin/consistency/run', middleware.requireAdmin, asyncRoute 'consistency.run', (req, res) ->
    findings = await consistencyScheduler.runAndStore()
    res.json
      ran_at:                     new Date().toISOString()
      findings:                   decorate findings
      unreported_acknowledgments: unreported findings

  app.post '/admin/consistency/ack', middleware.requireAdmin, asyncRoute 'consistency.ack', (req, res) ->
    { key, note } = req.body or {}
    return res.status(400).json error: 'key required' unless key
    return res.status(400).json error: 'note required' unless note and String(note).trim().length > 0

    acknowledgment = consistencyModel.ack key, String(note).trim(), req.session.email
    res.json { acknowledgment }

  app.delete '/admin/consistency/ack/:key', middleware.requireAdmin, asyncRoute 'consistency.unack', (req, res) ->
    consistencyModel.unack req.params.key
    res.json { ok: true }

  # The page itself follows the /admin pattern: requireAdminPage sends a
  # tenant back to '/' rather than a browser-navigation 403. The data behind
  # it (the routes above) is behind requireAdmin, so a tenant who somehow
  # lands here sees no findings regardless.
  app.get '/issues', middleware.requireAdminPage, (req, res) ->
    res.sendFile 'issues.html', root: config.STATIC_DIR


module.exports = { setup }
