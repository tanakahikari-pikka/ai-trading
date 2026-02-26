#!/bin/bash
# Calculate ATR (Average True Range)
# Usage: atr.sh [period] < price_data.json
#
# Input: JSON with "high", "low", "close" arrays from get-chart.sh
# Output: JSON with ATR value

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PERIOD=${1:-14}

# Read input from stdin
INPUT=$(cat)

# Extract OHLC data
HIGH=$(echo "$INPUT" | jq -r '.high // empty')
LOW=$(echo "$INPUT" | jq -r '.low // empty')
CLOSE=$(echo "$INPUT" | jq -r '.close // empty')

# Validate input
if [[ -z "$HIGH" || -z "$LOW" || -z "$CLOSE" ]]; then
    echo "Error: Need high, low, close arrays in input" >&2
    exit 1
fi

PRICE_COUNT=$(echo "$CLOSE" | jq 'length')

if [[ "$PRICE_COUNT" -lt "$((PERIOD + 1))" ]]; then
    echo "Error: Not enough data points. Need at least $((PERIOD + 1)), got $PRICE_COUNT" >&2
    exit 1
fi

# Calculate ATR
ATR_DATA=$(echo "$INPUT" | jq --arg period "$PERIOD" '
    ($period | tonumber) as $p |
    .high as $h |
    .low as $l |
    .close as $c |

    # Filter out nulls and align arrays
    [range(1; ($c | length))] | map(
        select($h[.] != null and $l[.] != null and $c[.] != null and $c[. - 1] != null)
    ) |

    # Calculate True Range for each period
    map(
        . as $i |
        [
            ($h[$i] - $l[$i]),                    # High - Low
            (($h[$i] - $c[$i - 1]) | fabs),       # |High - Previous Close|
            (($l[$i] - $c[$i - 1]) | fabs)        # |Low - Previous Close|
        ] | max
    ) |

    # Calculate ATR (average of last N true ranges)
    .[-$p:] | add / $p |

    {
        atr: .,
        period: $p
    }
')

ATR_VALUE=$(echo "$ATR_DATA" | jq -r '.atr | . * 10000 | round / 10000')

# Calculate ATR as percentage of current price
CURRENT_PRICE=$(echo "$INPUT" | jq -r '.close[-1] // .regularMarketPrice // 1')
ATR_PCT=$(echo "$ATR_DATA" | jq -r --arg price "$CURRENT_PRICE" '
    ($price | tonumber) as $p |
    .atr / $p * 100 | . * 100 | round / 100
')

ATR_DATA=$(echo "$ATR_DATA" | jq --arg pct "$ATR_PCT" --arg price "$CURRENT_PRICE" '
    . + {
        atr_percent: ($pct | tonumber),
        current_price: ($price | tonumber),
        volatility: (
            if ($pct | tonumber) > 1 then "high"
            elif ($pct | tonumber) > 0.5 then "medium"
            else "low"
            end
        )
    }
')

echo "=== ATR($PERIOD) ===" >&2
echo "ATR: $ATR_VALUE" >&2
echo "ATR%: $ATR_PCT%" >&2

echo ""
echo "$ATR_DATA"
