# Bug 50 — Deeply nested JSON body crashes the process

**Reported:** 2026-09-23 by architectural review
**Status:** resolved 2026-09-24

## Resolution

Three independent layers, because each one alone left a gap:

1. `lib/logger.coffee::tokenizeMetadata` now takes a `depth` parameter and
   stops descending at `MAX_METADATA_DEPTH` (20), returning a
   `'[redacted: max nesting depth exceeded]'` marker instead of recursing
   further. This is the actual fix — it removes the unbounded recursion that
   raised the `RangeError` in the first place.

2. `lib/middleware.coffee::asyncRoute`'s catch block now wraps the
   `logger.error` call in its own `try`/`catch`. A logging failure — from a
   pathological body, a database error inside the tokenizer, or anything
   else — is reported to `console.error` directly and the HTTP response
   still goes out. Before this, an exception raised while logging a request
   error was thrown from inside a `catch` block with nothing above it to
   catch it.

3. `main.coffee` now installs `process.on 'unhandledRejection',
   handleUnhandledRejection`, which logs (best-effort — its own `logger.error`
   call is guarded too) and lets the process keep serving, rather than the
   Node 24 default of exiting.

Layer 1 fixes the actual crash for this report. Layers 2 and 3 are the belt
and braces the bug asked for: nothing about "a route handler's error path
must not be able to end the process" should depend on every future logger
change getting the depth bound right forever.

Separately, `asyncRoute` now honours a 4xx `err.status` set by the handler,
ahead of the message-sniffed `not found` / `already deleted` fallback. This
is the contract validation errors are expected to rely on (see the parallel
ledger-bugs work): a handler that already knows its status does not need its
error message pattern-matched to guess one. Only 4xx is honoured this way —
a handler is not in a position to override the framework's own idea of what
counts as a server error.

Covered by:
- `test/services/logger.coffee` — `tokenizeMetadata` survives a ~45,000-deep
  array without a `RangeError`, and separately confirms metadata beyond the
  depth bound is replaced with the marker rather than silently dropped or
  reproduced.
- `test/services/middleware.coffee` (`asyncRoute (bug 50)`) — a handler
  error with `err.status = 400` is honoured; a message-sniffed fallback
  still works when `err.status` is absent; an out-of-range or 5xx
  `err.status` does not override the default; a broken `logger.error` still
  lets the response go out.
- `test/services/middleware.coffee` (`main.coffee survives an unhandled
  rejection (bug 50)`) — a child process that installs
  `main.handleUnhandledRejection` and triggers a bare `Promise.reject`
  proves the process keeps running afterward.

## Symptom

An authenticated `POST` with a deeply nested JSON body (e.g. to
`/rent/events`) — combined with a field that also failed validation — could
take the whole process down. Every other in-flight request failed along with
it; the ASG eventually replaced the instance.

## Reproduction

1. Authenticate.
2. `POST /rent/events` with a body containing a ~45,000-level-deep nested
   array and an invalid `amount`.
3. The handler rejects the amount and throws; `asyncRoute`'s `catch` calls
   `logger.error` with `{ body: req.body, ... }` as metadata.
4. `logger.error` → `tokenizeMetadata` recurses once per level of the posted
   array. Around depth ~10,000–15,000 (stack-size dependent) it raises
   `RangeError: Maximum call stack size exceeded` — from inside the `catch`
   block that was supposed to turn the original error into an HTTP response.
5. Nothing above that `catch` catches the `RangeError`. It becomes an
   unhandled rejection. Node 24's default `unhandledRejection` behavior is to
   exit the process.

## Root cause

`tokenizeMetadata` (`lib/logger.coffee`) recursed into every level of a
posted object/array with no depth bound, spending one stack frame per level.
`asyncRoute` (`lib/middleware.coffee`) logs `req.body` unconditionally on any
handler error, so a sufficiently deep body turned an ordinary validation
failure into a stack overflow raised from code that had no `catch` around
it. There was also no process-level `unhandledRejection` handler, so the one
exception that did make it that far took the whole server down rather than
just failing the one request.

## Risk

Metadata nested beyond 20 levels is now recorded as a marker string rather
than its real shape. Nothing in this codebase's normal request/response
bodies nests anywhere near that deep — the only way to reach it is
deliberately, or via a bug — so this is not expected to lose real
diagnostic information in practice.
