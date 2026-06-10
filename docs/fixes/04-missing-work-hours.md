# Fix 4 — Lyndzie's work hours not appearing in rent periods

## What's reported

Lyndzie entered 48.75 hours but they aren't showing up in the rent
periods list. (From CLAUDE.md "Known Issues" section, 2026-01-01.)

## How to diagnose first

Before patching anything, run these queries against the live DB to find
out which suspect is real. Each command runs against the production SQLite.

### 1. Worker name spelling / case

```bash
sqlite3 tenant-coordinator.db <<'SQL'
SELECT worker, COUNT(*) AS log_count, SUM(duration) AS total_minutes
FROM work_logs
GROUP BY worker;
SQL
```

If you see anything other than exactly `lyndzie` (lower-case) — say
`Lyndzie`, `lynz57`, `Lyn`, or a stray space — that's your bug. The
service does:

```coffee
allLogs = await workLogModel.getWorkLogs worker: 'lyndzie'
```

and the model does:

```coffee
if filters.worker
  query += " AND worker = ?"
  params.push filters.worker
```

So it's a case-sensitive exact match. No data, no calculation.

### 2. Timezone shifting at month boundaries

```bash
sqlite3 tenant-coordinator.db <<'SQL'
SELECT id, worker, start_time, end_time, duration
FROM work_logs
WHERE worker LIKE '%yndzi%'
ORDER BY start_time
LIMIT 50;
SQL
```

Check whether `start_time` is stored as UTC (ending in `Z` or with
`+00:00`) or as a local-naive string. The `calculateRent` filter is:

```coffee
startDate = new Date year, month - 1, 1        # local midnight on the 1st
endDate   = new Date year, month, 0, 23, 59, 59
monthLogs = allLogs.filter (log) ->
  logDate = new Date log.start_time
  logDate >= startDate and logDate <= endDate
```

If logs were entered on the last evening of a month in Pacific time and
stored as UTC ISO strings, they cross into the next month when re-parsed
as `Date`. The threshold of pain is "logs entered close to midnight on
the 31st".

### 3. Total hours sanity check

```bash
sqlite3 tenant-coordinator.db <<'SQL'
SELECT
  strftime('%Y-%m', start_time) AS month,
  SUM(duration) / 60.0 AS hours
FROM work_logs
WHERE LOWER(worker) = 'lyndzie'
GROUP BY month
ORDER BY month;
SQL
```

This shows the truth about hours-by-month, ignoring case. If this total
adds up to 48.75 but a specific month is shifted, that confirms a
timezone issue. If the total doesn't even reach 48.75, the data is
missing (or stored with a worker name we're not matching).

## The fix

Regardless of which suspect wins, these changes harden the code:

### 1. Case-insensitive worker filter

In `lib/models/work_log.coffee`, replace:

```coffee
if filters.worker
  query += " AND worker = ?"
  params.push filters.worker
```

with:

```coffee
if filters.worker
  query += " AND LOWER(worker) = LOWER(?)"
  params.push filters.worker
```

This costs a small amount on the query (SQLite doesn't use the
`idx_work_logs_worker` index efficiently with `LOWER()`). For a 2-user
app with a few thousand work logs at most, this doesn't matter. If it
ever does, the right fix is a check constraint that normalizes worker
names on insert.

### 2. Push the date filter into SQL

Same file. Add date-range filter support:

```coffee
getWorkLogs = (filters = {}) ->
  query  = "SELECT * FROM work_logs WHERE 1=1"
  params = []

  if filters.worker
    query += " AND LOWER(worker) = LOWER(?)"
    params.push filters.worker

  if filters.project_id
    query += " AND project_id = ?"
    params.push filters.project_id

  if filters.start_after
    query += " AND start_time >= ?"
    params.push filters.start_after

  if filters.start_before
    query += " AND start_time < ?"
    params.push filters.start_before

  query += " ORDER BY start_time DESC"

  if filters.limit
    query += " LIMIT ?"
    params.push parseInt filters.limit

  return db.prepare(query).all params...
```

### 3. Use the date filter in the rent service

In `lib/services/rent.coffee`, change `calculateRent`:

```coffee
calculateRent = (year, month) ->
  # Build ISO strings that match how work_logs stores start_time.
  # Both endpoints are in the local timezone of the server, which is
  # what the user means when they say "December hours".
  startISO = new Date(year, month - 1, 1).toISOString()
  endISO   = new Date(year, month, 1).toISOString()  # exclusive

  monthLogs = await workLogModel.getWorkLogs
    worker:       'lyndzie'
    start_after:  startISO
    start_before: endISO

  hoursWorked = monthLogs.reduce ((total, log) ->
    total + (log.duration / 60)
  ), 0

  # ...rest unchanged
```

Note: the boundary is "exclusive on the upper end" rather than
"<=23:59:59" — cleaner and avoids the edge case where a log starts at
exactly 23:59:59.999.

Same change applies to `recalculateAllRent` — it currently fetches all
logs and groups them in JS. After the database has a proper date filter,
that can be done with a single GROUP BY query, but that's a bigger
refactor. For now, the in-JS grouping is fine; just make sure it uses
the case-insensitive worker comparison via the same filter.

## How to verify

1. Run the diagnosis queries above; record what they say.
2. Apply the model and service changes.
3. Restart, hit "Recalculate All", then check the rent periods. The
   hours should match what the diagnosis SQL showed.
4. Add `test/services/rent.coffee` test cases for:
   - Mixed-case worker name input
   - Log straddling midnight on the last day of a month
   - Log at 00:00:00 on the 1st of a month

## Risk

**Low.** The model change is a one-line edit with a case-insensitive
default. The service change uses a tighter date filter that's strictly
more correct than the existing version.

If your existing data has logs stored as bare local-time strings (no
timezone), the date filter still works because SQLite is doing
lexicographic comparison on ISO 8601 strings, which works either way as
long as the comparison values are in the same format as the stored
values. The `toISOString()` call produces UTC-suffixed strings, so if
your logs are stored as local-naive strings, you'll get a mismatch.
**Verify this on a copy of production first.**
