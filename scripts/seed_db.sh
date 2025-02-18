#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GS_DB_HOST:-}" || -z "${GS_DB_PORT:-}" || -z "${GS_DB_NAME:-}" || -z "${GS_DB_USER:-}" || -z "${GS_DB_PASSWORD:-}" ]]; then
  echo "Missing required GS_DB_* environment variables." >&2
  exit 1
fi

SSL_MODE=${GS_DB_SSLMODE:-require}

PGPASSWORD="$GS_DB_PASSWORD" psql \
  "postgresql://$GS_DB_USER@$GS_DB_HOST:$GS_DB_PORT/$GS_DB_NAME?sslmode=$SSL_MODE" \
  -v ON_ERROR_STOP=1 \
  -f "$(dirname "$0")/../db/seed.sql"
