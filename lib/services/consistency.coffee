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
VALID_MONTH_KEY        = /^\d{4}-(0[1-9]|1[0-2])$/

checkEffectiveFor = (deps) ->
  for e in deps.events when e.action in REQUIRES_EFFECTIVE_FOR
    value = e.effective_for
    continue if value? and VALID_MONTH_KEY.test value

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


checkAmountDuePinMismatch = (deps) ->
  findings = []
  for month, p of deps.periods when p.amount_due_override
    due_c  = money.centsOf p.amount_due
    calc_c = money.centsOf p.amount_due_calculated
    continue if due_c is calc_c

    findings.push
      key:      "manual-amount-due-mismatch:#{month}:pinned=#{due_c}:calculated=#{calc_c}"
      kind:     'manual-amount-due-mismatch'
      severity: 'warning'
      month:    month
      message:  "#{month} amount_due is pinned at #{money.fromCents due_c}, calculated value is #{money.fromCents calc_c}"
      detail:   { pinned: money.fromCents(due_c), calculated: money.fromCents(calc_c) }
  findings


# --- backup: the newest S3 backup vs the newest write -----------------------

checkBackupAge = (deps) ->
  return [] unless deps.s3Enabled

  backups   = await deps.listS3Backups()
  lastWrite = deps.dbLastWriteMs()
  return [] unless lastWrite > 0    # no database file yet (fresh test DB)

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

Stripe = require 'stripe'

defaultListSucceededPaymentIntents = ->
  return [] unless config.STRIPE_SECRET_KEY

  stripeClient  = new Stripe config.STRIPE_SECRET_KEY, apiVersion: '2024-12-18.acacia'
  results       = []
  startingAfter = undefined

  loop
    page = await stripeClient.paymentIntents.list
      limit:          100
      starting_after: startingAfter

    results.push (pi for pi in page.data when pi.status is 'succeeded')...
    break unless page.has_more
    startingAfter = page.data[page.data.length - 1].id

  results


CHECKS = [
  { name: 'db-integrity',              run: checkDatabaseIntegrity }
  { name: 'db-foreign-key',            run: checkForeignKeys }
  { name: 'ledger-corrupt-month',      run: checkCorruptMonths }
  { name: 'ledger-effective-for',      run: checkEffectiveFor }
  { name: 'ledger-missing-target',     run: checkTargetEventIds }
  { name: 'ledger-delete-of-delete',   run: checkDeleteOfDelete }
  { name: 'manual-payment-after-pin',  run: checkPaymentAfterPin }
  { name: 'manual-amount-paid-mismatch', run: checkAmountPaidPinMismatch }
  { name: 'manual-amount-due-mismatch',  run: checkAmountDuePinMismatch }
  { name: 'backup-stale',              run: checkBackupAge }
  { name: 'stripe',                    run: checkStripePayments }
]


# Run every check. A check that throws becomes a single 'error' finding for
# that check rather than aborting the run — see the module comment. `deps`
# lets tests substitute events/periods/db/Stripe/S3 without touching the
# real database or network.
runChecks = (deps = {}) ->
  now     = deps.now ? new Date()
  events  = deps.events  ? eventsModel.listAllEvents()
  periods = deps.periods ? period.computeAllPeriods events, now, includeSuppressed: true

  fullDeps = Object.assign {
    db:                          schema.db
    s3Enabled:                   backupService.S3_ENABLED
    listS3Backups:               backupService.listS3Backups
    dbLastWriteMs:               backupService.dbLastWriteMs
    stripeEnabled:                !!config.STRIPE_SECRET_KEY
    listSucceededPaymentIntents: defaultListSucceededPaymentIntents
  }, deps, { events, periods }

  findings = []
  for check in CHECKS
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
