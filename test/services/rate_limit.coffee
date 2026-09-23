# lib/rate_limit.coffee — the one new module with arithmetic in it.
#
# `hit` takes an injectable `now` precisely so the window edges can be tested
# without waiting for them.

{ describe, it, beforeEach } = require 'node:test'
assert                       = require 'node:assert/strict'
rateLimit                    = require '../../lib/rate_limit.coffee'

{ hit, size, reset, MAX_KEYS } = rateLimit

T = 1_000_000


describe 'Fixed-window counter', ->
  beforeEach -> reset()

  it 'allows exactly `limit` hits in a window', ->
    results = (hit('k', 3, 5000, T).allowed for _ in [1..4])
    assert.deepEqual results, [true, true, true, false],
      'the hit that equals the limit is allowed; the next one is not'

  it 'rolls over exactly at resetAt, not a tick early', ->
    hit 'k', 1, 5000, T
    assert.equal hit('k', 1, 5000, T + 4999).allowed, false,
      'still inside the window one millisecond before it ends'
    assert.equal hit('k', 1, 5000, T + 5000).allowed, true,
      'the window is half-open: resetAt starts a new one'

  it 'reports how long until the window rolls over', ->
    hit 'k', 1, 5000, T
    assert.equal hit('k', 1, 5000, T).retryAfter, 5
    assert.equal hit('k', 1, 5000, T + 4001).retryAfter, 1,
      'rounded up, so a caller obeying it is never early'

  it 'keeps keys independent', ->
    hit 'a', 1, 5000, T
    assert.equal hit('a', 1, 5000, T).allowed, false
    assert.equal hit('b', 1, 5000, T).allowed, true

  it 'a limit of zero rejects immediately', ->
    assert.equal hit('k', 0, 5000, T).allowed, false


describe 'Key eviction', ->
  beforeEach -> reset()

  it 'an expired bucket does not carry its count into the next window', ->
    hit 'k', 1, 1000, T
    assert.equal hit('k', 1, 1000, T).allowed,        false
    assert.equal hit('k', 1, 1000, T + 2000).allowed, true,
      'the stale bucket is replaced rather than incremented'

  it 'holds the cap under a spray where nothing has expired yet', ->
    # The failure this replaces: eviction only removed *expired* buckets, so a
    # spray of live keys grew the map without bound while every request paid
    # for a full scan.
    hit "spray#{n}", 1, 600_000, T for n in [1..(MAX_KEYS + 500)]

    assert.ok size() <= MAX_KEYS,
      "the map must stay at or under #{MAX_KEYS}, got #{size()}"

  it 'evicts the buckets closest to expiring, not the newest ones', ->
    hit 'expires-soonest', 5, 1000,   T
    hit 'expires-latest',  5, 900_000, T
    hit "filler#{n}", 5, 500_000, T for n in [1..MAX_KEYS]

    assert.equal hit('expires-latest', 5, 900_000, T).allowed, true,
      'a long-lived bucket survives the spray'
