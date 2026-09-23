PORT     = process.env.PORT     or 3000
NODE_ENV = process.env.NODE_ENV or 'development'
DB_PATH  = process.env.DB_PATH  or './tenant-coordinator.db'

STATIC_DIR = './static'

TIMER_POLL_INTERVAL   = 1000
SESSION_TIMEOUT       = 8 * 60 * 60 * 1000
MIN_WORK_LOG_DURATION = if NODE_ENV is 'test' then 1 else 60

# Auto-backup once the DB has changed but gone quiet (no writes) for this
# long — catches data between the nightly cron backups.
BACKUP_IDLE_MS       = 60 * 60 * 1000    # 1h of write-inactivity
BACKUP_IDLE_CHECK_MS = 10 * 60 * 1000    # check every 10 min

WORKERS              = ['robert', 'lyndzie']
DEFAULT_STAKEHOLDERS = ['robert', 'lyndzie']

# Who each worker is in the rent event model. A created work log emits a
# work-reported event under this identity; only 'tenant' hours credit rent
# (see lib/services/period.coffee). Mirrors the seed migration's mapping so
# live and seeded events agree.
LANDLORD_EMAIL = 'robert@defore.st'
TENANT_EMAIL   = 'lynz57@hotmail.com'

WORKER_IDENTITY =
  robert:  { actor: 'landlord', user: LANDLORD_EMAIL }
  lyndzie: { actor: 'tenant',   user: TENANT_EMAIL }

isTenant = (worker) -> WORKER_IDENTITY[worker]?.actor is 'tenant'


BASE_RENT              = 1600
HOURLY_CREDIT          = 50
MAX_MONTHLY_HOURS      = 8
AGREED_MONTHLY_PAYMENT = 950
RENT_DUE_DAY           = 15

ALLOWED_EMAILS  = [LANDLORD_EMAIL, TENANT_EMAIL]

# The landlord. Admin routes (detokenize, log tail) are restricted to this
# list; the tenant is authenticated but not an admin.
ADMIN_EMAILS    = [LANDLORD_EMAIL]

# One spelling of an address, everywhere. SQLite's `=` is case-sensitive, so
# storing one casing and querying another silently loses the row, and the
# same person would otherwise get two different PII tokens.
normalizeEmail = (email) -> String(email ? '').toLowerCase().trim()

memberOf = (list) ->
  normalized = list.map (e) -> normalizeEmail e
  (email) -> normalizeEmail(email) in normalized

isEmailAllowed = memberOf ALLOWED_EMAILS
isAdminEmail   = memberOf ADMIN_EMAILS

LOCAL_ENVS = ['development', 'test']

# Session cookies are only as secret as this key, so the repo no longer
# contains one to fall back to. Outside dev/test an unset SESSION_SECRET is a
# refusal to boot; in dev/test it is a fresh random key per process, which
# costs nothing but "you have to log in again after a restart" and cannot be
# a bypass the way a published constant was.
#
# The check reads process.env.NODE_ENV rather than the defaulted NODE_ENV on
# purpose: an unset NODE_ENV is a misconfiguration, not a declaration that
# this is a laptop.
SESSION_SECRET = process.env.SESSION_SECRET
unless SESSION_SECRET
  unless process.env.NODE_ENV in LOCAL_ENVS
    throw new Error "SESSION_SECRET must be set unless NODE_ENV is one of
                     #{LOCAL_ENVS.join ', '} (NODE_ENV is
                     #{process.env.NODE_ENV ? 'unset'})"

  SESSION_SECRET = require('node:crypto').randomBytes(32).toString 'hex'
  console.warn "SESSION_SECRET is unset; generated an ephemeral one for
                #{NODE_ENV}. Sessions will not survive a restart."

SESSION_MAX_AGE = 90 * 24 * 60 * 60 * 1000
CODE_EXPIRY     = 10 * 60 * 1000

# Login throttling. The code is six digits, so guessing is only expensive if
# each wrong guess costs something: five misses burn the code, and each caller
# gets a bounded number of tries per window.
#
# The budget is keyed on (client address, email) rather than on the email
# alone. An email-only bucket is an unauthenticated lockout: both addresses
# are public, so anyone could spend the real user's budget from anywhere and
# keep them logged out indefinitely. Keying on the caller means an attacker
# can only exhaust their own.
#
# The per-address totals are looser still, because both users live in the same
# house and share a public address — throttling them against each other would
# be a self-inflicted outage. That bucket exists to bound memory against a
# spray across made-up emails.
MAX_VERIFY_ATTEMPTS = 5

VERIFY_RATE_LIMIT    = 10
VERIFY_IP_LIMIT      = 60
VERIFY_RATE_WINDOW   = 10 * 60 * 1000

SEND_CODE_LIMIT      = 5
SEND_CODE_IP_LIMIT   = 30
SEND_CODE_WINDOW     = 10 * 60 * 1000

# Cross-origin callers. The app is same-origin; set CORS_ORIGINS only if a
# real cross-origin client ever appears.
CORS_ORIGINS = (process.env.CORS_ORIGINS or '')
  .split(',')
  .map((o) -> o.trim())
  .filter((o) -> o.length > 0)

SMTP_HOST = process.env.SMTP_HOST
SMTP_PORT = process.env.SMTP_PORT or 587
SMTP_USER = process.env.SMTP_USER
SMTP_PASS = process.env.SMTP_PASS
EMAIL_FROM = process.env.EMAIL_FROM or 'noreply@thatsnice.org'

STRIPE_SECRET_KEY      = process.env.STRIPE_SECRET_KEY
STRIPE_PUBLISHABLE_KEY = process.env.STRIPE_PUBLISHABLE_KEY
STRIPE_WEBHOOK_SECRET  = process.env.STRIPE_WEBHOOK_SECRET


module.exports = {
  PORT
  NODE_ENV
  DB_PATH
  STATIC_DIR
  TIMER_POLL_INTERVAL
  SESSION_TIMEOUT
  MIN_WORK_LOG_DURATION
  BACKUP_IDLE_MS
  BACKUP_IDLE_CHECK_MS
  WORKERS
  DEFAULT_STAKEHOLDERS
  WORKER_IDENTITY
  LANDLORD_EMAIL
  TENANT_EMAIL
  isTenant
  BASE_RENT
  HOURLY_CREDIT
  MAX_MONTHLY_HOURS
  AGREED_MONTHLY_PAYMENT
  RENT_DUE_DAY
  ALLOWED_EMAILS
  ADMIN_EMAILS
  normalizeEmail
  isEmailAllowed
  isAdminEmail
  SESSION_SECRET
  SESSION_MAX_AGE
  CODE_EXPIRY
  MAX_VERIFY_ATTEMPTS
  VERIFY_RATE_LIMIT
  VERIFY_IP_LIMIT
  VERIFY_RATE_WINDOW
  SEND_CODE_LIMIT
  SEND_CODE_IP_LIMIT
  SEND_CODE_WINDOW
  CORS_ORIGINS
  SMTP_HOST
  SMTP_PORT
  SMTP_USER
  SMTP_PASS
  EMAIL_FROM
  STRIPE_SECRET_KEY
  STRIPE_PUBLISHABLE_KEY
  STRIPE_WEBHOOK_SECRET
}
