#!/bin/bash
set -euo pipefail

# Runs database migrations and seed data for the defect management system.
# Uses db_connection.txt as the authoritative connection string.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONN_STR="$(cat "${ROOT_DIR}/db_connection.txt" | tr -d '\n')"

echo "Using connection: ${CONN_STR}"
echo "Applying migrations..."

psql "${CONN_STR}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/migrations/001_init_extensions.sql"
psql "${CONN_STR}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/migrations/002_core_schema.sql"
psql "${CONN_STR}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/migrations/003_indexes_and_views.sql"
psql "${CONN_STR}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/seeds/001_seed_masters.sql"
psql "${CONN_STR}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/seeds/002_seed_demo_data.sql"

echo "✓ Migrations and seeds applied successfully"
