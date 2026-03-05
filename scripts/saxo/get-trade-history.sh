#!/bin/bash
# Get trade history (order blotter) from Saxo Bank API
# Usage: get-trade-history.sh [days_back] [mode]
#   days_back: Number of days to look back (default: 7)
#   mode: "detailed" for per-trade analysis with round trips (default: summary)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/auth.sh"

DAYS_BACK="${1:-7}"
MODE="${2:-summary}"
FROM_DATE=$(date -v-${DAYS_BACK}d +%Y-%m-%dT00:00:00Z 2>/dev/null || date -d "-${DAYS_BACK} days" +%Y-%m-%dT00:00:00Z)
TO_DATE=$(date -v+1d +%Y-%m-%dT00:00:00Z 2>/dev/null || date -d "+1 day" +%Y-%m-%dT00:00:00Z)

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

# Get order activities
RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/cs/v1/audit/orderactivities?ClientKey=$ENCODED_CLIENT_KEY&FromDateTime=$FROM_DATE&ToDateTime=$TO_DATE" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching order activities:" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

# Detailed mode: Use trade-matcher for per-trade analysis
if [[ "$MODE" == "detailed" ]]; then
    source "$PROJECT_ROOT/scripts/report/lib/trade-matcher.sh"
    DETAILED=$(match_trades_fifo "$RESPONSE")

    # Add period info and output
    echo "$DETAILED" | jq --arg from "$FROM_DATE" --arg to "$TO_DATE" '
        . + {period: {from: $from, to: $to}}
    '
    exit 0
fi

# Default mode: Summary by instrument (original behavior)
echo "$RESPONSE" | jq --arg from "$FROM_DATE" --arg to "$TO_DATE" '
# UIC to Symbol mapping (from config/currencies/*.json + API search)
def uic_to_symbol:
  {
    "4": "AUDUSD",
    "18": "EURJPY",
    "21": "EURUSD",
    "26": "GBPJPY",
    "31": "GBPUSD",
    "38": "USDCAD",
    "42": "USDJPY",
    "47": "USDPLN",
    "8176": "XAUUSD",
    "8177": "XAGUSD",
    "107830": "XPTUSD"
  }[tostring] // "UIC:\(.)";

# Filter to FinalFill status only
[.Data[] | select(.Status == "FinalFill")] |

# Group by UIC and calculate summary
group_by(.Uic) | map({
  uic: .[0].Uic,
  symbol: (.[0].Uic | uic_to_symbol),
  trades: length,
  buy_count: [.[] | select(.BuySell == "Buy")] | length,
  sell_count: [.[] | select(.BuySell == "Sell")] | length,
  total_buy_amount: ([.[] | select(.BuySell == "Buy") | .Amount] | add // 0),
  total_sell_amount: ([.[] | select(.BuySell == "Sell") | .Amount] | add // 0),
  avg_buy_price: (([.[] | select(.BuySell == "Buy") | .Amount * .AveragePrice] | add // 0) / ([.[] | select(.BuySell == "Buy") | .Amount] | add // 1)),
  avg_sell_price: (([.[] | select(.BuySell == "Sell") | .Amount * .AveragePrice] | add // 0) / ([.[] | select(.BuySell == "Sell") | .Amount] | add // 1)),
  first_trade: (sort_by(.ActivityTime) | .[0].ActivityTime),
  last_trade: (sort_by(.ActivityTime) | .[-1].ActivityTime)
}) |

# Calculate P/L for closed positions
map(. + {
  net_position: (.total_buy_amount - .total_sell_amount),
  closed_amount: ([.total_buy_amount, .total_sell_amount] | min),
  pnl_per_unit: (if .total_sell_amount > 0 and .total_buy_amount > 0 then (.avg_sell_price - .avg_buy_price) else 0 end)
}) |

map(. + {
  estimated_pnl: (.closed_amount * .pnl_per_unit)
}) |

{
  period: {from: $from, to: $to},
  total_trades: (map(.trades) | add),
  by_instrument: .
}
'
