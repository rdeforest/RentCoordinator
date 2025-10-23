{ v1 }       = require 'uuid'
{ db }       = require '../db/schema.coffee'
config       = require '../config.coffee'
emailService = require '../services/email.coffee'


storeVerificationCode = (email, code) ->
  id        = v1()
  now       = new Date().toISOString()
  expiresAt = new Date(Date.now() + config.CODE_EXPIRY).toISOString()

  db.prepare("""
    INSERT INTO auth_sessions (id, email, code, expires_at, verified, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  """).run id, email, code, expiresAt, 0, now

  return db.prepare("SELECT * FROM auth_sessions WHERE id = ?").get id


getVerificationCode = (email) ->
  result = db.prepare("""
    SELECT * FROM auth_sessions
    WHERE email = ? AND verified = 0
    ORDER BY created_at DESC
    LIMIT 1
  """).get email

  return result or null


verifyCode = (email, code) ->
  stored = await getVerificationCode email

  unless stored
    return success: false, error: 'No verification code found'

  if Date.now() > new Date(stored.expires_at).getTime()
    await deleteVerificationCode email
    return success: false, error: 'Verification code expired'

  unless stored.code is code
    return success: false, error: 'Invalid verification code'

  db.prepare("""
    UPDATE auth_sessions
    SET verified = 1
    WHERE id = ?
  """).run stored.id

  return success: true


deleteVerificationCode = (email) ->
  db.prepare("""
    DELETE FROM auth_sessions
    WHERE email = ? AND verified = 0
  """).run email


isEmailAllowed = (email) ->
  normalized = email.toLowerCase().trim()
  allowed    = config.ALLOWED_EMAILS.map (e) -> e.toLowerCase().trim()
  return normalized in allowed


sendVerificationCode = (email) ->
  unless isEmailAllowed email
    throw new Error 'Email not authorized'

  code = emailService.generateCode()
  await storeVerificationCode email, code
  await emailService.sendVerificationCode email, code

  return success: true

module.exports = {
  storeVerificationCode
  getVerificationCode
  verifyCode
  deleteVerificationCode
  isEmailAllowed
  sendVerificationCode
}
