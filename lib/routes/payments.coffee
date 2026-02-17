rentModel = require '../models/rent.coffee'
logger    = require '../logger.coffee'


setup = (app) ->
  # Get all payments across all periods
  app.get '/v1/api/payments', (req, res) ->
    try
      # Get all rent events of type 'payment'
      allEvents = await rentModel.getAllRentEvents()

      payments = allEvents
        .filter (event) -> event.type is 'payment'
        .map (event) ->
          metadata = if typeof event.metadata is 'string'
            try JSON.parse(event.metadata) catch then {}
          else
            event.metadata or {}

          id:             event.id
          period_id:      event.period_id
          year:           event.year
          month:          event.month
          amount:         Math.abs(event.amount)  # Convert negative to positive for display
          description:    event.description
          payment_method: metadata.payment_method or 'unknown'
          payment_date:   metadata.payment_date or event.created_at
          notes:          metadata.notes or ''
          created_at:     event.created_at

      # Sort by payment date (most recent first)
      payments.sort (a, b) ->
        new Date(b.payment_date) - new Date(a.payment_date)

      res.json payments
    catch err
      logger.error 'payments.list', err, {}, req.id
      res.status(500).json error: err.message

  # Update which period a payment applies to
  app.put '/v1/api/payments/:paymentId/reassign', (req, res) ->
    paymentId = req.params.paymentId
    { year, month } = req.body

    unless year and month
      return res.status(400).json error: 'Year and month required'

    try
      # Get the payment event
      payment = await rentModel.getRentEvent paymentId

      unless payment
        return res.status(404).json error: 'Payment not found'

      unless payment.type is 'payment'
        return res.status(400).json error: 'Event is not a payment'

      # Get the target period
      targetPeriod = await rentModel.getRentPeriod parseInt(year), parseInt(month)

      unless targetPeriod
        return res.status(404).json error: "Rent period not found for #{year}-#{month}"

      # Update the payment event (only period_id and description exist on rent_events)
      updated = await rentModel.updateRentEvent paymentId,
        period_id:   targetPeriod.id
        description: "Payment received for #{year}-#{month}"

      res.json updated
    catch err
      logger.error 'payments.reassign', err,
        { paymentId, year, month },
        req.id
      res.status(500).json error: err.message

  # Delete a payment
  app.delete '/v1/api/payments/:paymentId', (req, res) ->
    paymentId = req.params.paymentId

    try
      # Verify it's a payment event
      payment = await rentModel.getRentEvent paymentId

      unless payment
        return res.status(404).json error: 'Payment not found'

      unless payment.type is 'payment'
        return res.status(400).json error: 'Event is not a payment'

      # Delete the event
      result = await rentModel.deleteRentEvent paymentId

      res.json result
    catch err
      logger.error 'payments.delete', err,
        { paymentId },
        req.id
      res.status(500).json error: err.message


module.exports = { setup }
