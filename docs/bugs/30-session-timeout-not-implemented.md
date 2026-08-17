# Bug 30 — Documented 8-hour auto-timeout is not implemented

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

A timer left running (e.g. the browser was closed without stopping)
accumulates elapsed time indefinitely. CLAUDE.md claims "Automatic
session timeout after 8 hours," but there is no cap.

## Reproduction

1. Start a timer.
2. Never stop it; leave the session `active`.
3. Query `/timer/status` days later — `elapsed` keeps growing with wall
   time, unbounded.

## Root cause

`config.SESSION_TIMEOUT = 8 * 60 * 60 * 1000` (`lib/config.coffee:8`) is
defined and exported but referenced nowhere else (grep confirms only the
definition and the export). `calculateSessionDuration`
(`lib/models/work_session.coffee:95-97`) accrues
`(new Date() - lastStartTime)` open-endedly for any still-active session,
so nothing bounds the elapsed time.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Pick one:

- Implement the cap: in `calculateSessionDuration` (or when a session is
  read for status/stop), clamp an open segment to `SESSION_TIMEOUT` and
  auto-stop sessions that exceed it.
- Or remove the constant and the CLAUDE.md claim so the doc stops
  describing behavior that doesn't exist.

Decide which behavior is actually wanted before writing code — the two
answers are opposite.

## Risk

Low either way. Implementing the cap changes recorded durations for
abandoned sessions (arguably a correction). Removing the constant is
inert.
