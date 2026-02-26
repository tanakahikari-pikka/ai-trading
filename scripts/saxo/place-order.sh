#!/bin/bash
# Place an order on Saxo Bank API
# Usage: place-order.sh <account_key> <uic> <buy_sell> <amount> <order_type> [order_price] [asset_type]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

ACCOUNT_KEY="$1"
UIC="$2"
BUY_SELL="$3"
AMOUNT="$4"
ORDER_TYPE="$5"
ORDER_PRICE="$6"
ASSET_TYPE="${7:-FxSpot}"

if [[ -z "$ACCOUNT_KEY" || -z "$UIC" || -z "$BUY_SELL" || -z "$AMOUNT" || -z "$ORDER_TYPE" ]]; then
    echo "Usage: $0 <account_key> <uic> <buy_sell> <amount> <order_type> [order_price] [asset_type]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  account_key - AccountKey from get-accounts.sh" >&2
    echo "  uic         - Universal Instrument Code" >&2
    echo "  buy_sell    - 'Buy' or 'Sell'" >&2
    echo "  amount      - Order amount" >&2
    echo "  order_type  - 'Market' or 'Limit'" >&2
    echo "  order_price - Price (required for Limit orders)" >&2
    echo "  asset_type  - Asset type (default: FxSpot)" >&2
    exit 1
fi

# Validate buy_sell
if [[ "$BUY_SELL" != "Buy" && "$BUY_SELL" != "Sell" ]]; then
    echo "Error: buy_sell must be 'Buy' or 'Sell'" >&2
    exit 1
fi

# Validate order_type
if [[ "$ORDER_TYPE" != "Market" && "$ORDER_TYPE" != "Limit" ]]; then
    echo "Error: order_type must be 'Market' or 'Limit'" >&2
    exit 1
fi

# Require price for Limit orders
if [[ "$ORDER_TYPE" == "Limit" && -z "$ORDER_PRICE" ]]; then
    echo "Error: order_price is required for Limit orders" >&2
    exit 1
fi

# Build order JSON
if [[ "$ORDER_TYPE" == "Market" ]]; then
    ORDER_JSON=$(jq -n \
        --arg accountKey "$ACCOUNT_KEY" \
        --argjson uic "$UIC" \
        --arg buySell "$BUY_SELL" \
        --argjson amount "$AMOUNT" \
        --arg assetType "$ASSET_TYPE" \
        '{
            AccountKey: $accountKey,
            Uic: $uic,
            BuySell: $buySell,
            Amount: $amount,
            AssetType: $assetType,
            OrderType: "Market",
            OrderRelation: "StandAlone",
            ManualOrder: true,
            OrderDuration: {
                DurationType: "DayOrder"
            }
        }')
else
    ORDER_JSON=$(jq -n \
        --arg accountKey "$ACCOUNT_KEY" \
        --argjson uic "$UIC" \
        --arg buySell "$BUY_SELL" \
        --argjson amount "$AMOUNT" \
        --argjson orderPrice "$ORDER_PRICE" \
        --arg assetType "$ASSET_TYPE" \
        '{
            AccountKey: $accountKey,
            Uic: $uic,
            BuySell: $buySell,
            Amount: $amount,
            AssetType: $assetType,
            OrderType: "Limit",
            OrderPrice: $orderPrice,
            OrderRelation: "StandAlone",
            ManualOrder: true,
            OrderDuration: {
                DurationType: "GoodTillCancel"
            }
        }')
fi

echo "=== Order Request ===" >&2
echo "$ORDER_JSON" | jq . >&2
echo "" >&2

# Confirm before placing order
echo "Placing order..." >&2

RESPONSE=$(curl -s -X POST "$SAXO_BASE_URL/trade/v2/orders" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$ORDER_JSON")

if echo "$RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error placing order:" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

echo "" >&2
echo "=== Order Response ===" >&2
echo "$RESPONSE" | jq . >&2

# Output JSON for script consumption
echo ""
echo "$RESPONSE"
