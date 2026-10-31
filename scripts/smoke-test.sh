#!/usr/bin/env bash
# Checks the remote Supabase security rules as an anonymous visitor would.
#
# Usage:
#   scripts/smoke-test.sh              # anonymous access checks only
#   scripts/smoke-test.sh <pet-uuid>   # also runs the scan flow on a real pet
#                                      # (the test scan is deleted afterwards,
#                                      # requires `npx supabase login` + link)
#
# Reads the Supabase URL and publishable key from apps/web/.env.local.

set -uo pipefail

cd "$(dirname "$0")/.."

ENV_FILE=apps/web/.env.local
PET_ID=${1:-}
UNKNOWN_ID=00000000-0000-0000-0000-000000000000
# Null Island: coordinates no real scan will ever have, used to find the test row
TEST_LAT=0
TEST_LNG=0

read_env() {
    grep "^$1=" "$ENV_FILE" | cut -d= -f2- | tr -d "\"' "
}

URL=$(read_env NEXT_PUBLIC_SUPABASE_URL)
KEY=$(read_env NEXT_PUBLIC_SUPABASE_ANON_KEY)

if [[ -z "$URL" || -z "$KEY" ]]; then
    echo "Missing Supabase URL or key in $ENV_FILE" >&2
    exit 2
fi

failures=0

check() {
    local name=$1 expected=$2 actual=$3
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  PASS  $name"
    else
        echo "  FAIL  $name (expected '$expected', got '$actual')"
        failures=$((failures + 1))
    fi
}

# Calls the REST API with the given key; prints "<http code> <body>"
api() {
    local key=$1 method=$2 path=$3 body=${4:-}
    curl -s -X "$method" "$URL/rest/v1/$path" \
        -H "apikey: $key" -H "Content-Type: application/json" \
        ${body:+-d "$body"} -w ' %{http_code}'
}

echo "Anonymous access"
check "pets are not listable" "[] 200" "$(api "$KEY" GET 'pets?select=id')"
check "scans are not listable" "[] 200" "$(api "$KEY" GET 'scans?select=id')"
check "profiles are not listable" "[] 200" "$(api "$KEY" GET 'profiles?select=id')"
check "direct scan insert is refused" "401" \
    "$(api "$KEY" POST scans "{\"pet_id\":\"$UNKNOWN_ID\",\"latitude\":1,\"longitude\":1}")"
# Without EXECUTE, PostgREST does not even expose the function
check "handle_new_user is not callable" "PGRST202" \
    "$(api "$KEY" POST rpc/handle_new_user '{}')"

echo "Public RPCs"
check "get_pet_public on unknown pet returns nothing" "[] 200" \
    "$(api "$KEY" POST rpc/get_pet_public "{\"p_pet_id\":\"$UNKNOWN_ID\"}")"
check "get_pet_public on invalid id fails" "22P02" \
    "$(api "$KEY" POST rpc/get_pet_public '{"p_pet_id":"not-a-uuid"}')"
check "record_scan on unknown pet fails" "pet not found" \
    "$(api "$KEY" POST rpc/record_scan "{\"p_pet_id\":\"$UNKNOWN_ID\",\"p_latitude\":1,\"p_longitude\":1}")"

echo "Legacy key"
# The old anon key is still in the git history; it must be rejected.
LEGACY_KEY=$(git log -p -- apps/mobile/lib/main.dart | grep -m1 -oE "eyJ[A-Za-z0-9._-]+")
if [[ -n "$LEGACY_KEY" ]]; then
    check "legacy anon key is rejected" "401" "$(api "$LEGACY_KEY" GET 'pets?select=id')"
else
    echo "  SKIP  legacy key not found in git history"
fi

if [[ -n "$PET_ID" ]]; then
    echo "Scan flow on pet $PET_ID"
    check "get_pet_public returns the pet" "\"is_lost\"" \
        "$(api "$KEY" POST rpc/get_pet_public "{\"p_pet_id\":\"$PET_ID\"}")"
    check "record_scan rejects out-of-range coordinates" "23514" \
        "$(api "$KEY" POST rpc/record_scan "{\"p_pet_id\":\"$PET_ID\",\"p_latitude\":200,\"p_longitude\":1}")"
    check "record_scan accepts a valid scan" "204" \
        "$(api "$KEY" POST rpc/record_scan "{\"p_pet_id\":\"$PET_ID\",\"p_latitude\":$TEST_LAT,\"p_longitude\":$TEST_LNG}")"

    deleted=$(npx supabase db query --linked \
        "delete from scans where pet_id = '$PET_ID' and latitude = $TEST_LAT and longitude = $TEST_LNG and scanned_at > now() - interval '5 minutes' returning id" \
        2>/dev/null | grep -c '"id"')
    check "test scan cleaned up" "1" "$deleted"
fi

echo
if ((failures > 0)); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All checks passed"
