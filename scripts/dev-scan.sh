#!/usr/bin/env bash
# Starts the web app locally and opens the scan page of a real pet, so the
# finder flow can be tested by hand in a browser (GPS button included).
#
# Usage:
#   scripts/dev-scan.sh              # uses the first pet found in the database
#   scripts/dev-scan.sh <pet-uuid>   # uses this pet
#
# Requires `npx supabase login` and a linked project to look up the pet and
# to clean up the scans created during the session.

set -uo pipefail

cd "$(dirname "$0")/.."

PORT=${PORT:-3000}
PET_ID=${1:-}
STARTED_AT=$(date -u +"%Y-%m-%d %H:%M:%S")

if [[ -z "$PET_ID" ]]; then
    echo "Looking up a pet in the database..."
    PET_ID=$(npx supabase db query --linked "select id from pets order by created_at limit 1" 2>/dev/null \
        | grep -m1 -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    if [[ -z "$PET_ID" ]]; then
        echo "No pet found. Pass a pet id: scripts/dev-scan.sh <pet-uuid>" >&2
        exit 1
    fi
fi

SCAN_URL="http://localhost:$PORT/scan/$PET_ID"

cleanup() {
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    echo
    read -r -p "Delete the scans created during this session? [y/N] " answer
    if [[ "$answer" =~ ^[yYoO]$ ]]; then
        deleted=$(npx supabase db query --linked \
            "delete from scans where pet_id = '$PET_ID' and scanned_at >= '$STARTED_AT' returning id" \
            2>/dev/null | grep -c '"id"')
        echo "$deleted scan(s) deleted."
    else
        echo "Scans kept."
    fi
    exit 0
}

(cd apps/web && npx next dev -p "$PORT") &
SERVER_PID=$!
trap cleanup INT TERM

echo "Waiting for the dev server..."
until curl -s -o /dev/null "http://localhost:$PORT"; do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "The dev server stopped." >&2
        exit 1
    fi
    sleep 1
done

cat <<EOF

  Scan page: $SCAN_URL
  Unknown pet (404 screen): http://localhost:$PORT/scan/00000000-0000-0000-0000-000000000000

  To test:
    1. The pet name is shown.
    2. Click the button and allow location: the success message appears.
    3. Refuse location (reset the permission in the address bar): the error appears.
    4. Open the unknown pet link: the "not registered" message appears.

  Press Ctrl+C to stop.

EOF

xdg-open "$SCAN_URL" >/dev/null 2>&1 || true
wait "$SERVER_PID"
