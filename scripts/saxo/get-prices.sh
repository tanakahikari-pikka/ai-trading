#!/bin/bash
# Get prices for instruments on Saxo Bank API
# Usage: get-prices.sh <account_key> <uics> [asset_type]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

ACCOUNT_KEY="$1"
UICS="$2"
ASSET_TYPE="${3:-FxSpot}"

if [[ -z "$ACCOUNT_KEY" || -z "$UICS" ]]; then
    echo "Usage: $0 <account_key> <uics> [asset_type]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  account_key - AccountKey from get-accounts.sh" >&2
    echo "  uics        - Comma-separated list of UICs (e.g., '16,21,31')" >&2
    echo "  asset_type  - Asset type (default: FxSpot)" >&2
    exit 1
fi

echo "Fetching prices for UICs: $UICS (AssetType: $ASSET_TYPE)..." >&2
echo "" >&2

# URL encode the account key
ENCODED_ACCOUNT_KEY=$(printf '%s' "$ACCOUNT_KEY" | jq -sRr @uri)

RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/trade/v1/infoprices/list?AccountKey=$ENCODED_ACCOUNT_KEY&Uics=$UICS&AssetType=$ASSET_TYPE&FieldGroups=DisplayAndFormat,Quote" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

# Check for top-level error (not nested ErrorCode in Quote)
if echo "$RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error:" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

# Display results
echo "=== Prices ===" >&2
echo "$RESPONSE" | jq -r '.Data[] | "[\(.DisplayAndFormat.Symbol)] Bid: \(.Quote.Bid // "N/A") | Ask: \(.Quote.Ask // "N/A") | Mid: \(.Quote.Mid // "N/A")"' >&2

# Output JSON for script consumption
echo ""
echo "$RESPONSE" | jq '.Data | map({
    uic: .Uic,
    symbol: .DisplayAndFormat.Symbol,
    description: .DisplayAndFormat.Description,
    bid: .Quote.Bid,
    ask: .Quote.Ask,
    mid: .Quote.Mid,
    priceTypeAsk: .Quote.PriceTypeAsk,
    priceTypeBid: .Quote.PriceTypeBid
})'
