# Database utility functions for cleaner SQL interactions

{ db } = require './schema.coffee'


formatSQLParameters = (params) ->
  Object.assign {}, ({[":#{k}"]: v} for k, v of params)...


# Nesting depth, so an inner transaction gets its own savepoint name rather
# than failing the way a second BEGIN would.
depth = 0


# Run fn inside a transaction. SAVEPOINT rather than BEGIN so transactions
# nest; the outermost release is what actually commits.
#
# The callback must be synchronous. node:sqlite is a synchronous API, and an
# async callback would have its COMMIT run before the awaited work did — a
# silent partial commit. Refusing one is louder than pretending it worked.
transaction = (fn) ->
  name = "sp_#{depth}"

  # Opened before the counter moves: if SAVEPOINT throws there is no
  # savepoint to unwind, and a depth that was incremented anyway would leave
  # the next transaction using a name one level too deep.
  db.exec "SAVEPOINT #{name}"
  depth += 1

  try
    result = fn()

    if typeof result?.then is 'function'
      throw new Error 'transaction() callback must be synchronous: node:sqlite is
                       synchronous, so an async callback would commit before its
                       work runs'

    db.exec "RELEASE #{name}"
    result

  catch err
    # Keep the original failure as the thing that surfaces; a rollback that
    # also fails is extra information, not a replacement for it.
    try
      db.exec "ROLLBACK TO #{name}"
      db.exec "RELEASE #{name}"
    catch rollbackErr
      err.rollbackError = rollbackErr.message

    throw err

  finally
    depth -= 1


module.exports = {
  formatSQLParameters
  transaction
}
