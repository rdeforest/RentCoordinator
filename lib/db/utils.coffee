# Database utility functions for cleaner SQL interactions

formatSQLParameters = (params) ->
  Object.assign {}, ({[":#{k}"]: v} for k, v of params)...

module.exports = {
  formatSQLParameters
}
