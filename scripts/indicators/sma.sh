#!/bin/bash
# Calculate SMA (Simple Moving Average)
# Usage: sma.sh [period] < price_data.json
#
# Input: JSON with "close" array from get-chart.sh
# Output: JSON with SMA value

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PERIOD=${1:-20}

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

# Calculate SMA
SMA_DATA=$(echo "$CLOSES" | jq --arg period "$PERIOD" '
    ($period | tonumber) as $p |
    [.[] | select(. != null)] |
    .[-$p:] | add / $p |
    {
        sma: .,
        period: $p
    }
')

SMA_VALUE=$(echo "$SMA_DATA" | jq -r '.sma | . * 10000 | round / 10000')

echo "=== SMA($PERIOD) ===" >&2
echo "Value: $SMA_VALUE" >&2

echo ""
echo "$SMA_DATA"
