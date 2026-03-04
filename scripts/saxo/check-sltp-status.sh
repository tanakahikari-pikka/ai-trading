#!/bin/bash
set -eo pipefail
# Check which positions are missing SL/TP orders
# Usage: check-sltp-status.sh
# Output: JSON array of positions without SL and/or TP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

# Get client key
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

# Get all positions
POSITIONS=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/positions?ClientKey=$ENCODED_CLIENT_KEY&FieldGroups=DisplayAndFormat,PositionBase,PositionView" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

POSITION_COUNT=$(echo "$POSITIONS" | jq '.Data | length')

if [[ "$POSITION_COUNT" -eq 0 ]]; then
    echo "No open positions." >&2
    echo "[]"
    exit 0
fi

# Get all orders
ORDERS=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/orders/me?FieldGroups=DisplayAndFormat,ExchangeInfo" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

# Build position list with SL/TP status
RESULT=$(echo "$POSITIONS" | jq --argjson orders "$ORDERS" '
    .Data | map(
        . as $pos |
        $pos.PositionId as $posId |
        $pos.DisplayAndFormat.Symbol as $symbol |
        $pos.PositionBase.Amount as $amount |

        # Determine close direction
        (if $amount > 0 then "Sell" else "Buy" end) as $closeDir |

        # Find related orders for this position
        ($orders.Data // [] | map(
            select(.RelatedPositionId == $posId or
                   (.DisplayAndFormat.Symbol == $symbol and .BuySell == $closeDir))
        )) as $relatedOrders |

        # Check for Stop orders (SL)
        ($relatedOrders | map(select(.OpenOrderType == "Stop" or .OpenOrderType == "StopIfTraded")) | length > 0) as $hasSL |

        # Check for Limit orders (TP)
        ($relatedOrders | map(select(.OpenOrderType == "Limit")) | length > 0) as $hasTP |

        {
            positionId: $posId,
            symbol: $symbol,
            amount: $amount,
            direction: (if $amount > 0 then "Long" else "Short" end),
            openPrice: $pos.PositionBase.OpenPrice,
            currentPrice: $pos.PositionView.CurrentPrice,
            uic: $pos.PositionBase.Uic,
            assetType: $pos.PositionBase.AssetType,
            accountKey: $pos.PositionBase.AccountKey,
            hasSL: $hasSL,
            hasTP: $hasTP,
            needsSL: ($hasSL | not),
            needsTP: ($hasTP | not)
        }
    ) | map(select(.needsSL or .needsTP))
')

# Count results
MISSING_COUNT=$(echo "$RESULT" | jq 'length')

echo "=== SL/TP Status Check ===" >&2
echo "Total positions: $POSITION_COUNT" >&2
echo "Missing SL/TP: $MISSING_COUNT" >&2

if [[ "$MISSING_COUNT" -gt 0 ]]; then
    echo "" >&2
    echo "Positions needing SL/TP:" >&2
    echo "$RESULT" | jq -r '.[] | "[\(.symbol)] \(.direction) \(.amount) @ \(.openPrice) | SL: \(if .needsSL then "MISSING" else "OK" end) | TP: \(if .needsTP then "MISSING" else "OK" end)"' >&2
fi

echo "$RESULT"
