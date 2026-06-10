# Database utility functions for cleaner SQL interactions

{ db } = require './schema.coffee'


formatSQLParameters = (params) ->
  Object.assign {}, ({[":#{k}"]: v} for k, v of params)...


transaction = (fn) ->
  db.exec 'BEGIN'
  try
    result = fn()
    db.exec 'COMMIT'
    result
  catch err
    try
      db.exec 'ROLLBACK'
    throw err


module.exports = {
  formatSQLParameters
  transaction
}
