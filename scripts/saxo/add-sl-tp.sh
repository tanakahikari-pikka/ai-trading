#!/bin/bash
set -eo pipefail
# Add Stop Loss and Take Profit to existing position
# Usage: add-sl-tp.sh <position_id> <sl_price> [tp_price]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

POSITION_ID="$1"
SL_PRICE="$2"
TP_PRICE="$3"

if [[ -z "$POSITION_ID" || -z "$SL_PRICE" ]]; then
    echo "Usage: $0 <position_id> <sl_price> [tp_price]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  position_id - PositionId from get-positions.sh" >&2
    echo "  sl_price    - Stop Loss price" >&2
    echo "  tp_price    - Take Profit price (optional)" >&2
    exit 1
fi

# Get client key and account key
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

# Get position details
POSITION_RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/positions/$POSITION_ID?ClientKey=$ENCODED_CLIENT_KEY&FieldGroups=DisplayAndFormat,PositionBase" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$POSITION_RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching position:" >&2
    echo "$POSITION_RESPONSE" | jq . >&2
    exit 1
fi

SYMBOL=$(echo "$POSITION_RESPONSE" | jq -r '.DisplayAndFormat.Symbol')
AMOUNT=$(echo "$POSITION_RESPONSE" | jq -r '.PositionBase.Amount')
UIC=$(echo "$POSITION_RESPONSE" | jq -r '.PositionBase.Uic')
ASSET_TYPE=$(echo "$POSITION_RESPONSE" | jq -r '.PositionBase.AssetType')
ACCOUNT_KEY=$(echo "$POSITION_RESPONSE" | jq -r '.PositionBase.AccountKey')
OPEN_PRICE=$(echo "$POSITION_RESPONSE" | jq -r '.PositionBase.OpenPrice')

# Determine direction based on position amount
if (( $(echo "$AMOUNT > 0" | bc -l) )); then
    POSITION_DIRECTION="Long"
    SL_DIRECTION="Sell"
    TP_DIRECTION="Sell"
else
    POSITION_DIRECTION="Short"
    SL_DIRECTION="Buy"
    TP_DIRECTION="Buy"
fi

# Use absolute amount for orders
AMOUNT_ABS=$(echo "$AMOUNT" | tr -d '-')

echo "=== Position Info ===" >&2
echo "Symbol: $SYMBOL" >&2
echo "Position: $POSITION_DIRECTION (Amount: $AMOUNT)" >&2
echo "Open Price: $OPEN_PRICE" >&2
echo "UIC: $UIC" >&2
echo "Asset Type: $ASSET_TYPE" >&2
echo "Account Key: $ACCOUNT_KEY" >&2
echo "" >&2

# Build and place Stop Loss order
echo "=== Adding Stop Loss @ $SL_PRICE ===" >&2

SL_ORDER_JSON=$(jq -n \
    --arg accountKey "$ACCOUNT_KEY" \
    --argjson uic "$UIC" \
    --arg buySell "$SL_DIRECTION" \
    --argjson amount "$AMOUNT_ABS" \
    --argjson orderPrice "$SL_PRICE" \
    --arg assetType "$ASSET_TYPE" \
    --arg positionId "$POSITION_ID" \
    '{
        AccountKey: $accountKey,
        Uic: $uic,
        BuySell: $buySell,
        Amount: $amount,
        AssetType: $assetType,
        OrderType: "Stop",
        OrderPrice: $orderPrice,
        ManualOrder: true,
        OrderRelation: "StandAlone",
        OrderDuration: {
            DurationType: "GoodTillCancel"
        },
        RelatedPositionId: $positionId
    }')

echo "$SL_ORDER_JSON" | jq . >&2

SL_RESPONSE=$(curl -s -X POST "$SAXO_BASE_URL/trade/v2/orders" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SL_ORDER_JSON")

if echo "$SL_RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error placing Stop Loss:" >&2
    echo "$SL_RESPONSE" | jq . >&2
    # Continue to TP if SL failed
else
    echo "Stop Loss placed successfully:" >&2
    echo "$SL_RESPONSE" | jq . >&2
fi

echo "" >&2

# Place Take Profit if specified
if [[ -n "$TP_PRICE" ]]; then
    echo "=== Adding Take Profit @ $TP_PRICE ===" >&2

    TP_ORDER_JSON=$(jq -n \
        --arg accountKey "$ACCOUNT_KEY" \
        --argjson uic "$UIC" \
        --arg buySell "$TP_DIRECTION" \
        --argjson amount "$AMOUNT_ABS" \
        --argjson orderPrice "$TP_PRICE" \
        --arg assetType "$ASSET_TYPE" \
        --arg positionId "$POSITION_ID" \
        '{
            AccountKey: $accountKey,
            Uic: $uic,
            BuySell: $buySell,
            Amount: $amount,
            AssetType: $assetType,
            OrderType: "Limit",
            OrderPrice: $orderPrice,
            ManualOrder: true,
            OrderRelation: "StandAlone",
            OrderDuration: {
                DurationType: "GoodTillCancel"
            },
            RelatedPositionId: $positionId
        }')

    echo "$TP_ORDER_JSON" | jq . >&2

    TP_RESPONSE=$(curl -s -X POST "$SAXO_BASE_URL/trade/v2/orders" \
        -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$TP_ORDER_JSON")

    if echo "$TP_RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
        echo "Error placing Take Profit:" >&2
        echo "$TP_RESPONSE" | jq . >&2
    else
        echo "Take Profit placed successfully:" >&2
        echo "$TP_RESPONSE" | jq . >&2
    fi
fi

echo "" >&2
echo "=== Complete ===" >&2
