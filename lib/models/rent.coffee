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