#!/bin/bash
# Search instruments on Saxo Bank API
# Usage: search-instruments.sh <keywords> [asset_type]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

KEYWORDS="$1"
ASSET_TYPE="${2:-FxSpot}"

if [[ -z "$KEYWORDS" ]]; then
    echo "Usage: $0 <keywords> [asset_type]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  keywords   - Search term (e.g., 'USD', 'EURUSD', 'Gold')" >&2
    echo "  asset_type - Asset type (default: FxSpot)" >&2
    echo "" >&2
    echo "Common asset types:" >&2
    echo "  FxSpot, FxForwards, FxSwap, FxOptions" >&2
    echo "  Stock, StockOption, StockIndex, StockIndexOption" >&2
    echo "  CfdOnIndex, CfdOnStock, CfdOnFutures" >&2
    echo "  FuturesOption, Bond, MutualFund, ETF" >&2
    exit 1
fi

echo "Searching for '$KEYWORDS' (AssetType: $ASSET_TYPE)..." >&2
echo "" >&2

ENCODED_KEYWORDS=$(printf '%s' "$KEYWORDS" | jq -sRr @uri)
RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/ref/v1/instruments?KeyWords=$ENCODED_KEYWORDS&AssetTypes=$ASSET_TYPE" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error:" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

# Display results
COUNT=$(echo "$RESPONSE" | jq '.Data | length')
echo "Found $COUNT instruments:" >&2
echo "" >&2

echo "$RESPONSE" | jq -r '.Data[] | "UIC: \(.Identifier)\t| \(.Symbol)\t| \(.Description)"' >&2

# Output JSON for script consumption
echo ""
echo "$RESPONSE" | jq '.Data | map({uic: .Identifier, symbol: .Symbol, description: .Description, assetType: .AssetType})'
