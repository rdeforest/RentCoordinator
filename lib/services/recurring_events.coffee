recurringEventsModel = require '../models/recurring_events.coffee'
rentModel            = require '../models/rent.coffee'
rentService          = require './rent.coffee'
config               = require '../config.coffee'


calculateNextDueDate = (recurringEvent, fromDate = new Date()) ->
  switch recurringEvent.frequency
    when 'daily'
      nextDate = new Date fromDate
      nextDate.setDate nextDate.getDate() + 1
      return nextDate

    when 'weekly'
      nextDate         = new Date fromDate
      currentDayOfWeek = nextDate.getDay()
      targetDayOfWeek  = recurringEvent.day_of_week or 0

      daysToAdd = (targetDayOfWeek - currentDayOfWeek + 7) % 7
      if daysToAdd is 0 and nextDate.getTime() <= fromDate.getTime()
        daysToAdd = 7

      nextDate.setDate nextDate.getDate() + daysToAdd
      return nextDate

    when 'monthly'
      nextDate = new Date fromDate
      nextDate.setDate recurringEvent.day_of_month or 1

      if nextDate.getTime() <= fromDate.getTime()
        nextDate.setMonth nextDate.getMonth() + 1
        nextDate.setDate recurringEvent.day_of_month or 1

      return nextDate

    when 'yearly'
      nextDate = new Date fromDate
      nextDate.setFullYear nextDate.getFullYear() + 1
      return nextDate

    else
      throw new Error "Unknown frequency: #{recurringEvent.frequency}"


isEventDue = (recurringEvent, currentDate = new Date()) ->
  if not recurringEvent.enabled
    return false

  if not recurringEvent.next_due
    return true

  nextDue = new Date recurringEvent.next_due
  return currentDate >= nextDue


processRecurringEvent = (recurringEvent, currentDate = new Date()) ->
  year   = currentDate.getFullYear()
  month  = currentDate.getMonth() + 1
  period = await rentModel.getOrCreateRentPeriod year, month

  try
    eventsCreated = []

    switch recurringEvent.event_type
      when 'rent_due'
        eventId = await processRentDueEvent recurringEvent, currentDate
        if eventId
          eventsCreated.push eventId

      when 'recalculation'
        await processRecalculationEvent recurringEvent, currentDate

      else
        eventId = await processGenericEvent recurringEvent, currentDate
        if eventId
          eventsCreated.push eventId

    nextDue = calculateNextDueDate recurringEvent, currentDate
    await recurringEventsModel.updateRecurringEvent recurringEvent.id,
      last_processed: currentDate.toISOString()
      next_due:       nextDue.toISOString()

    await recurringEventsModel.createProcessingLog
      recurring_event_id: recurringEvent.id
      period_id:          period.id
      processing_date:    currentDate.toISOString()
      events_created:     eventsCreated
      status:             'success'
      message:            "Successfully processed #{recurringEvent.name}"

    return success: true, events_created: eventsCreated

  catch error
    await recurringEventsModel.createProcessingLog
      recurring_event_id: recurringEvent.id
      period_id:          period.id
      processing_date:    currentDate.toISOString()
      events_created:     []
      status:             'error'
      message:            "Error processing #{recurringEvent.name}"
      error_details:      error.message

    console.error "Error processing recurring event #{recurringEvent.name}:", error
    return success: false, error: error.message


processRentDueEvent = (recurringEvent, currentDate) ->
  year  = currentDate.getFullYear()
  month = currentDate.getMonth() + 1

  existingEvents = await rentModel.getRentEventsForPeriod year, month
  rentDueExists  = existingEvents.some (event) ->
    event.type is 'manual' and
    event.metadata?.category is 'rent_due' and
    event.amount < 0

  if rentDueExists
    console.log "Rent due event already exists for #{year}-#{month}, skipping"
    return null

  monthName = new Date(year, month - 1).toLocaleDateString 'en-US', month: 'long'
  baseRent  = config.BASE_RENT or 1600

  description = recurringEvent.event_template.description_template
    .replace('{{month}}', monthName)
    .replace('{{year}}', year.toString())

  notes = recurringEvent.event_template.notes_template
    .replace('{{base_rent}}', baseRent.toString())
    .replace('{{month}}', monthName)
    .replace('{{year}}', year.toString())

  event = await rentModel.createRentEvent
    type:        recurringEvent.event_template.type
    date:        currentDate.toISOString()
    year:        year
    month:       month
    amount:      recurringEvent.event_template.amount
    description: description
    notes:       notes
    metadata:    Object.assign {}, recurringEvent.event_template.metadata,
      generated_by_recurring_event: recurringEvent.id
      generated_at:                 currentDate.toISOString()

  console.log "Created rent due event for #{year}-#{month}: #{event.id}"
  return event.id


processRecalculationEvent = (recurringEvent, currentDate) ->
  year  = currentDate.getFullYear()
  month = currentDate.getMonth() + 1

  console.log "Processing rent recalculation for #{year}-#{month}"

  await rentService.recalculateAllRent()

  console.log "Completed rent recalculation"


processGenericEvent = (recurringEvent, currentDate) ->
  year  = currentDate.getFullYear()
  month = currentDate.getMonth() + 1

  description = recurringEvent.event_template.description_template
    .replace('{{month}}', new Date(year, month - 1).toLocaleDateString 'en-US', month: 'long')
    .replace('{{year}}', year.toString())

  notes = recurringEvent.event_template.notes_template
    .replace('{{month}}', new Date(year, month - 1).toLocaleDateString 'en-US', month: 'long')
    .replace('{{year}}', year.toString())

  event = await rentModel.createRentEvent
    type:        recurringEvent.event_template.type
    date:        currentDate.toISOString()
    year:        year
    month:       month
    amount:      recurringEvent.event_template.amount
    description: description
    notes:       notes
    metadata:    Object.assign {}, recurringEvent.event_template.metadata,
      generated_by_recurring_event: recurringEvent.id
      generated_at:                 currentDate.toISOString()

  return event.id


processAllDueEvents = (currentDate = new Date()) ->
  try
    console.log "Checking for due recurring events at #{currentDate.toISOString()}"

    recurringEvents = await recurringEventsModel.getEnabledRecurringEvents()
    results         = []

    for recurringEvent in recurringEvents
      if isEventDue recurringEvent, currentDate
        console.log "Processing due recurring event: #{recurringEvent.name}"
        result = await processRecurringEvent recurringEvent, currentDate
        results.push Object.assign { recurring_event: recurringEvent.name }, result
      else
        console.log "Recurring event not due: #{recurringEvent.name} (next due: #{recurringEvent.next_due})"

    console.log "Completed processing #{results.length} recurring events"
    return results

  catch error
    console.error "Error processing recurring events:", error
    throw error


initializeRecurringEvents = ->
  try
    console.log "Initializing recurring events system..."

    await recurringEventsModel.initializeDefaultRecurringEvents()

    allEvents = await recurringEventsModel.getAllRecurringEvents()

    for event in allEvents
      if not event.next_due
        nextDue = calculateNextDueDate event
        await recurringEventsModel.updateRecurringEvent event.id,
          next_due: nextDue.toISOString()
        console.log "Set next due date for #{event.name}: #{nextDue.toISOString()}"

    await processAllDueEvents()

    console.log "Recurring events system initialized"

  catch error
    console.error "Error initializing recurring events:", error
    throw error


scheduleDailyProcessing = ->
  now      = new Date()
  tomorrow = new Date now
  tomorrow.setDate tomorrow.getDate() + 1
  tomorrow.setHours 0, 1, 0, 0

  timeUntilTomorrow = tomorrow.getTime() - now.getTime()

  console.log "Scheduling next recurring events check for #{tomorrow.toISOString()}"

  setTimeout ->
    processAllDueEvents()

    setInterval ->
      processAllDueEvents()
    , 24 * 60 * 60 * 1000

  , timeUntilTomorrow


triggerManualProcessing = ->
  console.log "Manual recurring events processing triggered"
  return await processAllDueEvents()

module.exports = {
  processAllDueEvents
  initializeRecurringEvents
  scheduleDailyProcessing
  triggerManualProcessing
}
