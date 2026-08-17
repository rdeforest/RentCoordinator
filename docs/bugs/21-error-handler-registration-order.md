# Bug 21 — Global error handler registered before routes; never catches route errors

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

An error that propagates out of a route (an uncaught throw, or a
`next(err)`) never reaches the structured error handler. Instead of the
intended JSON `{ error: 'Internal server error' }` and a
`logger.error 'middleware.errorHandler'` log line, the client gets
Express's default HTML error page and nothing is logged through the
structured logger.

## Reproduction

1. Add a route that throws outside any try/catch (or calls `next(err)`).
2. Hit it.

Expected: 500 JSON `{ error: 'Internal server error' }` and a
`middleware.errorHandler` log entry.
Actual: Express's default HTML stack-trace page; no structured log.

## Root cause

Express only routes an error to a 4-argument error-handling middleware if
that middleware was registered *after* the route that failed. The error
handler here is registered too early.

`main.coffee:21-22` calls `middleware.setup app` before `routing.setup app`.
The error handler lives inside `middleware.setup`
(`lib/middleware.coffee:45-52`):

```coffee
app.use (err, req, res, next) ->
  logger.error 'middleware.errorHandler', err, …
  res.status(500).json error: 'Internal server error', …
```

Because it's registered before any route exists in the middleware stack,
errors thrown by routes flow past it to Express's built-in handler. It's
dead code for its stated purpose.

Today this is masked because every route is wrapped in `asyncRoute`
(middleware.coffee:70-86), which try/catches and sends its own JSON. But any
path that throws or calls `next(err)` outside that wrapper — a route added
without `asyncRoute`, a synchronous middleware error, a `next(err)` — is
unhandled.

## Proposed fix

(No docs/fixes/ file exists yet.)

Register the error handler *after* all routes. Pull it out of
`middleware.setup` into its own export — e.g. `middleware.setupErrorHandler
app` — and call it at the very end of `startServer`, after
`routing.setup app`. Order in `main.coffee` becomes: `middleware.setup` →
`routing.setup` → `middleware.setupErrorHandler`. That puts the 4-arg
handler last in the stack, where Express will actually select it.

## Risk

Low and mechanical. The one thing to confirm is that nothing else in
`middleware.setup` depends on the error handler being registered at that
point (it doesn't — it's the last thing set up). After the move, verify by
adding a throwing route and confirming the JSON response and the
`middleware.errorHandler` log line both appear. Read `main.coffee` and
`lib/middleware.coffee` to confirm the ordering before moving it.
