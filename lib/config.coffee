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