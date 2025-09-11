# lib/models/recurring_events.coffee

{ v1 } = await import('uuid')
db = (await import('../db/schema.coffee')).db
config = await import('../config.coffee')


# Recurring Event Configuration
export createRecurringEvent = (data) ->
  id = v1.generate()

  recurringEvent =
    id: id
    name: data.name
    description: data.description
    event_type: data.event_type  # 'rent_due', 'payment_reminder', 'recalculation', etc.
    frequency: data.frequency    # 'monthly', 'weekly', 'daily', 'yearly'
    day_of_month: data.day_of_month or 1  # For monthly events
    day_of_week: data.day_of_week or null  # For weekly events (0-6, Sunday=0)
    time_of_day: data.time_of_day or '00:00'  # HH:MM format
    enabled: data.enabled ? true
    
    # Template for events to create
    event_template:
      type: data.event_template?.type or 'manual'
      amount: data.event_template?.amount or 0
      description_template: data.event_template?.description_template or ''
      notes_template: data.event_template?.notes_template or ''
      metadata: data.event_template?.metadata or {}
    
    # Scheduling metadata
    last_processed: data.last_processed or null
    next_due: data.next_due or null
    
    created_at: new Date().toISOString()
    updated_at: new Date().toISOString()

  key = ['recurring_events', id]
  await db.set key, recurringEvent

  return recurringEvent


export getAllRecurringEvents = ->
  events = []
  prefix = ['recurring_events']
  entries = db.list({ prefix })

  for await entry from entries
    events.push entry.value

  # Sort by name
  events.sort (a, b) -> a.name.localeCompare(b.name)
  return events


export getRecurringEvent = (id) ->
  key = ['recurring_events', id]
  result = await db.get(key)
  return result.value


export updateRecurringEvent = (id, updates) ->
  key = ['recurring_events', id]
  existing = await db.get(key)

  if not existing.value
    throw new Error "Recurring event not found: #{id}"

  updated = Object.assign({}, existing.value, updates, {
    updated_at: new Date().toISOString()
  })

  await db.set key, updated
  return updated


export deleteRecurringEvent = (id) ->
  key = ['recurring_events', id]
  existing = await db.get(key)

  if not existing.value
    throw new Error "Recurring event not found: #{id}"

  await db.delete(key)
  return existing.value


export getEnabledRecurringEvents = ->
  allEvents = await getAllRecurringEvents()
  return allEvents.filter (event) -> event.enabled


# Event Processing Log
export createProcessingLog = (data) ->
  id = v1.generate()

  logEntry =
    id: id
    recurring_event_id: data.recurring_event_id
    processing_date: data.processing_date or new Date().toISOString()
    events_created: data.events_created or []  # Array of created event IDs
    status: data.status or 'success'  # 'success', 'error', 'skipped'
    message: data.message or null
    error_details: data.error_details or null
    created_at: new Date().toISOString()

  key = ['recurring_event_logs', id]
  await db.set key, logEntry

  return logEntry


export getProcessingLogs = (recurring_event_id = null, limit = 50) ->
  logs = []
  prefix = ['recurring_event_logs']
  entries = db.list({ prefix })

  for await entry from entries
    log = entry.value
    if not recurring_event_id or log.recurring_event_id is recurring_event_id
      logs.push log

  # Sort by processing date descending
  logs.sort (a, b) -> new Date(b.processing_date) - new Date(a.processing_date)
  
  return logs.slice(0, limit)


# Initialize default recurring events
export initializeDefaultRecurringEvents = ->
  existing = await getAllRecurringEvents()
  
  # Check if monthly rent due event already exists
  monthlyRentExists = existing.some (event) -> 
    event.event_type is 'rent_due' and event.frequency is 'monthly'

  unless monthlyRentExists
    await createRecurringEvent
      name: 'Monthly Rent Due'
      description: 'Creates rent due event for each month'
      event_type: 'rent_due'
      frequency: 'monthly'
      day_of_month: 1
      time_of_day: '00:00'
      enabled: true
      event_template:
        type: 'manual'
        amount: -(config.BASE_RENT or 1600)  # Negative because it's money owed
        description_template: 'Rent due for {{month}} {{year}}'
        notes_template: 'Base rent: ${{base_rent}}/month'
        metadata:
          category: 'rent_due'
          recurring: true

    console.log 'Created default monthly rent due recurring event'

  # Check if monthly recalculation event exists
  recalculationExists = existing.some (event) ->
    event.event_type is 'recalculation' and event.frequency is 'monthly'

  unless recalculationExists
    await createRecurringEvent
      name: 'Monthly Rent Recalculation'
      description: 'Triggers rent recalculation each month'
      event_type: 'recalculation'
      frequency: 'monthly'
      day_of_month: 2
      time_of_day: '01:00'
      enabled: true
      event_template:
        type: 'adjustment'
        amount: 0  # Will be calculated dynamically
        description_template: 'Monthly recalculation for {{month}} {{year}}'
        notes_template: 'Automatic recalculation of rent based on work hours'
        metadata:
          category: 'recalculation'
          recurring: true

    console.log 'Created default monthly recalculation recurring event'