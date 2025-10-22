# lib/config.coffee

# Environment configuration with sensible defaults

PORT     = process.env.PORT     or 3000
NODE_ENV = process.env.NODE_ENV or 'development'
DB_PATH  = process.env.DB_PATH  or './tenant-coordinator.db'

# Static files directory (different in dev vs production)
STATIC_DIR = if NODE_ENV is 'production' then './dist/static' else './static'

# Timer configuration
TIMER_POLL_INTERVAL     = 1000  # Client polls every second
SESSION_TIMEOUT         = 8 * 60 * 60 * 1000  # 8 hours max session
MIN_WORK_LOG_DURATION   = if NODE_ENV is 'test' then 1 else 60  # Minimum seconds to create work log

# Worker identities
WORKERS = ['robert', 'lyndzie']

# Report recipients (can be overridden per project)
DEFAULT_STAKEHOLDERS = ['robert', 'lyndzie']

# Rent configuration
BASE_RENT         = 1600  # Base monthly rent
HOURLY_CREDIT     = 50    # Dollar credit per hour worked
MAX_MONTHLY_HOURS = 8     # Maximum hours creditable per month (excess rolls over)

# Authentication configuration
ALLOWED_EMAILS = ['robert@defore.st', 'lynz57@hotmail.com']
SESSION_SECRET = process.env.SESSION_SECRET or 'dev-secret-change-in-production'
SESSION_MAX_AGE = 30 * 24 * 60 * 60 * 1000  # 30 days
CODE_EXPIRY = 10 * 60 * 1000  # 10 minutes

# Email configuration (for verification codes)
SMTP_HOST = process.env.SMTP_HOST
SMTP_PORT = process.env.SMTP_PORT or 587
SMTP_USER = process.env.SMTP_USER
SMTP_PASS = process.env.SMTP_PASS
EMAIL_FROM = process.env.EMAIL_FROM or 'noreply@thatsnice.org'

# Stripe configuration (for rent payments)
STRIPE_SECRET_KEY      = process.env.STRIPE_SECRET_KEY
STRIPE_PUBLISHABLE_KEY = process.env.STRIPE_PUBLISHABLE_KEY

module.exports = {
  PORT
  NODE_ENV
  DB_PATH
  STATIC_DIR
  TIMER_POLL_INTERVAL
  SESSION_TIMEOUT
  MIN_WORK_LOG_DURATION
  WORKERS
  DEFAULT_STAKEHOLDERS
  BASE_RENT
  HOURLY_CREDIT
  MAX_MONTHLY_HOURS
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
}