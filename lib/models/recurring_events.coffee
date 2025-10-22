# lib/models/recurring_events.coffee

{ v1 } = await import('uuid')
db = (await import('../db/schema.coffee')).db
config = await import('../config.coffee')


# Recurring Event Configuration
export createRecurringEvent = (data) ->
  id = v1()
  now = new Date().toISOString()

  # Build metadata object from fields not in main schema
  metadata = {
    event_type: data.event_type or 'manual'
    day_of_week: data.day_of_week or null
    time_of_day: data.time_of_day or '00:00'
    event_template: data.event_template or {}
    next_due: data.next_due or null
  }

  # Merge any additional metadata
  if data.metadata
    metadata = Object.assign({}, metadata, data.metadata)

  # Insert recurring event
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

  # Return the created event
  return db.prepare("SELECT * FROM recurring_events WHERE id = ?").get(id)


export getAllRecurringEvents = ->
  events = db.prepare("SELECT * FROM recurring_events").all()

  # Parse metadata JSON for each event
  for event in events
    if event.metadata
      try
        event.metadata = JSON.parse(event.metadata)
      catch e
        event.metadata = {}

    # Extract event_template from metadata to top level
    if event.metadata?.event_template
      event.event_template = event.metadata.event_template

    # Extract next_due from metadata to top level
    if event.metadata?.next_due
      event.next_due = event.metadata.next_due

    # Add legacy field mappings for backwards compatibility
    event.name = event.description
    event.event_type = event.type
    event.enabled = event.active is 1

  # Sort by description
  events.sort (a, b) -> a.description.localeCompare(b.description)
  return events


export getRecurringEvent = (id) ->
  event = db.prepare("SELECT * FROM recurring_events WHERE id = ?").get(id)
  return null unless event

  # Parse metadata JSON
  if event.metadata
    try
      event.metadata = JSON.parse(event.metadata)
    catch e
      event.metadata = {}

  # Extract event_template from metadata to top level
  if event.metadata?.event_template
    event.event_template = event.metadata.event_template

  # Extract next_due from metadata to top level
  if event.metadata?.next_due
    event.next_due = event.metadata.next_due

  # Add legacy field mappings for backwards compatibility
  event.name = event.description
  event.event_type = event.type
  event.enabled = event.active is 1

  return event


export updateRecurringEvent = (id, updates) ->
  existing = await getRecurringEvent(id)

  unless existing
    throw new Error "Recurring event not found: #{id}"

  now = new Date().toISOString()

  # Build update fields
  type        = updates.type or updates.event_type or existing.type
  description = updates.description or updates.name or existing.description
  amount      = updates.amount ? existing.amount
  frequency   = updates.frequency or existing.frequency
  dayOfMonth  = updates.day_of_month ? existing.day_of_month
  startDate   = updates.start_date or existing.start_date
  endDate     = updates.end_date ? existing.end_date
  lastProcessed = updates.last_processed ? existing.last_processed
  active      = if updates.enabled? then (if updates.enabled then 1 else 0) else existing.active

  # Update metadata
  metadata = existing.metadata or {}
  if updates.metadata
    metadata = Object.assign({}, metadata, updates.metadata)
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

  # Update record
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

  # Return updated event
  return await getRecurringEvent(id)


export deleteRecurringEvent = (id) ->
  existing = await getRecurringEvent(id)

  unless existing
    throw new Error "Recurring event not found: #{id}"

  db.prepare("DELETE FROM recurring_events WHERE id = ?").run(id)
  return existing


export getEnabledRecurringEvents = ->
  events = db.prepare("SELECT * FROM recurring_events WHERE active = 1").all()

  # Parse metadata JSON for each event
  for event in events
    if event.metadata
      try
        event.metadata = JSON.parse(event.metadata)
      catch e
        event.metadata = {}

    # Extract event_template from metadata to top level
    if event.metadata?.event_template
      event.event_template = event.metadata.event_template

    # Extract next_due from metadata to top level
    if event.metadata?.next_due
      event.next_due = event.metadata.next_due

    # Add legacy field mappings
    event.name = event.description
    event.event_type = event.type
    event.enabled = event.active is 1

  return events


# Event Processing Log
export createProcessingLog = (data) ->
  id = v1()
  now = new Date().toISOString()

  unless data.period_id
    throw new Error "period_id is required for processing logs"

  # Store additional fields in metadata since schema only has: id, recurring_event_id, period_id, amount, processed_at
  # But we want to preserve: events_created, status, message, error_details
  # We'll need to check if the schema should be extended or use metadata approach

  # For now, insert what we can based on the schema
  db.prepare("""
    INSERT INTO recurring_event_logs (
      id, recurring_event_id, period_id, amount, processed_at
    )
    VALUES (?, ?, ?, ?, ?)
  """).run(
    id,
    data.recurring_event_id,
    data.period_id,
    data.amount or 0,
    data.processing_date or now
  )

  # Return full data structure for backwards compatibility
  return {
    id: id
    recurring_event_id: data.recurring_event_id
    period_id: data.period_id or ''
    amount: data.amount or 0
    processing_date: data.processing_date or now
    events_created: data.events_created or []
    status: data.status or 'success'
    message: data.message or null
    error_details: data.error_details or null
    created_at: now
    processed_at: data.processing_date or now
  }


export getProcessingLogs = (recurring_event_id = null, limit = 50) ->
  logs = if recurring_event_id
    db.prepare("""
      SELECT * FROM recurring_event_logs
      WHERE recurring_event_id = ?
      ORDER BY processed_at DESC
      LIMIT ?
    """).all(recurring_event_id, limit)
  else
    db.prepare("""
      SELECT * FROM recurring_event_logs
      ORDER BY processed_at DESC
      LIMIT ?
    """).all(limit)

  # Add backwards compatibility fields
  for log in logs
    log.processing_date = log.processed_at
    log.events_created = []
    log.status = 'success'
    log.message = null
    log.error_details = null
    log.created_at = log.processed_at

  return logs


# Initialize default recurring events
export initializeDefaultRecurringEvents = ->
  existing = await getAllRecurringEvents()

  # Check if monthly rent due event already exists
  monthlyRentExists = existing.some (event) ->
    event.type is 'rent_due' and event.frequency is 'monthly'

  unless monthlyRentExists
    await createRecurringEvent
      event_type: 'rent_due'
      name: 'Monthly Rent Due'
      description: 'Creates rent due event for each month'
      frequency: 'monthly'
      day_of_month: 1
      time_of_day: '00:00'
      enabled: true
      amount: -(config.BASE_RENT or 1600)  # Negative because it's money owed
      start_date: new Date().toISOString()
      event_template:
        type: 'manual'
        amount: -(config.BASE_RENT or 1600)
        description_template: 'Rent due for {{month}} {{year}}'
        notes_template: 'Base rent: ${{base_rent}}/month'
        metadata:
          category: 'rent_due'
          recurring: true

    console.log 'Created default monthly rent due recurring event'

  # Check if monthly recalculation event exists
  recalculationExists = existing.some (event) ->
    event.type is 'recalculation' and event.frequency is 'monthly'

  unless recalculationExists
    await createRecurringEvent
      event_type: 'recalculation'
      name: 'Monthly Rent Recalculation'
      description: 'Triggers rent recalculation each month'
      frequency: 'monthly'
      day_of_month: 2
      time_of_day: '01:00'
      enabled: true
      amount: 0  # Will be calculated dynamically
      start_date: new Date().toISOString()
      event_template:
        type: 'adjustment'
        amount: 0
        description_template: 'Monthly recalculation for {{month}} {{year}}'
        notes_template: 'Automatic recalculation of rent based on work hours'
        metadata:
          category: 'recalculation'
          recurring: true

    console.log 'Created default monthly recalculation recurring event'
