{ v1 } = require 'uuid'
logger = require '../logger.coffee'
{ db } = require '../db/schema.coffee'
config = require '../config.coffee'


createRecurringEvent = (data) ->
  id  = v1()
  now = new Date().toISOString()

  metadata =
    event_type:     data.event_type or 'manual'
    day_of_week:    data.day_of_week or null
    time_of_day:    data.time_of_day or '00:00'
    event_template: data.event_template or {}
    next_due:       data.next_due or null

  if data.metadata
    metadata = Object.assign {}, metadata, data.metadata

  db.prepare("""
    INSERT INTO recurring_events (
      id, type, description, amount, frequency, day_of_month,
      start_date, end_date, last_processed, active, metadata,
      created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """).run(
    id,
    data.event_type or data.type or 'manual',
    data.description or data.name or '',
    data.amount or data.event_template?.amount or 0,
    data.frequency or 'monthly',
    data.day_of_month or 1,
    data.start_date or now,
    data.end_date or null,
    data.last_processed or null,
    if (data.enabled ? true) then 1 else 0,
    JSON.stringify(metadata),
    now,
    now
  )

  return db.prepare("SELECT * FROM recurring_events WHERE id = ?").get id


getAllRecurringEvents = ->
  events = db.prepare("SELECT * FROM recurring_events").all()

  for event in events
    if event.metadata
      try
        event.metadata = JSON.parse event.metadata
      catch e
        event.metadata = {}

    if event.metadata?.event_template
      event.event_template = event.metadata.event_template

    if event.metadata?.next_due
      event.next_due = event.metadata.next_due

    event.name       = event.description
    event.event_type = event.type
    event.enabled    = event.active is 1

  events.sort (a, b) -> a.description.localeCompare b.description
  return events


getRecurringEvent = (id) ->
  event = db.prepare("SELECT * FROM recurring_events WHERE id = ?").get id
  return null unless event

  if event.metadata
    try
      event.metadata = JSON.parse event.metadata
    catch e
      event.metadata = {}

  if event.metadata?.event_template
    event.event_template = event.metadata.event_template

  if event.metadata?.next_due
    event.next_due = event.metadata.next_due

  event.name       = event.description
  event.event_type = event.type
  event.enabled    = event.active is 1

  return event


updateRecurringEvent = (id, updates) ->
  existing = await getRecurringEvent id

  unless existing
    throw new Error "Recurring event not found: #{id}"

  now = new Date().toISOString()

  type          = updates.type or updates.event_type or existing.type
  description   = updates.description or updates.name or existing.description
  amount        = updates.amount ? existing.amount
  frequency     = updates.frequency or existing.frequency
  dayOfMonth    = updates.day_of_month ? existing.day_of_month
  startDate     = updates.start_date or existing.start_date
  endDate       = updates.end_date ? existing.end_date
  lastProcessed = updates.last_processed ? existing.last_processed
  active        = if updates.enabled? then (if updates.enabled then 1 else 0) else existing.active

  metadata = existing.metadata or {}
  if updates.metadata
    metadata = Object.assign {}, metadata, updates.metadata
  if updates.event_type
    metadata.event_type = updates.event_type
  if updates.day_of_week?
    metadata.day_of_week = updates.day_of_week
  if updates.time_of_day
    metadata.time_of_day = updates.time_of_day
  if updates.event_template
    metadata.event_template = updates.event_template
  if updates.next_due
    metadata.next_due = updates.next_due

  db.prepare("""
    UPDATE recurring_events
    SET type = ?, description = ?, amount = ?, frequency = ?, day_of_month = ?,
        start_date = ?, end_date = ?, last_processed = ?, active = ?,
        metadata = ?, updated_at = ?
    WHERE id = ?
  """).run(
    type,
    description,
    amount,
    frequency,
    dayOfMonth,
    startDate,
    endDate,
    lastProcessed,
    active,
    JSON.stringify(metadata),
    now,
    id
  )

  return await getRecurringEvent id


deleteRecurringEvent = (id) ->
  existing = await getRecurringEvent id

  unless existing
    throw new Error "Recurring event not found: #{id}"

  db.prepare("DELETE FROM recurring_events WHERE id = ?").run id
  return existing


getEnabledRecurringEvents = ->
  events = db.prepare("SELECT * FROM recurring_events WHERE active = 1").all()

  for event in events
    if event.metadata
      try
        event.metadata = JSON.parse event.metadata
      catch e
        event.metadata = {}

    if event.metadata?.event_template
      event.event_template = event.metadata.event_template

    if event.metadata?.next_due
      event.next_due = event.metadata.next_due

    event.name       = event.description
    event.event_type = event.type
    event.enabled    = event.active is 1

  return events


# null, not [] — the same shape `status` uses for "this row predates the
# column". An empty list would say "this run created nothing", which is a
# claim, and inventing claims about what happened is the defect the outcome
# columns were added to fix.
parseEventsCreated = (log) ->
  return null unless log.events_created

  try
    JSON.parse log.events_created
  catch err
    logger.error 'recurringEvents.parseEventsCreated', err,
      { logId: log.id, stored: log.events_created }
    null


# Rows written before the outcome columns existed report status null — an
# honest "unknown" rather than the hardcoded 'success' that used to be
# invented on read, which made a run that threw look like one that worked.
hydrateProcessingLog = (log) ->
  return log unless log

  log.processing_date = log.processed_at
  log.created_at      = log.processed_at
  log.events_created  = parseEventsCreated log
  log


createProcessingLog = (data) ->
  id  = v1()
  now = new Date().toISOString()

  unless data.period_id
    throw new Error "period_id is required for processing logs"

  db.prepare("""
    INSERT INTO recurring_event_logs (
      id, recurring_event_id, period_id, amount,
      status, message, error_details, events_created, processed_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  """).run(
    id,
    data.recurring_event_id,
    data.period_id,
    data.amount or 0,
    data.status or 'success',
    data.message or null,
    data.error_details or null,
    JSON.stringify(data.events_created or []),
    data.processing_date or now
  )

  return hydrateProcessingLog db.prepare("""
    SELECT * FROM recurring_event_logs WHERE id = ?
  """).get id


getProcessingLogs = (recurring_event_id = null, limit = 50) ->
  logs = if recurring_event_id
    db.prepare("""
      SELECT * FROM recurring_event_logs
      WHERE recurring_event_id = ?
      ORDER BY processed_at DESC
      LIMIT ?
    """).all recurring_event_id, limit
  else
    db.prepare("""
      SELECT * FROM recurring_event_logs
      ORDER BY processed_at DESC
      LIMIT ?
    """).all limit

  hydrateProcessingLog log for log in logs


initializeDefaultRecurringEvents = ->
  existing = await getAllRecurringEvents()

  monthlyRentExists = existing.some (event) ->
    event.type is 'rent_due' and event.frequency is 'monthly'

  unless monthlyRentExists
    await createRecurringEvent
      event_type:   'rent_due'
      name:         'Monthly Rent Due'
      description:  'Creates rent due event for each month'
      frequency:    'monthly'
      day_of_month: 1
      time_of_day:  '00:00'
      enabled:      true
      amount:       -config.BASE_RENT
      start_date:   new Date().toISOString()
      event_template:
        type:                 'manual'
        amount:               -(config.BASE_RENT or 1600)
        description_template: 'Rent due for {{month}} {{year}}'
        notes_template:       'Base rent: ${{base_rent}}/month'
        metadata:
          category:  'rent_due'
          recurring: true

    console.log 'Created default monthly rent due recurring event'

  recalculationExists = existing.some (event) ->
    event.type is 'recalculation' and event.frequency is 'monthly'

  unless recalculationExists
    await createRecurringEvent
      event_type:   'recalculation'
      name:         'Monthly Rent Recalculation'
      description:  'Triggers rent recalculation each month'
      frequency:    'monthly'
      day_of_month: 2
      time_of_day:  '01:00'
      enabled:      true
      amount:       0
      start_date:   new Date().toISOString()
      event_template:
        type:                 'adjustment'
        amount:               0
        description_template: 'Monthly recalculation for {{month}} {{year}}'
        notes_template:       'Automatic recalculation of rent based on work hours'
        metadata:
          category:  'recalculation'
          recurring: true

    console.log 'Created default monthly recalculation recurring event'

module.exports = {
  createRecurringEvent
  getAllRecurringEvents
  getRecurringEvent
  updateRecurringEvent
  deleteRecurringEvent
  getEnabledRecurringEvents
  createProcessingLog
  getProcessingLogs
  initializeDefaultRecurringEvents
}
