{ v4: uuidv4 } = require 'uuid'
{ db }         = require '../db/schema.coffee'

CONFIG_ID = 'singleton'  # Only one configuration row

getConfiguration = ->
  config = db.prepare("SELECT * FROM rent_configuration WHERE id = ?").get CONFIG_ID

  unless config
    # Create default configuration
    now = new Date().toISOString()
    db.prepare("""
      INSERT INTO rent_configuration (id, temporary_base_rent, apply_to_new_periods, created_at, updated_at)
      VALUES (?, NULL, 0, ?, ?)
    """).run CONFIG_ID, now, now

    config = db.prepare("SELECT * FROM rent_configuration WHERE id = ?").get CONFIG_ID

  return config

updateConfiguration = (updates) ->
  now = new Date().toISOString()

  # Ensure config exists
  getConfiguration()

  # Build update query dynamically based on provided fields
  fields = []
  values = []

  if updates.temporary_base_rent?
    fields.push 'temporary_base_rent = ?'
    values.push updates.temporary_base_rent

  if updates.apply_to_new_periods?
    fields.push 'apply_to_new_periods = ?'
    values.push if updates.apply_to_new_periods then 1 else 0

  return getConfiguration() if fields.length is 0

  fields.push 'updated_at = ?'
  values.push now
  values.push CONFIG_ID

  db.prepare("""
    UPDATE rent_configuration
    SET #{fields.join ', '}
    WHERE id = ?
  """).run values...

  return getConfiguration()

module.exports = { getConfiguration, updateConfiguration }
