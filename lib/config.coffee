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
WORKER_IDENTITY =
  robert:  { actor: 'landlord', user: 'robert@defore.st' }
  lyndzie: { actor: 'tenant',   user: 'lynz57@hotmail.com' }

BASE_RENT              = 1600
HOURLY_CREDIT          = 50
MAX_MONTHLY_HOURS      = 8
AGREED_MONTHLY_PAYMENT = 950
RENT_DUE_DAY           = 15

ALLOWED_EMAILS  = ['robert@defore.st', 'lynz57@hotmail.com']
SESSION_SECRET  = process.env.SESSION_SECRET or 'dev-secret-change-in-production'
SESSION_MAX_AGE = 90 * 24 * 60 * 60 * 1000
CODE_EXPIRY     = 10 * 60 * 1000

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
  BASE_RENT
  HOURLY_CREDIT
  MAX_MONTHLY_HOURS
  AGREED_MONTHLY_PAYMENT
  RENT_DUE_DAY
  ALLOWED_EMAILS
  SESSION_SECRET
  SESSION_MAX_AGE
  CODE_EXPIRY
  SMTP_HOST
  SMTP_PORT
  SMTP_USER
  SMTP_PASS
  EMAIL_FROM
  STRIPE_SECRET_KEY
  STRIPE_PUBLISHABLE_KEY
  STRIPE_WEBHOOK_SECRET
}
