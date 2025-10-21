# lib/models/auth.coffee

{ v1 }      = await import('uuid')
db          = (await import('../db/schema.coffee')).db
config      = await import('../config.coffee')
emailService = await import('../services/email.coffee')


# Store verification code for email
export storeVerificationCode = (email, code) ->
  id  = v1()
  now = new Date().toISOString()
  expiresAt = new Date(Date.now() + config.CODE_EXPIRY).toISOString()

  db.prepare("""
    INSERT INTO auth_sessions (id, email, code, expires_at, verified, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  """).run(id, email, code, expiresAt, 0, now)

  return db.prepare("SELECT * FROM auth_sessions WHERE id = ?").get(id)


# Get verification code for email
export getVerificationCode = (email) ->
  result = db.prepare("""
    SELECT * FROM auth_sessions
    WHERE email = ? AND verified = 0
    ORDER BY created_at DESC
    LIMIT 1
  """).get(email)

  return result or null


# Verify code for email
export verifyCode = (email, code) ->
  stored = await getVerificationCode(email)

  if not stored
    return success: false, error: 'No verification code found'

  if Date.now() > new Date(stored.expires_at).getTime()
    await deleteVerificationCode(email)
    return success: false, error: 'Verification code expired'

  if stored.code isnt code
    return success: false, error: 'Invalid verification code'

  # Code is valid, mark as verified
  db.prepare("""
    UPDATE auth_sessions
    SET verified = 1
    WHERE id = ?
  """).run(stored.id)

  return success: true


# Delete verification code
export deleteVerificationCode = (email) ->
  db.prepare("""
    DELETE FROM auth_sessions
    WHERE email = ? AND verified = 0
  """).run(email)


# Check if email is allowed
export isEmailAllowed = (email) ->
  normalized = email.toLowerCase().trim()
  allowed = config.ALLOWED_EMAILS.map (e) -> e.toLowerCase().trim()
  return normalized in allowed


# Send verification code to email
export sendVerificationCode = (email) ->
  if not isEmailAllowed(email)
    throw new Error 'Email not authorized'

  code = emailService.generateCode()
  await storeVerificationCode(email, code)
  await emailService.sendVerificationCode(email, code)

  return success: true
