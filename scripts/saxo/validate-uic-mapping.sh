#!/bin/bash
set -eo pipefail
# Validate UIC mappings in currency config files against Saxo Bank API
# Usage: validate-uic-mapping.sh
# Exit code: 0 = all OK, 1 = mismatches found

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

CONFIG_DIR="$SCRIPT_DIR/../config/currencies"

echo "=== UIC Mapping Validation ===" >&2
echo "Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >&2
echo "" >&2

MISMATCH=0
CHECKED=0
RESULTS="[]"

for config_file in "$CONFIG_DIR"/*.json; do
    [[ -f "$config_file" ]] || continue

    SYMBOL=$(jq -r '.symbol' "$config_file")
    CONFIGURED_UIC=$(jq -r '.saxo_uic' "$config_file")
    ASSET_TYPE=$(jq -r '.saxo_asset_type' "$config_file")

    # Search Saxo API for this symbol
    ENCODED=$(printf '%s' "$SYMBOL" | jq -sRr @uri)
    RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/ref/v1/instruments?KeyWords=$ENCODED&AssetTypes=$ASSET_TYPE" \
        -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
        -H "Content-Type: application/json")

    # Find exact match
    ACTUAL_UIC=$(echo "$RESPONSE" | jq -r --arg sym "$SYMBOL" '.Data[] | select(.Symbol == $sym) | .Identifier' 2>/dev/null | head -1)
    ACTUAL_DESC=$(echo "$RESPONSE" | jq -r --arg sym "$SYMBOL" '.Data[] | select(.Symbol == $sym) | .Description' 2>/dev/null | head -1)

    CHECKED=$((CHECKED + 1))
    STATUS="ok"

    if [[ -z "$ACTUAL_UIC" ]]; then
        echo "  [$SYMBOL] WARNING: Not found on Saxo API (configured UIC: $CONFIGURED_UIC)" >&2
        STATUS="not_found"
        MISMATCH=$((MISMATCH + 1))
    elif [[ "$ACTUAL_UIC" != "$CONFIGURED_UIC" ]]; then
        echo "  [$SYMBOL] MISMATCH: config=$CONFIGURED_UIC, actual=$ACTUAL_UIC ($ACTUAL_DESC)" >&2
        STATUS="mismatch"
        MISMATCH=$((MISMATCH + 1))
    else
        echo "  [$SYMBOL] OK (UIC: $CONFIGURED_UIC, $ACTUAL_DESC)" >&2
    fi

    RESULTS=$(echo "$RESULTS" | jq \
        --arg symbol "$SYMBOL" \
        --argjson configUic "$CONFIGURED_UIC" \
        --arg actualUic "${ACTUAL_UIC:-null}" \
        --arg desc "${ACTUAL_DESC:-}" \
        --arg status "$STATUS" \
        '. + [{
            symbol: $symbol,
            configuredUic: $configUic,
            actualUic: (if $actualUic == "null" then null else ($actualUic | tonumber) end),
            description: $desc,
            status: $status
        }]')
done

echo "" >&2
echo "Checked: $CHECKED, Mismatches: $MISMATCH" >&2

# Output JSON
jq -n \
    --arg status "$(if [[ $MISMATCH -gt 0 ]]; then echo "error"; else echo "ok"; fi)" \
    --argjson checked "$CHECKED" \
    --argjson mismatches "$MISMATCH" \
    --argjson results "$RESULTS" \
    '{
        status: $status,
        checked: $checked,
        mismatches: $mismatches,
        results: $results,
        timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    }'

if [[ $MISMATCH -gt 0 ]]; then
    exit 1
fi
