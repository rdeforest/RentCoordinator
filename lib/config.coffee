# lib/config.coffee

# Environment configuration with sensible defaults

export PORT     = Deno.env.get('PORT')     or 3000
export NODE_ENV = Deno.env.get('NODE_ENV') or 'development'
export DB_PATH  = Deno.env.get('DB_PATH')  or './tenant-coordinator.db'

# Timer configuration
export TIMER_POLL_INTERVAL = 1000  # Client polls every second
export SESSION_TIMEOUT     = 8 * 60 * 60 * 1000  # 8 hours max session

# Worker identities
export WORKERS = ['robert', 'lyndzie']

# Report recipients (can be overridden per project)
export DEFAULT_STAKEHOLDERS = ['robert', 'lyndzie']

# Rent configuration
export BASE_RENT         = 1600  # Base monthly rent
export HOURLY_CREDIT     = 50    # Dollar credit per hour worked
export MAX_MONTHLY_HOURS = 8     # Maximum hours creditable per month (excess rolls over)

# Authentication configuration
export ALLOWED_EMAILS = ['robert@defore.st', 'lynz57@hotmail.com']
export SESSION_SECRET = Deno.env.get('SESSION_SECRET') or 'dev-secret-change-in-production'
export SESSION_MAX_AGE = 30 * 24 * 60 * 60 * 1000  # 30 days
export CODE_EXPIRY = 10 * 60 * 1000  # 10 minutes

# Email configuration (for verification codes)
export SMTP_HOST = Deno.env.get('SMTP_HOST')
export SMTP_PORT = Deno.env.get('SMTP_PORT') or 587
export SMTP_USER = Deno.env.get('SMTP_USER')
export SMTP_PASS = Deno.env.get('SMTP_PASS')
export EMAIL_FROM = Deno.env.get('EMAIL_FROM') or 'noreply@thatsnice.org'