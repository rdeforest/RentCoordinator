# Bug 13 — Verification codes use Math.random() (non-CSPRNG)

**Reported:** 2026-08-15 by codebase audit
**Status:** active (security)

## Symptom

Login verification codes are generated with a non-cryptographic RNG.
Their values are not truly unpredictable: an observer who sees enough
generated codes can recover the generator's internal state and predict
future codes.

## Reproduction

Not directly reproducible by clicking — it's a property of the generator,
not a runtime error. The weakness is exploited by observing a sequence of
issued codes and recovering V8's `Math.random` state, then predicting the
next code.

## Root cause

```
generateCode = ->
  Math.floor(100000 + Math.random() * 900000).toString()   # email.coffee:5
```

`Math.random()` is not a cryptographically secure PRNG. V8 implements it
with an xorshift-family generator whose internal state can be recovered
from a modest run of observed outputs, after which all subsequent outputs
are predictable. For a value that gates authentication, that's the wrong
primitive.

Combined with bug 12 (no lockout / no rate limit), predictability makes
the login even weaker: an attacker who can anticipate the code doesn't
even need to brute-force it.

## Proposed fix

Use the crypto RNG:

```coffee
{ randomInt } = require 'node:crypto'
generateCode = -> randomInt(100000, 1000000).toString()
```

`randomInt` draws from the CSPRNG and gives a uniform value in
`[100000, 1000000)`, i.e. exactly the six-digit range.

## Risk

Low. It's a one-line swap with no schema or interface change; the output
shape (a 6-digit string) is unchanged, so nothing downstream needs to
adapt. `crypto.randomInt` is synchronous in this form and fast enough for
login volume.
