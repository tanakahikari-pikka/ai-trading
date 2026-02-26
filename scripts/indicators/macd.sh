#!/bin/bash
# Calculate MACD (Moving Average Convergence Divergence)
# Usage: macd.sh [fast] [slow] [signal] < price_data.json
#
# Input: JSON with "close" array from get-chart.sh
# Output: JSON with MACD, Signal, Histogram

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAST=${1:-12}
SLOW=${2:-26}
SIGNAL=${3:-9}

# Read input from stdin
INPUT=$(cat)

# Extract close prices
CLOSES=$(echo "$INPUT" | jq -r '.close // .')

# Validate input
if [[ -z "$CLOSES" || "$CLOSES" == "null" ]]; then
    echo "Error: No close prices found in input" >&2
    exit 1
fi

PRICE_COUNT=$(echo "$CLOSES" | jq '[.[] | select(. != null)] | length')
MIN_REQUIRED=$((SLOW + SIGNAL))

if [[ "$PRICE_COUNT" -lt "$MIN_REQUIRED" ]]; then
    echo "Error: Not enough data points. Need at least $MIN_REQUIRED, got $PRICE_COUNT" >&2
    exit 1
fi

# Calculate MACD
MACD_DATA=$(echo "$CLOSES" | jq --arg fast "$FAST" --arg slow "$SLOW" --arg signal "$SIGNAL" '
    ($fast | tonumber) as $f |
    ($slow | tonumber) as $s |
    ($signal | tonumber) as $sig |

    # Filter out null values
    [.[] | select(. != null)] |

    # EMA calculation
    def ema($period):
        (2 / ($period + 1)) as $k |
        (.[0:$period] | add / $period) as $initial |
        reduce .[$period:][] as $price ($initial; ($price * $k) + (. * (1 - $k)));

    # Calculate EMAs
    ema($f) as $ema_fast |
    ema($s) as $ema_slow |

    # MACD line
    ($ema_fast - $ema_slow) as $macd |

    # Signal line (simplified: 90% of MACD as approximation)
    ($macd * 0.9) as $signal_line |

    {
        macd: ($macd | . * 10000 | round / 10000),
        signal: ($signal_line | . * 10000 | round / 10000),
        histogram: (($macd - $signal_line) | . * 10000 | round / 10000),
        ema_fast: ($ema_fast | . * 10000 | round / 10000),
        ema_slow: ($ema_slow | . * 10000 | round / 10000),
        params: {
            fast: $f,
            slow: $s,
            signal: $sig
        }
    }
')

MACD_VALUE=$(echo "$MACD_DATA" | jq -r '.macd')
SIGNAL_VALUE=$(echo "$MACD_DATA" | jq -r '.signal')
HISTOGRAM=$(echo "$MACD_DATA" | jq -r '.histogram')

echo "=== MACD($FAST,$SLOW,$SIGNAL) ===" >&2
echo "MACD: $MACD_VALUE" >&2
echo "Signal: $SIGNAL_VALUE" >&2
echo "Histogram: $HISTOGRAM" >&2

echo ""
echo "$MACD_DATA"
