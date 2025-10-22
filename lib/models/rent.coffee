# lib/models/rent.coffee

{ v1 } = require 'uuid'
{ db } = require '../db/schema.coffee'
config = require '../config.coffee'


# Rent period record
createRentPeriod = (data) ->
  id  = v1()
  now = new Date().toISOString()

  db.prepare("""
    INSERT INTO rent_periods (
      id, year, month, base_rent, hourly_credit, max_monthly_hours,
      hours_worked, hours_from_previous, hours_to_next, manual_adjustments,
      amount_due, amount_paid, created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """).run(
    id,
    data.year,
    data.month,
    data.base_rent or config.BASE_RENT or 1600,
    data.hourly_credit or config.HOURLY_CREDIT or 50,
    data.max_monthly_hours or config.MAX_MONTHLY_HOURS or 8,
    data.hours_worked or 0,
    data.hours_from_previous or 0,
    data.hours_to_next or 0,
    data.manual_adjustments or 0,
    data.amount_due,
    data.amount_paid or 0,
    now,
    now
  )

  return db.prepare("SELECT * FROM rent_periods WHERE id = ?").get(id)


getRentPeriod = (year, month) ->
  return db.prepare("""
    SELECT * FROM rent_periods
    WHERE year = ? AND month = ?
  """).get(year, month)


# Get or create rent period - ensures period exists before operations
getOrCreateRentPeriod = (year, month) ->
  existing = getRentPeriod(year, month)
  return existing if existing

  # Create new period with default values
  return await createRentPeriod {
    year:        year
    month:       month
    amount_due:  config.BASE_RENT or 1600  # Will be recalculated later
  }


getAllRentPeriods = ->
  periods = db.prepare("""
    SELECT * FROM rent_periods
    ORDER BY year DESC, month DESC
  """).all()

  return periods


updateRentPeriod = (year, month, updates) ->
  existing = getRentPeriod(year, month)

  if not existing
    throw new Error "Rent period not found: #{year}-#{month}"

  # Build dynamic update query based on provided fields
  fields = []
  values = []

  for key, value of updates
    # Skip non-column fields
    continue if key in ['id', 'created_at']
    fields.push "#{key} = ?"
    values.push value

  # Always update updated_at
  fields.push "updated_at = ?"
  values.push new Date().toISOString()

  # Add WHERE clause values
  values.push year, month

  query = """
    UPDATE rent_periods
    SET #{fields.join(', ')}
    WHERE year = ? AND month = ?
  """

  db.prepare(query).run(values...)

  return getRentPeriod(year, month)


# Rent events for comprehensive tracking
createRentEvent = (data) ->
  id  = v1()
  now = new Date().toISOString()

  # Get period_id from year/month if not provided
  period_id = data.period_id
  if not period_id and data.year and data.month
    period = getRentPeriod(data.year, data.month)
    period_id = period?.id

  if not period_id
    throw new Error "Cannot create rent event: period not found for #{data.year}-#{data.month}"

  db.prepare("""
    INSERT INTO rent_events (id, period_id, type, amount, description, metadata, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  """).run(
    id,
    period_id,
    data.type,
    data.amount,
    data.description or null,
    JSON.stringify(data.metadata or {}),
    now
  )

  # Add audit log entry
  await createAuditLog {
    action:      'create'
    entity_type: 'rent_event'
    entity_id:   id
    old_value:   null
    new_value:   data
    user:        data.created_by or 'user'
  }

  return db.prepare("SELECT * FROM rent_events WHERE id = ?").get(id)


getAllRentEvents = (includeDeleted = false) ->
  # Note: SQLite version doesn't have soft delete in rent_events table
  # This is handled at the application layer if needed
  events = db.prepare("""
    SELECT * FROM rent_events
    ORDER BY created_at DESC
  """).all()

  # Parse metadata JSON
  for event in events
    event.metadata = JSON.parse(event.metadata) if event.metadata

  return events


getRentEvent = (id) ->
  event = db.prepare("SELECT * FROM rent_events WHERE id = ?").get(id)

  if event?.metadata
    event.metadata = JSON.parse(event.metadata)

  return event


updateRentEvent = (id, updates) ->
  existing = getRentEvent(id)

  if not existing
    throw new Error "Rent event not found: #{id}"

  # Build dynamic update query
  fields = []
  values = []

  for key, value of updates
    continue if key in ['id', 'created_at', 'updated_by']
    if key is 'metadata'
      fields.push "metadata = ?"
      values.push JSON.stringify(value)
    else
      fields.push "#{key} = ?"
      values.push value

  # Add WHERE clause value
  values.push id

  query = """
    UPDATE rent_events
    SET #{fields.join(', ')}
    WHERE id = ?
  """

  db.prepare(query).run(values...)

  # Add audit log entry
  await createAuditLog {
    action:      'update'
    entity_type: 'rent_event'
    entity_id:   id
    old_value:   existing
    new_value:   updates
    user:        updates.updated_by or 'user'
  }

  return getRentEvent(id)


deleteRentEvent = (id, deletedBy = 'user') ->
  existing = getRentEvent(id)

  if not existing
    throw new Error "Rent event not found: #{id}"

  # Hard delete in SQLite version - soft delete would require schema change
  db.prepare("DELETE FROM rent_events WHERE id = ?").run(id)

  # Add audit log entry
  await createAuditLog {
    action:      'delete'
    entity_type: 'rent_event'
    entity_id:   id
    old_value:   existing
    new_value:   null
    user:        deletedBy
  }

  return { deleted: true, id: id }


getRentEventsForPeriod = (year, month, includeDeleted = false) ->
  period = getRentPeriod(year, month)

  if not period
    return []

  events = db.prepare("""
    SELECT * FROM rent_events
    WHERE period_id = ?
    ORDER BY created_at DESC
  """).all(period.id)

  # Parse metadata JSON
  for event in events
    event.metadata = JSON.parse(event.metadata) if event.metadata

  return events


# Audit log functionality
createAuditLog = (data) ->
  id  = v1()
  now = new Date().toISOString()

  # Prepare changes object
  changes = {
    old_value: data.old_value or null
    new_value: data.new_value or null
    metadata:  data.metadata or {}
  }

  db.prepare("""
    INSERT INTO audit_logs (id, action, entity_type, entity_id, user, changes, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  """).run(
    id,
    data.action,
    data.entity_type,
    data.entity_id,
    data.user or 'system',
    JSON.stringify(changes),
    now
  )

  return db.prepare("SELECT * FROM audit_logs WHERE id = ?").get(id)


getAuditLogs = (filters = {}) ->
  # Build dynamic WHERE clause
  conditions = []
  values     = []

  if filters.entity_type
    conditions.push "entity_type = ?"
    values.push filters.entity_type

  if filters.entity_id
    conditions.push "entity_id = ?"
    values.push filters.entity_id

  if filters.action
    conditions.push "action = ?"
    values.push filters.action

  if filters.user
    conditions.push "user = ?"
    values.push filters.user

  whereClause = if conditions.length > 0
    "WHERE #{conditions.join(' AND ')}"
  else
    ""

  query = """
    SELECT * FROM audit_logs
    #{whereClause}
    ORDER BY created_at DESC
  """

  logs = db.prepare(query).all(values...)

  # Parse changes JSON
  for log in logs
    log.changes = JSON.parse(log.changes) if log.changes

  return logs

module.exports = {
  createRentPeriod
  getRentPeriod
  getOrCreateRentPeriod
  getAllRentPeriods
  updateRentPeriod
  createRentEvent
  getAllRentEvents
  getRentEvent
  updateRentEvent
  deleteRentEvent
  getRentEventsForPeriod
  createAuditLog
  getAuditLogs
}
