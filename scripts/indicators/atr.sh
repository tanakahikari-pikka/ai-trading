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

# Calculate ATR with relative volatility (ATR / ATR_EMA)
# EMA responds faster to regime changes than SMA
ATR_EMA_PERIOD=50

ATR_DATA=$(echo "$INPUT" | jq --arg period "$PERIOD" --arg ema_period "$ATR_EMA_PERIOD" '
    ($period | tonumber) as $p |
    ($ema_period | tonumber) as $ep |
    (2 / ($ep + 1)) as $ema_multiplier |
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
    ) as $true_ranges |

    # Calculate rolling ATR values
    if ($true_ranges | length) >= ($p + $ep) then
        # Calculate ATR values for each period (rolling window)
        [range($ep + 1)] | map(
            . as $offset |
            $true_ranges[-($p + $ep - $offset):][:$p] | add / $p
        ) as $atr_series |

        # Calculate EMA of ATR series
        # Start with SMA of first $ep values as initial EMA
        ($atr_series[:$ep] | add / $ep) as $initial_ema |

        # Apply EMA formula: EMA = (current - prev_ema) * multiplier + prev_ema
        (reduce $atr_series[$ep:][] as $atr (
            $initial_ema;
            ($atr - .) * $ema_multiplier + .
        )) as $atr_ema |

        # Current ATR (most recent)
        ($atr_series | last) as $current_atr |

        # Relative ATR ratio (continuous volatility score)
        (if $atr_ema > 0 then $current_atr / $atr_ema else 1 end) as $atr_ratio |

        {
            atr: $current_atr,
            atr_ema: $atr_ema,
            atr_ratio: ($atr_ratio * 100 | round / 100),
            period: $p,
            ema_period: $ep
        }
    else
        # Fallback: not enough data for EMA, use simple ATR
        ($true_ranges[-$p:] | add / $p) as $current_atr |
        {
            atr: $current_atr,
            atr_ema: null,
            atr_ratio: 1,
            period: $p,
            ema_period: $ep
        }
    end
')

ATR_VALUE=$(echo "$ATR_DATA" | jq -r '.atr | . * 10000 | round / 10000')

# Calculate ATR as percentage of current price
CURRENT_PRICE=$(echo "$INPUT" | jq -r '.close[-1] // .regularMarketPrice // 1')
ATR_PCT=$(echo "$ATR_DATA" | jq -r --arg price "$CURRENT_PRICE" '
    ($price | tonumber) as $p |
    .atr / $p * 100 | . * 100 | round / 100
')

# Get ATR ratio for volatility classification
ATR_RATIO=$(echo "$ATR_DATA" | jq -r '.atr_ratio // 1')
ATR_EMA=$(echo "$ATR_DATA" | jq -r '.atr_ema // "null"')

ATR_DATA=$(echo "$ATR_DATA" | jq --arg pct "$ATR_PCT" --arg price "$CURRENT_PRICE" '
    . + {
        atr_percent: ($pct | tonumber),
        current_price: ($price | tonumber),
        # Backward compatible volatility label based on atr_ratio
        # ratio > 1.5 = high (50% above average)
        # ratio < 0.7 = low (30% below average)
        # else = medium
        volatility: (
            if .atr_ratio > 1.5 then "high"
            elif .atr_ratio < 0.7 then "low"
            else "medium"
            end
        )
    }
')

echo "=== ATR($PERIOD) ===" >&2
echo "ATR: $ATR_VALUE" >&2
echo "ATR%: $ATR_PCT%" >&2
echo "ATR_EMA(50): $ATR_EMA" >&2
echo "ATR Ratio: $ATR_RATIO (relative volatility score)" >&2

echo ""
echo "$ATR_DATA"
