# lib/models/auth.coffee

{ db }         = await import('../db/schema.coffee')
config         = await import('../config.coffee')
emailService   = await import('../services/email.coffee')


# Store verification code for email
export storeVerificationCode = (email, code) ->
  key = ['auth_code', email]
  value =
    email:      email
    code:       code
    created_at: Date.now()
    expires_at: Date.now() + config.CODE_EXPIRY

  await db.set key, value
  return value


# Get verification code for email
export getVerificationCode = (email) ->
  key = ['auth_code', email]
  result = await db.get(key)
  return result.value


# Verify code for email
export verifyCode = (email, code) ->
  stored = await getVerificationCode(email)

  if not stored
    return success: false, error: 'No verification code found'

  if Date.now() > stored.expires_at
    await deleteVerificationCode(email)
    return success: false, error: 'Verification code expired'

  if stored.code isnt code
    return success: false, error: 'Invalid verification code'

  # Code is valid, delete it
  await deleteVerificationCode(email)
  return success: true


# Delete verification code
export deleteVerificationCode = (email) ->
  key = ['auth_code', email]
  await db.delete(key)


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
