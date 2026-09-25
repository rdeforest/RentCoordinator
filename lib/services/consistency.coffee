# Bug 62 — consistency checks that report and never block.
#
# Each check is a small function of `deps` returning an array of findings
# { key, kind, severity, month?, event_ids?, message, detail }. `key` is
# stable across runs for the same underlying problem AND carries the values
# involved, so a finding reappears (as a *new* key) if the data changes after
# it was acknowledged — see docs/bugs/62-no-consistency-checking.md.
#
# runChecks() is the only export most callers need. Everything else is
# exported so tests can call one check in isolation with constructed deps —
# no DB, no Stripe, no S3 required.

config      = require '../config.coffee'
money       = require '../money.coffee'
eventsModel = require '../models/events.coffee'
period      = require '../services/period.coffee'
schema      = require '../db/schema.coffee'
backupService = require './backup.coffee'
paymentService = require './payment.coffee'
consistencyModel = require '../models/consistency.coffee'


errorFinding = (kind, err) ->
  key:      "#{kind}-error:#{err.message}"
  kind:     "#{kind}-error"
  severity: 'error'
  message:  "#{kind} check threw: #{err.message}"
  detail:   { error: err.message }


groupByEffectiveFor = (events) ->
  groups = {}
  for e in events when e.effective_for
    (groups[e.effective_for] ?= []).push e
  groups


# --- db: SQLite's own integrity checks --------------------------------------

checkDatabaseIntegrity = (deps) ->
  rows     = deps.db.prepare('PRAGMA integrity_check').all()
  problems = (r.integrity_check for r in rows when r.integrity_check isnt 'ok')
  return [] if problems.length is 0

  [{
    key:      "db-integrity:#{problems.join '|'}"
    kind:     'db-integrity'
    severity: 'error'
    message:  'SQLite integrity_check reported problems'
    detail:   { problems }
  }]


checkForeignKeys = (deps) ->
  rows = deps.db.prepare('PRAGMA foreign_key_check').all()
  for r in rows
    key:      "db-foreign-key:#{r.table}:#{r.rowid}:#{r.parent}:#{r.fkid}"
    kind:     'db-foreign-key'
    severity: 'error'
    message:  "#{r.table} row #{r.rowid} references a missing #{r.parent} row (fk #{r.fkid})"
    detail:   r


# --- ledger: shape invariants the fold assumes ------------------------------

checkCorruptMonths = (deps) ->
  for month, p of deps.periods when p.corrupt
    key:      "ledger-corrupt-month:#{month}"
    kind:     'ledger-corrupt-month'
    severity: 'error'
    month:    month
    message:  "#{month} does not compute to a finite amount"
    detail:   { amount_due: p.amount_due, amount_paid: p.amount_paid }


REQUIRES_EFFECTIVE_FOR = ['work-reported', 'payment-made', 'override', 'adjustment']

checkEffectiveFor = (deps) ->
  for e in deps.events when e.action in REQUIRES_EFFECTIVE_FOR
    value = e.effective_for
    continue if value? and period.VALID_MONTH_KEY.test value

    key:       "ledger-invalid-effective-for:#{e.id}:#{JSON.stringify value}"
    kind:      'ledger-invalid-effective-for'
    severity:  'error'
    event_ids: [e.id]
    message:   "#{e.action} event #{e.id} has an invalid effective_for (#{JSON.stringify value})"
    detail:    { effective_for: value, action: e.action }


META_TARGETING = ['edited', 'deleted', 'undeleted']

checkTargetEventIds = (deps) ->
  ids = new Set (e.id for e in deps.events)
  for e in deps.events when e.action in META_TARGETING
    target = e.target_event_id
    continue if target? and ids.has target

    key:       "ledger-missing-target:#{e.id}:#{JSON.stringify target}"
    kind:      'ledger-missing-target'
    severity:  'error'
    event_ids: [e.id]
    message:   "#{e.action} event #{e.id} targets a missing event (#{JSON.stringify target})"
    detail:    { target_event_id: target }


checkDeleteOfDelete = (deps) ->
  byId = new Map ([e.id, e] for e in deps.events)

  for e in deps.events when e.action is 'deleted' and e.target_event_id
    target = byId.get e.target_event_id
    continue unless target?.action is 'deleted'

    key:       "ledger-delete-of-delete:#{e.id}:#{target.id}"
    kind:      'ledger-delete-of-delete'
    severity:  'error'
    event_ids: [e.id, target.id]
    message:   "deleted event #{e.id} targets another deleted event #{target.id}"
    detail:    {}


# --- manual vs automatic: pins that disagree with what happened ------------

checkPaymentAfterPin = (deps) ->
  resolved = period.resolveEditsAndDeletes deps.events
  byMonth  = groupByEffectiveFor resolved

  findings = []
  for month, monthEvents of byMonth
    pin = period.latestFieldOverride monthEvents, 'amount_paid'
    continue unless pin

    for e in monthEvents when e.action is 'payment-made' and e.occurred_at > pin.occurred_at
      findings.push
        key:       "manual-payment-after-pin:#{month}:#{e.id}:pin=#{pin.id}"
        kind:      'manual-payment-after-pin'
        severity:  'warning'
        month:     month
        event_ids: [e.id, pin.id]
        message:   "payment-made #{e.id} was recorded after amount_paid was pinned for #{month}"
        detail:
          payment_amount: e.payload.amount
          paid_at:        e.occurred_at
          pin_amount:     pin.payload.new_value
          pinned_at:      pin.occurred_at
  findings


checkAmountPaidPinMismatch = (deps) ->
  resolved = period.resolveEditsAndDeletes deps.events
  byMonth  = groupByEffectiveFor resolved

  findings = []
  for month, monthEvents of byMonth
    pin = period.latestFieldOverride monthEvents, 'amount_paid'
    continue unless pin

    paidEvents = (e for e in monthEvents when e.action is 'payment-made')
    summed_c   = paidEvents.reduce ((sum, e) -> sum + money.centsOf e.payload.amount), 0
    pinned_c   = money.centsOf pin.payload.new_value
    continue if pinned_c is summed_c

    findings.push
      key:       "manual-amount-paid-mismatch:#{month}:pinned=#{pinned_c}:summed=#{summed_c}"
      kind:      'manual-amount-paid-mismatch'
      severity:  'warning'
      month:     month
      event_ids: [pin.id].concat (e.id for e in paidEvents)
      message:   "#{month} amount_paid is pinned at #{money.fromCents pinned_c}, but payment-made events sum to #{money.fromCents summed_c}"
      detail:    { pinned: money.fromCents(pinned_c), summed: money.fromCents(summed_c) }
  findings


# amount_due is pinned "by design differs from the full calculation"
# (overridesForField/latestFieldOverride in period.coffee) — the comparison
# below is still worth reporting, but the *key* used to be built from
# amount_due/amount_due_calculated, both of which shift whenever an earlier
# month's carry-over changes even though the pin itself did not. That
# re-opened findings Robert had already acknowledged (bug 62, F6). Key on
# the pin instead — its event id and its own new_value — so the finding is
# stable across recalculation and only truly changes when the pin does.
checkAmountDuePinMismatch = (deps) ->
  resolved = period.resolveEditsAndDeletes deps.events
  byMonth  = groupByEffectiveFor resolved

  findings = []
  for month, monthEvents of byMonth
    pin = period.latestFieldOverride monthEvents, 'amount_due'
    continue unless pin

    p = deps.periods[month]
    continue unless p?.amount_due_override

    due_c  = money.centsOf p.amount_due
    calc_c = money.centsOf p.amount_due_calculated
    continue if due_c is calc_c

    pin_c = money.centsOf pin.payload.new_value

    findings.push
      key:       "manual-amount-due-mismatch:#{month}:pin=#{pin.id}:value=#{pin_c}"
      kind:      'manual-amount-due-mismatch'
      severity:  'warning'
      month:     month
      event_ids: [pin.id]
      message:   "#{month} amount_due is pinned at #{money.fromCents pin_c}"
      detail:    { amount_due: money.fromCents(due_c), amount_due_calculated: money.fromCents(calc_c) }
  findings


# --- backup: the newest S3 backup vs the newest write -----------------------

checkBackupAge = (deps) ->
  return [] unless deps.s3Enabled

  backups   = await deps.listS3Backups()
  lastWrite = deps.lastDataWriteMs()
  return [] if lastWrite is 0    # no data yet

  # lastDataWriteMs returns NaN (not 0) when a row exists but its created_at
  # couldn't be parsed — that's a real problem worth reporting, not the same
  # as "no data yet" (bug 62, F2).
  unless Number.isFinite lastWrite
    return [{
      key:      'backup-lastwrite-unparseable'
      kind:     'backup-lastwrite-error'
      severity: 'error'
      message:  'Could not determine the most recent data write timestamp'
      detail:   {}
    }]

  newestBackupMs = if backups[0]?.lastModified then new Date(backups[0].lastModified).getTime() else 0
  return [] if newestBackupMs >= lastWrite

  [{
    key:      "backup-stale:newest=#{newestBackupMs}:write=#{lastWrite}"
    kind:     'backup-stale'
    severity: 'error'
    message:  'The newest S3 backup is older than the newest data write'
    detail:
      newestBackupAt: if newestBackupMs > 0 then new Date(newestBackupMs).toISOString() else null
      lastWriteAt:    new Date(lastWrite).toISOString()
  }]


# --- stripe: settled PaymentIntents vs the ledger ---------------------------

MONTH_IN_TEXT = /(\d{4})-(0[1-9]|1[0-2])/

# The allocation a PaymentIntent describes, best-effort: the plan stored at
# checkout, then year/month metadata, then a month mentioned in the
# description ("Rent payment for 2026-05", "... covering 2026-05"). Returns
# null when none of these are present — the intent is still checked for
# being linked at all, just not cross-checked against a month.
allocationFor = (intent) ->
  meta = intent.metadata or {}

  if meta.allocation
    try
      return JSON.parse meta.allocation
    catch
      # fall through to the other strategies

  if meta.year and meta.month
    return [ { year: parseInt(meta.year, 10), month: parseInt(meta.month, 10), amount: intent.amount / 100 } ]

  match = (intent.description or '').match MONTH_IN_TEXT
  if match
    return [ { year: parseInt(match[1], 10), month: parseInt(match[2], 10), amount: intent.amount / 100 } ]

  null


checkStripePayments = (deps) ->
  return [] unless deps.stripeEnabled

  intents = await deps.listSucceededPaymentIntents()
  linkedEvents = (e for e in deps.events when e.action is 'payment-made' and e.payload.stripe_payment_intent_id)

  findings = []
  for intent in intents
    matching = (e for e in linkedEvents when e.payload.stripe_payment_intent_id is intent.id)

    if matching.length is 0
      findings.push
        key:      "stripe-unlinked:#{intent.id}"
        kind:     'stripe-unlinked'
        severity: 'warning'
        message:  "Stripe payment #{intent.id} not linked in the ledger"
        detail:
          amount:      intent.amount / 100
          date:        new Date(intent.created * 1000).toISOString()
          description: intent.description
      continue

    allocation = allocationFor intent
    continue unless allocation   # linked but nothing to cross-check against

    allocMonths  = (period.monthKey(a.year, a.month) for a in allocation).sort()
    eventMonths  = (e.effective_for for e in matching).sort()
    allocSum_c   = allocation.reduce ((sum, a) -> sum + money.centsOf a.amount), 0
    eventSum_c   = matching.reduce   ((sum, e) -> sum + money.centsOf e.payload.amount), 0

    sameMonths = allocMonths.length is eventMonths.length and
      allocMonths.every (m, i) -> m is eventMonths[i]

    continue if sameMonths and allocSum_c is eventSum_c

    findings.push
      key:       "stripe-mismatch:#{intent.id}:alloc=#{allocSum_c}:events=#{eventSum_c}:#{allocMonths.join(',')}vs#{eventMonths.join(',')}"
      kind:      'stripe-mismatch'
      severity:  'warning'
      event_ids: (e.id for e in matching)
      message:   "Stripe payment #{intent.id} allocation disagrees with the linked ledger events"
      detail:
        allocated_months: allocMonths
        ledger_months:    eventMonths
        allocated_amount: money.fromCents allocSum_c
        ledger_amount:    money.fromCents eventSum_c
  findings


# --- orchestration -----------------------------------------------------------

# needsLedger marks a check that reads deps.events/deps.periods (the whole
# ledger, loaded and folded once below) rather than the db handle or an
# external service directly. When that load fails (F4), these are the checks
# skipped — the rest (db integrity, foreign keys, backup age) don't need it
# and still run.
CHECKS = [
  { name: 'db-integrity',              run: checkDatabaseIntegrity }
  { name: 'db-foreign-key',            run: checkForeignKeys }
  { name: 'ledger-corrupt-month',      run: checkCorruptMonths,          needsLedger: true }
  { name: 'ledger-effective-for',      run: checkEffectiveFor,           needsLedger: true }
  { name: 'ledger-missing-target',     run: checkTargetEventIds,         needsLedger: true }
  { name: 'ledger-delete-of-delete',   run: checkDeleteOfDelete,         needsLedger: true }
  { name: 'manual-payment-after-pin',  run: checkPaymentAfterPin,        needsLedger: true }
  { name: 'manual-amount-paid-mismatch', run: checkAmountPaidPinMismatch, needsLedger: true }
  { name: 'manual-amount-due-mismatch',  run: checkAmountDuePinMismatch,  needsLedger: true }
  { name: 'backup-stale',              run: checkBackupAge }
  { name: 'stripe',                    run: checkStripePayments,         needsLedger: true }
]


# Load the ledger (every event, folded into periods) once for the checks that
# need it. Kept separate from runChecks's per-check try/catch below: a
# malformed event payload throws from inside JSON.parse (events.coffee's
# hydrate) before any individual check runs, which previously took down the
# whole run — nothing stored, a stale issues page (bug 62, F4). One
# 'ledger-unreadable' finding stands in for every ledger-dependent check; the
# rest still run.
loadLedger = (deps, now) ->
  return { ok: true, events: deps.events, periods: deps.periods, findings: [] } if deps.events? and deps.periods?

  try
    events  = deps.events  ? eventsModel.listAllEvents()
    periods = deps.periods ? period.computeAllPeriods events, now, includeSuppressed: true
    { ok: true, events, periods, findings: [] }
  catch err
    ok:       false
    events:   []
    periods:  {}
    findings: [{
      key:      "ledger-unreadable:#{err.message}"
      kind:     'ledger-unreadable'
      severity: 'error'
      message:  "The ledger could not be read: #{err.message}"
      detail:   { error: err.message }
    }]


# Run every check. A check that throws becomes a single 'error' finding for
# that check rather than aborting the run — see the module comment. `deps`
# lets tests substitute events/periods/db/Stripe/S3 without touching the
# real database or network.
runChecks = (deps = {}) ->
  now    = deps.now ? new Date()
  ledger = loadLedger deps, now

  fullDeps = Object.assign {
    db:                          schema.db
    s3Enabled:                   backupService.S3_ENABLED
    listS3Backups:               backupService.listS3Backups
    lastDataWriteMs:             consistencyModel.lastDataWriteMs
    stripeEnabled:                !!config.STRIPE_SECRET_KEY
    listSucceededPaymentIntents: paymentService.listSucceededPaymentIntents
  }, deps, { events: ledger.events, periods: ledger.periods }

  findings = [].concat ledger.findings
  for check in CHECKS
    continue if check.needsLedger and not ledger.ok
    try
      result = check.run fullDeps
      result = await result if typeof result?.then is 'function'
      findings = findings.concat result
    catch err
      findings.push errorFinding check.name, err
  findings


module.exports = {
  runChecks
  checkDatabaseIntegrity
  checkForeignKeys
  checkCorruptMonths
  checkEffectiveFor
  checkTargetEventIds
  checkDeleteOfDelete
  checkPaymentAfterPin
  checkAmountPaidPinMismatch
  checkAmountDuePinMismatch
  checkBackupAge
  checkStripePayments
  allocationFor
}
