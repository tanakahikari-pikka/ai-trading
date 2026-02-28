#!/bin/bash
# Calculate Bollinger Bands
# Usage: bollinger.sh [period] [std_dev] < price_data.json
#
# Input: JSON with "close" array from get-chart.sh
# Output: JSON with upper, middle, lower bands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PERIOD=${1:-20}
STD_DEV=${2:-2}

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

# Calculate Bollinger Bands
BB_DATA=$(echo "$CLOSES" | jq --arg period "$PERIOD" --arg std "$STD_DEV" '
    ($period | tonumber) as $p |
    ($std | tonumber) as $sd |
    [.[] | select(. != null)] |
    .[-$p:] as $recent |

    # Calculate SMA (middle band)
    ($recent | add / $p) as $sma |

    # Calculate standard deviation
    ($recent | map(. - $sma | . * .) | add / $p | sqrt) as $stdev |

    # Calculate bands
    {
        upper: ($sma + ($stdev * $sd)),
        middle: $sma,
        lower: ($sma - ($stdev * $sd)),
        std_dev: $stdev,
        params: {
            period: $p,
            std_multiplier: $sd
        }
    }
')

# Get current price for position analysis
CURRENT_PRICE=$(echo "$INPUT" | jq -r '.close[-1] // .regularMarketPrice // 0')
UPPER=$(echo "$BB_DATA" | jq -r '.upper | . * 100 | round / 100')
MIDDLE=$(echo "$BB_DATA" | jq -r '.middle | . * 100 | round / 100')
LOWER=$(echo "$BB_DATA" | jq -r '.lower | . * 100 | round / 100')

# Add position relative to bands and band width metrics
BB_DATA=$(echo "$BB_DATA" | jq --arg price "$CURRENT_PRICE" '
    ($price | tonumber) as $p |
    # Band width as percentage of middle band (for squeeze detection)
    ((.upper - .lower) / .middle * 100) as $band_width_pct |
    . + {
        current_price: $p,
        position: (
            if $p > .upper then "above_upper"
            elif $p > .middle then "upper_half"
            elif $p > .lower then "lower_half"
            else "below_lower"
            end
        ),
        percent_b: (($p - .lower) / (.upper - .lower) * 100),
        band_width_pct: ($band_width_pct | . * 100 | round / 100)
    }
')

echo "=== Bollinger Bands($PERIOD, ${STD_DEV}σ) ===" >&2
echo "Upper: $UPPER" >&2
echo "Middle: $MIDDLE" >&2
echo "Lower: $LOWER" >&2

echo ""
echo "$BB_DATA"
