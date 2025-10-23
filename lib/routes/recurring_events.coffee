recurringEventsModel   = require '../models/recurring_events.coffee'
recurringEventsService = require '../services/recurring_events.coffee'


setup = (app) ->
  app.get '/recurring-events', (req, res) ->
    try
      events = await recurringEventsModel.getAllRecurringEvents()
      res.json events
    catch err
      res.status(500).json error: err.message

  app.post '/recurring-events', (req, res) ->
    { name, description, event_type, frequency, day_of_month, day_of_week, time_of_day, enabled, event_template } = req.body

    unless name and event_type and frequency
      return res.status(400).json error: 'Name, event_type, and frequency are required'

    try
      event = await recurringEventsModel.createRecurringEvent
        name:           name
        description:    description
        event_type:     event_type
        frequency:      frequency
        day_of_month:   day_of_month
        day_of_week:    day_of_week
        time_of_day:    time_of_day
        enabled:        enabled
        event_template: event_template

      res.json event
    catch err
      res.status(500).json error: err.message

  app.get '/recurring-events/:id', (req, res) ->
    try
      event = await recurringEventsModel.getRecurringEvent req.params.id

      unless event
        return res.status(404).json error: 'Recurring event not found'

      res.json event
    catch err
      res.status(500).json error: err.message

  app.put '/recurring-events/:id', (req, res) ->
    { name, description, event_type, frequency, day_of_month, day_of_week, time_of_day, enabled, event_template } = req.body

    try
      event = await recurringEventsModel.updateRecurringEvent req.params.id,
        name:           name
        description:    description
        event_type:     event_type
        frequency:      frequency
        day_of_month:   day_of_month
        day_of_week:    day_of_week
        time_of_day:    time_of_day
        enabled:        enabled
        event_template: event_template

      res.json event
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else
        res.status(500).json error: err.message

  app.delete '/recurring-events/:id', (req, res) ->
    try
      deletedEvent = await recurringEventsModel.deleteRecurringEvent req.params.id
      res.json message: 'Recurring event deleted', event: deletedEvent
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else
        res.status(500).json error: err.message

  app.get '/recurring-events/logs/:id?', (req, res) ->
    { limit } = req.query
    recurringEventId = req.params.id or null

    try
      logs = await recurringEventsModel.getProcessingLogs recurringEventId, parseInt(limit) or 50
      res.json logs
    catch err
      res.status(500).json error: err.message

  app.post '/recurring-events/process', (req, res) ->
    try
      results = await recurringEventsService.triggerManualProcessing()
      res.json
        message: 'Recurring events processing triggered'
        results: results
    catch err
      res.status(500).json error: err.message

  app.get '/recurring-events/schedule', (req, res) ->
    try
      events   = await recurringEventsModel.getAllRecurringEvents()
      schedule = events.map (event) ->
        id:             event.id
        name:           event.name
        event_type:     event.event_type
        frequency:      event.frequency
        enabled:        event.enabled
        last_processed: event.last_processed
        next_due:       event.next_due

      res.json schedule
    catch err
      res.status(500).json error: err.message

module.exports = { setup }
