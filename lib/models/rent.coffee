# lib/models/rent.coffee

{ v1 } = await import('uuid')
db = (await import('../db/schema.coffee')).db
config = await import('../config.coffee')


# Rent period record
export createRentPeriod = (data) ->
  id = v1.generate()

  rentPeriod =
    id: id
    year: data.year
    month: data.month  # 1-12
    base_rent: config.BASE_RENT or 1600
    hours_worked: data.hours_worked or 0
    hours_from_previous: data.hours_from_previous or 0  # Roll-over hours
    hours_to_next: data.hours_to_next or 0  # Excess hours
    discount_applied: data.discount_applied or 0
    amount_due: data.amount_due
    amount_paid: data.amount_paid or 0
    paid_date: data.paid_date or null
    notes: data.notes or null
    created_at: new Date().toISOString()

  key = ['rent_periods', "#{data.year}-#{String(data.month).padStart(2, '0')}"]
  await db.set key, rentPeriod

  return rentPeriod


export getRentPeriod = (year, month) ->
  key = ['rent_periods', "#{year}-#{String(month).padStart(2, '0')}"]
  result = await db.get(key)
  return result.value


export getAllRentPeriods = ->
  periods = []
  prefix = ['rent_periods']
  entries = db.list({ prefix })

  for await entry from entries
    periods.push entry.value

  # Sort by year and month descending
  periods.sort (a, b) ->
    if a.year != b.year
      b.year - a.year
    else
      b.month - a.month

  return periods


export updateRentPeriod = (year, month, updates) ->
  key = ['rent_periods', "#{year}-#{String(month).padStart(2, '0')}"]
  existing = await db.get(key)

  if not existing.value
    throw new Error "Rent period not found: #{year}-#{month}"

  updated = Object.assign({}, existing.value, updates, {
    updated_at: new Date().toISOString()
  })

  await db.set key, updated
  return updated


# Payment record
export recordPayment = (data) ->
  id = v1.generate()

  payment =
    id: id
    year: data.year
    month: data.month
    amount: data.amount
    payment_date: data.payment_date or new Date().toISOString()
    payment_method: data.payment_method or 'cash'
    notes: data.notes or null
    created_at: new Date().toISOString()

  # Store payment
  paymentKey = ['rent_payments', id]
  await db.set paymentKey, payment

  # Update rent period
  period = await getRentPeriod(data.year, data.month)
  if period
    newPaidAmount = (period.amount_paid or 0) + data.amount
    await updateRentPeriod data.year, data.month,
      amount_paid: newPaidAmount
      paid_date: data.payment_date or new Date().toISOString()

  return payment


export getPaymentsForPeriod = (year, month) ->
  payments = []
  prefix = ['rent_payments']
  entries = db.list({ prefix })

  for await entry from entries
    payment = entry.value
    if payment.year is year and payment.month is month
      payments.push payment

  payments.sort (a, b) -> new Date(a.payment_date) - new Date(b.payment_date)
  return payments


# Rent events for comprehensive tracking
export createRentEvent = (data) ->
  id = v1.generate()

  event =
    id: id
    type: data.type  # 'payment', 'adjustment', 'work_value_change', 'manual'
    date: data.date or new Date().toISOString()
    year: data.year
    month: data.month
    amount: data.amount
    description: data.description
    notes: data.notes or null
    metadata: data.metadata or {}  # For storing type-specific data
    created_at: new Date().toISOString()
    updated_at: new Date().toISOString()

  key = ['rent_events', id]
  await db.set key, event

  # Add audit log entry
  await createAuditLog {
    action: 'create'
    entity_type: 'rent_event'
    entity_id: id
    old_value: null
    new_value: event
    user: data.created_by or 'user'
  }

  return event


export getAllRentEvents = (includeDeleted = false) ->
  events = []
  prefix = ['rent_events']
  entries = db.list({ prefix })

  for await entry from entries
    event = entry.value
    # Skip deleted events unless specifically requested
    if not includeDeleted and event.deleted
      continue
    events.push event

  # Sort by date descending
  events.sort (a, b) -> new Date(b.date) - new Date(a.date)
  return events


export getRentEvent = (id) ->
  key = ['rent_events', id]
  result = await db.get(key)
  return result.value


export updateRentEvent = (id, updates) ->
  key = ['rent_events', id]
  existing = await db.get(key)

  if not existing.value
    throw new Error "Rent event not found: #{id}"

  updated = Object.assign({}, existing.value, updates, {
    updated_at: new Date().toISOString()
  })

  await db.set key, updated

  # Add audit log entry
  await createAuditLog {
    action: 'update'
    entity_type: 'rent_event'
    entity_id: id
    old_value: existing.value
    new_value: updated
    user: updates.updated_by or 'user'
  }

  return updated


export deleteRentEvent = (id, deletedBy = 'user') ->
  key = ['rent_events', id]
  existing = await db.get(key)

  if not existing.value
    throw new Error "Rent event not found: #{id}"

  # Soft delete - mark as deleted instead of removing
  deleted = Object.assign({}, existing.value, {
    deleted: true
    deleted_at: new Date().toISOString()
    deleted_by: deletedBy
    updated_at: new Date().toISOString()
  })

  await db.set key, deleted

  # Add audit log entry
  await createAuditLog {
    action: 'delete'
    entity_type: 'rent_event'
    entity_id: id
    old_value: existing.value
    new_value: deleted
    user: deletedBy
  }

  return deleted


# Undelete a soft-deleted rent event
export undeleteRentEvent = (id, undeletedBy = 'user') ->
  key = ['rent_events', id]
  existing = await db.get(key)

  if not existing.value
    throw new Error "Rent event not found: #{id}"

  if not existing.value.deleted
    throw new Error "Rent event is not deleted: #{id}"

  # Remove deletion markers
  undeleted = Object.assign({}, existing.value)
  delete undeleted.deleted
  delete undeleted.deleted_at
  delete undeleted.deleted_by
  undeleted.updated_at = new Date().toISOString()

  await db.set key, undeleted

  # Add audit log entry
  await createAuditLog {
    action: 'undelete'
    entity_type: 'rent_event'
    entity_id: id
    old_value: existing.value
    new_value: undeleted
    user: undeletedBy
  }

  return undeleted


export getRentEventsForPeriod = (year, month, includeDeleted = false) ->
  events = []
  prefix = ['rent_events']
  entries = db.list({ prefix })

  for await entry from entries
    event = entry.value
    # Skip deleted events unless specifically requested
    if not includeDeleted and event.deleted
      continue
    if event.year is year and event.month is month
      events.push event

  events.sort (a, b) -> new Date(b.date) - new Date(a.date)
  return events


# Audit log functionality
export createAuditLog = (data) ->
  id = v1.generate()

  log =
    id: id
    action: data.action  # 'create', 'update', 'delete', 'undelete'
    entity_type: data.entity_type
    entity_id: data.entity_id
    old_value: data.old_value or null
    new_value: data.new_value or null
    user: data.user or 'system'
    timestamp: new Date().toISOString()
    metadata: data.metadata or {}

  key = ['audit_logs', id]
  await db.set key, log
  return log


export getAuditLogs = (filters = {}) ->
  logs = []
  prefix = ['audit_logs']
  entries = db.list({ prefix })

  for await entry from entries
    log = entry.value

    # Apply filters
    if filters.entity_type and log.entity_type != filters.entity_type
      continue
    if filters.entity_id and log.entity_id != filters.entity_id
      continue
    if filters.action and log.action != filters.action
      continue
    if filters.user and log.user != filters.user
      continue

    logs.push log

  # Sort by timestamp descending
  logs.sort (a, b) -> new Date(b.timestamp) - new Date(a.timestamp)
  return logs