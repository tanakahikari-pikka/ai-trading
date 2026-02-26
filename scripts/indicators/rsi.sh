#!/bin/bash
# Calculate RSI (Relative Strength Index)
# Usage: rsi.sh [period] [overbought] [oversold] < price_data.json
#
# Input: JSON with "close" array from get-chart.sh
# Output: JSON with RSI value and signal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PERIOD=${1:-14}
OVERBOUGHT=${2:-70}
OVERSOLD=${3:-30}

# Read input from stdin
INPUT=$(cat)

# Extract close prices
CLOSES=$(echo "$INPUT" | jq -r '.close // .')

# Validate input
if [[ -z "$CLOSES" || "$CLOSES" == "null" ]]; then
    echo "Error: No close prices found in input" >&2
    echo "Input should be JSON with 'close' array" >&2
    exit 1
fi

PRICE_COUNT=$(echo "$CLOSES" | jq 'length')

if [[ "$PRICE_COUNT" -lt "$((PERIOD + 1))" ]]; then
    echo "Error: Not enough data points. Need at least $((PERIOD + 1)), got $PRICE_COUNT" >&2
    exit 1
fi

# Calculate RSI using jq
RSI_DATA=$(echo "$CLOSES" | jq --arg period "$PERIOD" --arg overbought "$OVERBOUGHT" --arg oversold "$OVERSOLD" '
    ($period | tonumber) as $p |
    ($overbought | tonumber) as $ob |
    ($oversold | tonumber) as $os |

    # Filter out null values
    [.[] | select(. != null)] |

    # Calculate price changes
    . as $prices |
    [range(1; length)] | map($prices[.] - $prices[. - 1]) |

    # Separate gains and losses
    . as $changes |
    {
        gains: [$changes[] | if . > 0 then . else 0 end],
        losses: [$changes[] | if . < 0 then (. * -1) else 0 end]
    } |

    # Calculate average gains and losses for the period
    .gains[-$p:] as $recent_gains |
    .losses[-$p:] as $recent_losses |
    ($recent_gains | add / $p) as $avg_gain |
    ($recent_losses | add / $p) as $avg_loss |

    # Calculate RS and RSI
    if $avg_loss == 0 then
        {rs: null, rsi: 100}
    else
        ($avg_gain / $avg_loss) as $rs |
        {rs: $rs, rsi: (100 - (100 / (1 + $rs)))}
    end |

    # Add signal
    .rsi as $rsi |
    . + {
        signal: (
            if $rsi > $ob then "overbought"
            elif $rsi < $os then "oversold"
            else "neutral"
            end
        ),
        tradeSignal: (
            if $rsi > $ob then "Sell"
            elif $rsi < $os then "Buy"
            else "Wait"
            end
        ),
        period: $p,
        overbought: $ob,
        oversold: $os
    }
')

# Get values for display
RSI_VALUE=$(echo "$RSI_DATA" | jq -r '.rsi | . * 100 | round / 100')
SIGNAL=$(echo "$RSI_DATA" | jq -r '.signal')
TRADE_SIGNAL=$(echo "$RSI_DATA" | jq -r '.tradeSignal')

# Display summary
echo "=== RSI($PERIOD) ===" >&2
echo "Value: $RSI_VALUE" >&2
echo "Signal: $SIGNAL" >&2
echo "Trade: $TRADE_SIGNAL" >&2

# Output JSON
echo ""
echo "$RSI_DATA"
