# Defect Management Database (PostgreSQL)

This container provides the PostgreSQL schema, migrations, and seed data for the Manufacturing Defect Management System.

## Connection

This repo uses `db_connection.txt` as the authoritative connection string.

Example:

```bash
cat db_connection.txt
# psql postgresql://appuser:dbuser123@localhost:5000/myapp
```

## Run database

Start Postgres (if not already running):

```bash
./startup.sh
```

## Apply schema + seed data

Run:

```bash
./migrate.sh
```

This will apply:

- `migrations/001_init_extensions.sql`
- `migrations/002_core_schema.sql`
- `migrations/003_indexes_and_views.sql`
- `seeds/001_seed_masters.sql`
- `seeds/002_seed_demo_data.sql`

## Notes

- Audit/history tables are immutable (UPDATE/DELETE blocked by triggers).
- Dashboard support:
  - `vw_pareto_defect_types`
  - `vw_trends_daily`
  - `vw_actions_due`
