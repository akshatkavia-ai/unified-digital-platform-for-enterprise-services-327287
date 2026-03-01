# Database container (PostgreSQL)

This repository contains the **database schema** for the Unified Digital Platform.

It provides:

- Versioned migrations (plain SQL files)
- A simple seed script (idempotent inserts)
- Clear instructions for applying migrations and seeding via `psql`

## Prerequisites

- `psql` installed and available in PATH
- A Postgres instance reachable via a connection string

### Connection string

Per platform conventions, the connection string should be available in:

- `db_connection.txt` (recommended for local/dev), containing something like:
  `psql postgresql://user:pass@host:5432/dbname`
- or via environment variable `DATABASE_URL` (CI/prod)

This repository's scripts support either approach.

## Apply migrations

Migrations are stored in `migrations/` and should be applied in filename order.

### Option A: using the helper script (recommended)

```bash
./scripts/migrate.sh
```

### Option B: manually with psql

```bash
# Replace with your actual DSN / DATABASE_URL
psql "$DATABASE_URL" -f migrations/001_init.sql
```

## Seed data

Seed data is optional and safe to run multiple times.

### Using the helper script

```bash
./scripts/seed.sh
```

### Manually

```bash
psql "$DATABASE_URL" -f seeds/001_seed.sql
```

## Tables included (minimal)

This schema creates the minimal tables needed by the backend container for persistence and audit:

- `iam_users`
- `audit_log`
- `applications`
- `workflow_tasks`
- `documents_metadata`
- `tickets`
- `inspections`
- `payments`
"""
