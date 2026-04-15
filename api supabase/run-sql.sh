#!/usr/bin/env bash
# Auto-apply SQL extension files ke Supabase tanpa paste manual.
# Usage:
#   ./run-sql.sh schema_extend_5_8.sql
#   ./run-sql.sh schema.sql rls.sql rpc.sql   (multiple)
set -euo pipefail

cd "$(dirname "$0")"

# Load token
if [ -f .env ]; then
  set -a; source .env; set +a
fi

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  echo "❌ SUPABASE_ACCESS_TOKEN tak set. Letak dalam api supabase/.env" >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "Usage: $0 <sql-file> [more-sql-files...]" >&2
  exit 1
fi

# Get DB connection string via supabase API (1-time fetch)
PROJECT_REF="${SUPABASE_PROJECT_REF:-lpurtgmqecabgwwenikb}"

for sql in "$@"; do
  if [ ! -f "$sql" ]; then
    echo "❌ File tak jumpa: $sql" >&2
    exit 1
  fi
  echo "▶  Run: $sql"
  # Use management API to execute SQL
  RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$(jq -Rs '{query: .}' < "$sql")")

  HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
  BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')

  if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
    echo "✅ $sql berjaya"
  else
    echo "❌ $sql gagal (HTTP $HTTP_STATUS):"
    echo "$BODY"
    exit 1
  fi
done

echo "✅ Semua SQL files berjaya dijalankan"
