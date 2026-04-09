#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# HyperSwitch entrypoint for Railway
#
# 1. Wait for Postgres to be reachable
# 2. Apply all diesel migrations (up.sql files) via psql, in order
# 3. Exec the router (env vars override the baked-in TOML)
# ─────────────────────────────────────────────────────────────────────────────

: "${ROUTER__MASTER_DATABASE__HOST:?ROUTER__MASTER_DATABASE__HOST is required}"
: "${ROUTER__MASTER_DATABASE__PORT:?ROUTER__MASTER_DATABASE__PORT is required}"
: "${ROUTER__MASTER_DATABASE__USERNAME:?ROUTER__MASTER_DATABASE__USERNAME is required}"
: "${ROUTER__MASTER_DATABASE__PASSWORD:?ROUTER__MASTER_DATABASE__PASSWORD is required}"
: "${ROUTER__MASTER_DATABASE__DBNAME:?ROUTER__MASTER_DATABASE__DBNAME is required}"

export PGHOST="$ROUTER__MASTER_DATABASE__HOST"
export PGPORT="$ROUTER__MASTER_DATABASE__PORT"
export PGUSER="$ROUTER__MASTER_DATABASE__USERNAME"
export PGPASSWORD="$ROUTER__MASTER_DATABASE__PASSWORD"
export PGDATABASE="$ROUTER__MASTER_DATABASE__DBNAME"

echo "⏳ Waiting for Postgres at ${PGHOST}:${PGPORT}..."
RETRIES=30
until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -le 0 ]; then
    echo "❌ Postgres not reachable after 60s, aborting."
    exit 1
  fi
  sleep 2
done
echo "✅ Postgres is up."

# ─────────────────────────────────────────────────────────────────────────────
# Run migrations
#
# The /local/migrations folder is a diesel-style layout:
#   migrations/
#     2023-01-01-000000_init/
#       up.sql
#       down.sql
#     ...
#
# We track applied migrations in a __schema_migrations table so reboots
# don't re-apply everything.
# ─────────────────────────────────────────────────────────────────────────────

MIGRATIONS_DIR="/local/migrations"

if [ ! -d "$MIGRATIONS_DIR" ]; then
  echo "⚠️  No migrations directory at $MIGRATIONS_DIR — skipping."
else
  echo "🔧 Ensuring schema_migrations table exists..."
  psql -v ON_ERROR_STOP=1 -c "
    CREATE TABLE IF NOT EXISTS __schema_migrations (
      version TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  " >/dev/null

  for migration_path in $(ls -1d "$MIGRATIONS_DIR"/*/ 2>/dev/null | sort); do
    version=$(basename "$migration_path")
    up_file="${migration_path}up.sql"

    if [ ! -f "$up_file" ]; then
      continue
    fi

    already_applied=$(psql -tAc "SELECT 1 FROM __schema_migrations WHERE version = '$version';")
    if [ "$already_applied" = "1" ]; then
      continue
    fi

    echo "  ▶ Applying $version"
    if psql -v ON_ERROR_STOP=1 -f "$up_file" >/dev/null; then
      psql -v ON_ERROR_STOP=1 -c \
        "INSERT INTO __schema_migrations (version) VALUES ('$version');" >/dev/null
    else
      echo "❌ Migration $version failed."
      exit 1
    fi
  done
  echo "✅ Migrations up to date."
fi

# ─────────────────────────────────────────────────────────────────────────────
# Start the router. The image ships with /local/config/docker_compose.toml as
# the base config; every value gets overridden by ROUTER__* env vars set in
# Railway, so the user can swap Postgres/Redis without touching code.
# ─────────────────────────────────────────────────────────────────────────────

echo "🚀 Starting HyperSwitch router on port ${ROUTER__SERVER__PORT:-8080}..."
exec /local/bin/router -f /local/config/docker_compose.toml
