#!/bin/bash
# Get current orders from Saxo Bank API
# Usage: get-orders.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

# Get orders
RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/orders/me?FieldGroups=DisplayAndFormat,ExchangeInfo" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching orders:" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

# Check if there are any orders
ORDER_COUNT=$(echo "$RESPONSE" | jq '.Data | length')

echo "=== Open Orders ($ORDER_COUNT) ===" >&2

if [[ "$ORDER_COUNT" -eq 0 ]]; then
    echo "No open orders." >&2
    echo "[]"
    exit 0
fi

# Display summary
echo "$RESPONSE" | jq -r '.Data[] | "[\(.DisplayAndFormat.Symbol)] \(.OrderType) \(.BuySell) \(.Amount) @ \(.Price)"' >&2

# Output formatted JSON
echo ""
echo "$RESPONSE" | jq '.Data | map({
    orderId: .OrderId,
    symbol: .DisplayAndFormat.Symbol,
    orderType: .OrderType,
    buySell: .BuySell,
    amount: .Amount,
    price: .Price,
    status: .Status,
    duration: .Duration.DurationType
})'
