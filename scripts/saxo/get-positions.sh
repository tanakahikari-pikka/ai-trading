#!/bin/bash
# Get current positions from Saxo Bank API
# Usage: get-positions.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

# Get client key first
CLIENT_RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/clients/me" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$CLIENT_RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching client info:" >&2
    echo "$CLIENT_RESPONSE" | jq . >&2
    exit 1
fi

CLIENT_KEY=$(echo "$CLIENT_RESPONSE" | jq -r '.ClientKey')
ENCODED_CLIENT_KEY=$(printf '%s' "$CLIENT_KEY" | jq -sRr @uri)

# Get positions
RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/positions?ClientKey=$ENCODED_CLIENT_KEY&FieldGroups=DisplayAndFormat,PositionBase,PositionView" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching positions:" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

# Check if there are any positions
POSITION_COUNT=$(echo "$RESPONSE" | jq '.Data | length')

echo "=== Positions ($POSITION_COUNT) ===" >&2

if [[ "$POSITION_COUNT" -eq 0 ]]; then
    echo "No open positions." >&2
    echo "[]"
    exit 0
fi

# Display summary
echo "$RESPONSE" | jq -r '.Data[] | "[\(.DisplayAndFormat.Symbol)] \(.PositionBase.Amount) @ \(.PositionBase.OpenPrice) | Current: \(.PositionView.CurrentPrice) | P/L: \(.PositionView.ProfitLossOnTrade) \(.DisplayAndFormat.Currency)"' >&2

# Output formatted JSON
echo ""
echo "$RESPONSE" | jq '.Data | map({
    positionId: .PositionId,
    symbol: .DisplayAndFormat.Symbol,
    description: .DisplayAndFormat.Description,
    currency: .DisplayAndFormat.Currency,
    amount: .PositionBase.Amount,
    openPrice: .PositionBase.OpenPrice,
    currentPrice: .PositionView.CurrentPrice,
    profitLoss: .PositionView.ProfitLossOnTrade,
    profitLossBaseCurrency: .PositionView.ProfitLossOnTradeInBaseCurrency,
    uic: .PositionBase.Uic,
    assetType: .PositionBase.AssetType,
    status: .PositionBase.Status
})'
