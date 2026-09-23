logger       = require '../logger.coffee'
middleware   = require '../middleware.coffee'
tokenService = require '../services/tokenization.coffee'


setup = (app) ->
  # Detokenize endpoint - converts tokenized PII back to original values
  app.post '/admin/detokenize', middleware.requireAdmin, (req, res) ->
    { data } = req.body

    unless data
      return res.status(400).json error: 'Data required'

    try
      detokenized = tokenService.detokenizeObject data
      res.json { detokenized }
    catch err
      logger.error 'admin.detokenize', err,
        { hasData: !!data },
        req.id
      res.status(500).json error: err.message

module.exports = { setup }
