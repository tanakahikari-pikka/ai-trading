#!/bin/bash
# Calculate EMA (Exponential Moving Average)
# Usage: ema.sh [period] < price_data.json
#
# Input: JSON with "close" array from get-chart.sh
# Output: JSON with EMA value

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PERIOD=${1:-12}

# Read input from stdin
INPUT=$(cat)

# Extract close prices
CLOSES=$(echo "$INPUT" | jq -r '.close // .')

# Validate input
if [[ -z "$CLOSES" || "$CLOSES" == "null" ]]; then
    echo "Error: No close prices found in input" >&2
    exit 1
fi

PRICE_COUNT=$(echo "$CLOSES" | jq 'length')

if [[ "$PRICE_COUNT" -lt "$PERIOD" ]]; then
    echo "Error: Not enough data points. Need at least $PERIOD, got $PRICE_COUNT" >&2
    exit 1
fi

# Calculate EMA
# EMA = Price(t) * k + EMA(y) * (1 - k)
# k = 2 / (N + 1)
EMA_DATA=$(echo "$CLOSES" | jq --arg period "$PERIOD" '
    ($period | tonumber) as $p |
    [.[] | select(. != null)] |
    (2 / ($p + 1)) as $k |

    # Start with SMA for first EMA value
    (.[0:$p] | add / $p) as $initial_ema |

    # Calculate EMA for remaining values
    .[$p:] | reduce .[] as $price (
        $initial_ema;
        ($price * $k) + (. * (1 - $k))
    ) |
    {
        ema: .,
        period: $p
    }
')

EMA_VALUE=$(echo "$EMA_DATA" | jq -r '.ema | . * 10000 | round / 10000')

echo "=== EMA($PERIOD) ===" >&2
echo "Value: $EMA_VALUE" >&2

echo ""
echo "$EMA_DATA"
