#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Prefer db_connection.txt (platform convention); fall back to DATABASE_URL.
PSQL_CMD=""
if [[ -f "${ROOT_DIR}/db_connection.txt" ]]; then
  # db_connection.txt typically contains: psql postgresql://...
  PSQL_CMD="$(cat "${ROOT_DIR}/db_connection.txt" | tr -d '\n')"
elif [[ -n "${DATABASE_URL:-}" ]]; then
  PSQL_CMD="psql ${DATABASE_URL}"
else
  echo "Missing connection info. Provide db_connection.txt or set DATABASE_URL." >&2
  exit 1
fi

echo "Using PSQL command: ${PSQL_CMD}"

for f in "${ROOT_DIR}"/migrations/*.sql; do
  echo "Applying migration: $(basename "$f")"
  # shellcheck disable=SC2086
  ${PSQL_CMD} -v ON_ERROR_STOP=1 -f "$f"
done

echo "Migrations applied successfully."
