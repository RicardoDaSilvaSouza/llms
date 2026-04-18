#!/bin/bash
set -e

# Save original stdout and redirect setup output to stderr
exec 3>&1
exec 1>&2

# If POSTGRES_HOST is external (not localhost), skip internal postgres entirely
if [ "${POSTGRES_HOST}" != "localhost" ] && [ "${POSTGRES_HOST}" != "127.0.0.1" ]; then
    echo "External PostgreSQL detected at ${POSTGRES_HOST}:${POSTGRES_PORT:-5432}, skipping internal DB init..."

    # Wait for external postgres to be ready
    until pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT:-5432}" -U "${POSTGRES_USER:-postgres}"; do
        echo "Waiting for external PostgreSQL at ${POSTGRES_HOST}..."
        sleep 2
    done

    # Run setup SQL against the external DB (creates functions + extensions)
    if [ -f sql/setup_database.sql ]; then
        echo "Running setup SQL on external database..."
        PGPASSWORD="${POSTGRES_PASSWORD}" psql \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT:-5432}" \
            -U "${POSTGRES_USER:-postgres}" \
            -d "${POSTGRES_DB:-postgres}" \
            -f sql/setup_database.sql || true  # idempotent, ok if already exists
    fi

else
    # Original internal postgres flow
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
        echo "Initializing internal PostgreSQL database..."
        su postgres -c "/usr/lib/postgresql/15/bin/initdb -D $PGDATA"
        su postgres -c "/usr/lib/postgresql/15/bin/pg_ctl -D $PGDATA -o '-c listen_addresses=localhost' -w start"
        su postgres -c "/usr/lib/postgresql/15/bin/psql -c \"CREATE EXTENSION IF NOT EXISTS vector;\""
        if [ -f sql/setup_database.sql ]; then
            su postgres -c "/usr/lib/postgresql/15/bin/psql -f sql/setup_database.sql"
        fi
        su postgres -c "/usr/lib/postgresql/15/bin/pg_ctl -D $PGDATA -m fast -w stop"
    fi

    su postgres -c "/usr/lib/postgresql/15/bin/pg_ctl -D $PGDATA -o '-c listen_addresses=localhost' -w start"

    until su postgres -c "/usr/lib/postgresql/15/bin/pg_isready -h localhost -p 5432"; do
        echo "Waiting for internal PostgreSQL..."
        sleep 1
    done
fi

echo "PostgreSQL is ready. Starting MCP server..."

# Restore stdout for MCP stdio protocol
exec 1>&3

exec python3 src/postgres_memory_server.py
