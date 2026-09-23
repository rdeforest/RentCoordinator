# Fixed-window request counter, in-process.
#
# This app runs a single instance per box for two users, so a shared store
# (Redis, a DB table) would be more machinery than the threat model needs.
# The tradeoff is explicit: counters reset on restart, and a multi-instance
# deployment would count per instance. For throttling a six-digit login code
# that is already burned after MAX_VERIFY_ATTEMPTS misses, that is enough.

MAX_KEYS = 10000

# Evicting one key per insert would sort the whole map on every request once
# the cap is reached. Clearing a tenth of it amortizes that over the next
# thousand inserts.
EVICT_TO = Math.floor MAX_KEYS * 0.9

buckets = new Map()


# Make room. Expired buckets go first; if the map is still at the cap, the
# buckets closest to rolling over go next. Dropping only the expired ones was
# not a cap at all — during a spray nothing is expired, so the map grew
# without bound while every request paid for a full scan.
evict = (now) ->
  for [key, bucket] from buckets
    buckets.delete key if now >= bucket.resetAt

  return if buckets.size <= EVICT_TO

  byExpiry = [...buckets.entries()].sort (a, b) -> a[1].resetAt - b[1].resetAt
  for [key] in byExpiry[0...(buckets.size - EVICT_TO)]
    buckets.delete key

  return


# Records one hit against `key`. Returns whether it is allowed and, when it is
# not, how many seconds until the window rolls over.
hit = (key, limit, windowMs, now = Date.now()) ->
  bucket = buckets.get key

  unless bucket? and now < bucket.resetAt
    evict now if buckets.size >= MAX_KEYS
    bucket = count: 0, resetAt: now + windowMs
    buckets.set key, bucket

  bucket.count += 1

  allowed:    bucket.count <= limit
  retryAfter: Math.ceil (bucket.resetAt - now) / 1000


size = -> buckets.size

reset = -> buckets.clear()


module.exports = { hit, size, reset, MAX_KEYS }
