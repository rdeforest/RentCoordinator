# Fix 2 (schema half) — update `lib/db/schema.coffee`

So that fresh installs match what the migration produces, update the
`SCHEMA` string in `lib/db/schema.coffee` for two tables.

## Change 1: `rent_events`

Find:
```sql
CREATE TABLE IF NOT EXISTS rent_events (
  id TEXT PRIMARY KEY,
  period_id TEXT NOT NULL REFERENCES rent_periods(id),
  type TEXT NOT NULL,
  amount REAL NOT NULL,
  description TEXT,
  metadata TEXT, -- JSON
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

Replace with:
```sql
CREATE TABLE IF NOT EXISTS rent_events (
  id TEXT PRIMARY KEY,
  period_id TEXT NOT NULL REFERENCES rent_periods(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  amount REAL NOT NULL,
  description TEXT,
  metadata TEXT, -- JSON
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## Change 2: `recurring_event_logs`

Find:
```sql
CREATE TABLE IF NOT EXISTS recurring_event_logs (
  id TEXT PRIMARY KEY,
  recurring_event_id TEXT NOT NULL REFERENCES recurring_events(id),
  period_id TEXT NOT NULL REFERENCES rent_periods(id),
  amount REAL NOT NULL,
  processed_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

Replace with:
```sql
CREATE TABLE IF NOT EXISTS recurring_event_logs (
  id TEXT PRIMARY KEY,
  recurring_event_id TEXT NOT NULL REFERENCES recurring_events(id) ON DELETE CASCADE,
  period_id TEXT NOT NULL REFERENCES rent_periods(id) ON DELETE CASCADE,
  amount REAL NOT NULL,
  processed_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## A note on `IF NOT EXISTS`

Both statements use `CREATE TABLE IF NOT EXISTS`, which means existing
databases keep their pre-migration schema even after you update this file.
The migration above is what brings existing databases into line.
