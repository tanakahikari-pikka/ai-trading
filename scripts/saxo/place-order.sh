#!/bin/bash
# Place a Market order on Saxo Bank API with optional SL/TP
# Usage: place-order.sh <account_key> <uic> <buy_sell> <amount> [asset_type] [sl_price] [tp_price]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

ACCOUNT_KEY="$1"
UIC="$2"
BUY_SELL="$3"
AMOUNT="$4"
ASSET_TYPE="${5:-FxSpot}"
SL_PRICE="$6"
TP_PRICE="$7"

if [[ -z "$ACCOUNT_KEY" || -z "$UIC" || -z "$BUY_SELL" || -z "$AMOUNT" ]]; then
    echo "Usage: $0 <account_key> <uic> <buy_sell> <amount> [asset_type] [sl_price] [tp_price]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  account_key - AccountKey from get-accounts.sh" >&2
    echo "  uic         - Universal Instrument Code" >&2
    echo "  buy_sell    - 'Buy' or 'Sell'" >&2
    echo "  amount      - Order amount" >&2
    echo "  asset_type  - Asset type (default: FxSpot)" >&2
    echo "  sl_price    - Stop Loss price (optional)" >&2
    echo "  tp_price    - Take Profit price (optional)" >&2
    exit 1
fi

# Validate buy_sell
if [[ "$BUY_SELL" != "Buy" && "$BUY_SELL" != "Sell" ]]; then
    echo "Error: buy_sell must be 'Buy' or 'Sell'" >&2
    exit 1
fi

# Determine opposite direction for SL/TP orders
if [[ "$BUY_SELL" == "Buy" ]]; then
    CLOSE_DIRECTION="Sell"
else
    CLOSE_DIRECTION="Buy"
fi

# Build related orders array for SL/TP
build_related_orders() {
    local sl="$1"
    local tp="$2"
    local close_dir="$3"

    local orders="[]"

    # Add Stop Loss order
    if [[ -n "$sl" && "$sl" != "" ]]; then
        orders=$(echo "$orders" | jq \
            --arg buySell "$close_dir" \
            --argjson orderPrice "$sl" \
            '. + [{
                BuySell: $buySell,
                OrderPrice: $orderPrice,
                OrderType: "Stop",
                ManualOrder: true,
                OrderDuration: {
                    DurationType: "GoodTillCancel"
                }
            }]')
    fi

    # Add Take Profit order
    if [[ -n "$tp" && "$tp" != "" ]]; then
        orders=$(echo "$orders" | jq \
            --arg buySell "$close_dir" \
            --argjson orderPrice "$tp" \
            '. + [{
                BuySell: $buySell,
                OrderPrice: $orderPrice,
                OrderType: "Limit",
                ManualOrder: true,
                OrderDuration: {
                    DurationType: "GoodTillCancel"
                }
            }]')
    fi

    echo "$orders"
}

# Build order JSON (Market order only)
if [[ -n "$SL_PRICE" || -n "$TP_PRICE" ]]; then
    RELATED_ORDERS=$(build_related_orders "$SL_PRICE" "$TP_PRICE" "$CLOSE_DIRECTION")
    ORDER_JSON=$(jq -n \
        --arg accountKey "$ACCOUNT_KEY" \
        --argjson uic "$UIC" \
        --arg buySell "$BUY_SELL" \
        --argjson amount "$AMOUNT" \
        --arg assetType "$ASSET_TYPE" \
        --argjson orders "$RELATED_ORDERS" \
        '{
            AccountKey: $accountKey,
            Uic: $uic,
            BuySell: $buySell,
            Amount: $amount,
            AssetType: $assetType,
            OrderType: "Market",
            ManualOrder: true,
            OrderDuration: {
                DurationType: "DayOrder"
            },
            Orders: $orders
        }')
else
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
