{ v1 }       = require 'uuid'
{ db }       = require '../db/schema.coffee'
config       = require '../config.coffee'
emailService = require '../services/email.coffee'

# The one rejection /auth/send-code is willing to describe to an
# unauthenticated caller. Everything else is internal detail.
AUTHORIZATION_REJECTION = 'Email not authorized'


{ normalizeEmail, isEmailAllowed, isAdminEmail } = config


# Expired codes are plaintext secrets with no remaining use. Sweeping them
# whenever a new code is issued keeps the table bounded without another timer.
purgeExpiredCodes = ->
  db.prepare("""
    DELETE FROM auth_sessions WHERE expires_at < ?
  """).run new Date().toISOString()


deleteVerificationCode = (email) ->
  db.prepare("""
    DELETE FROM auth_sessions WHERE email = ?
  """).run normalizeEmail email


storeVerificationCode = (email, code) ->
  email     = normalizeEmail email
  id        = v1()
  now       = new Date().toISOString()
  expiresAt = new Date(Date.now() + config.CODE_EXPIRY).toISOString()

  purgeExpiredCodes()

  # Only the newest code is ever checkable (getVerificationCode takes one row),
  # so any earlier one is an unusable plaintext secret. Supersede it.
  deleteVerificationCode email

  db.prepare("""
    INSERT INTO auth_sessions (id, email, code, expires_at, attempts, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  """).run id, email, code, expiresAt, 0, now

  return db.prepare("SELECT * FROM auth_sessions WHERE id = ?").get id


getVerificationCode = (email) ->
  result = db.prepare("""
    SELECT * FROM auth_sessions
    WHERE email = ?
    ORDER BY created_at DESC
    LIMIT 1
  """).get normalizeEmail email

  return result or null


deleteVerificationCodeById = (id) ->
  db.prepare("DELETE FROM auth_sessions WHERE id = ?").run id


verifyCode = (email, code) ->
  email  = normalizeEmail email
  stored = await getVerificationCode email

  unless stored
    return success: false, error: 'No verification code found'

  if Date.now() > new Date(stored.expires_at).getTime()
    deleteVerificationCodeById stored.id
    return success: false, error: 'Verification code expired'

  unless stored.code is code
    attempts = (stored.attempts ? 0) + 1

    # A six-digit code is only expensive to guess if wrong guesses cost
    # something. Burning the code after a few misses forces the attacker
    # back through /auth/send-code, which is itself throttled.
    if attempts >= config.MAX_VERIFY_ATTEMPTS
      deleteVerificationCodeById stored.id
      return success: false, error: 'Too many incorrect attempts. Request a new code.'

    db.prepare("UPDATE auth_sessions SET attempts = ? WHERE id = ?").run attempts, stored.id
    return success: false, error: 'Invalid verification code'

  # The session cookie keeps the user logged in from here; the row is a spent
  # secret with nothing left to authorize.
  deleteVerificationCodeById stored.id

  return success: true


sendVerificationCode = (email) ->
  email = normalizeEmail email

  unless isEmailAllowed email
    throw new Error AUTHORIZATION_REJECTION

  code = emailService.generateCode()
  await storeVerificationCode email, code
  await emailService.sendVerificationCode email, code

  return success: true

module.exports = {
  AUTHORIZATION_REJECTION
  normalizeEmail
  purgeExpiredCodes
  storeVerificationCode
  getVerificationCode
  verifyCode
  deleteVerificationCode
  isEmailAllowed
  isAdminEmail
  sendVerificationCode
}
