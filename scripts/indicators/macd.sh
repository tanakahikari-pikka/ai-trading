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

# Fresh cross lookback period (configurable per currency, default: 5)
LOOKBACK=${FRESH_CROSS_LOOKBACK:-5}

# Calculate MACD with histogram history
MACD_DATA=$(echo "$CLOSES" | jq --arg fast "$FAST" --arg slow "$SLOW" --arg signal "$SIGNAL" --argjson lookback "$LOOKBACK" '
    ($fast | tonumber) as $f |
    ($slow | tonumber) as $s |
    ($signal | tonumber) as $sig |

    # Filter out null values
    [.[] | select(. != null)] as $prices |

    # EMA series calculation (returns array of EMA values)
    def ema_series($period):
        (2 / ($period + 1)) as $k |
        (.[0:$period] | add / $period) as $initial |
        [$initial] + [
            foreach .[$period:][] as $price ($initial; ($price * $k) + (. * (1 - $k)))
        ];

    # Calculate EMA series for fast and slow
    ($prices | ema_series($f)) as $ema_fast_series |
    ($prices | ema_series($s)) as $ema_slow_series |

    # MACD line series (aligned from slow EMA start)
    # Fast EMA needs offset to align with slow EMA
    ($s - $f) as $offset |
    [range($ema_slow_series | length)] | map(
        $ema_fast_series[. + $offset] - $ema_slow_series[.]
    ) as $macd_series |

    # Signal line series (EMA of MACD)
    ($macd_series | ema_series($sig)) as $signal_series |

    # Histogram series
    ($sig - 1) as $sig_offset |
    [range($signal_series | length)] | map(
        $macd_series[. + $sig_offset] - $signal_series[.]
    ) as $histogram_series |

    # Get last values
    ($macd_series | last) as $macd |
    ($signal_series | last) as $signal_line |
    ($histogram_series | last) as $histogram |

    # Get last N histogram values for momentum/fresh cross detection (configurable)
    ($histogram_series | .[-$lookback:]) as $hist_last5 |

    {
        macd: ($macd | . * 10000 | round / 10000),
        signal: ($signal_line | . * 10000 | round / 10000),
        histogram: ($histogram | . * 10000 | round / 10000),
        histogram_history: ($hist_last5 | map(. * 10000 | round / 10000)),
        ema_fast: ($ema_fast_series | last | . * 10000 | round / 10000),
        ema_slow: ($ema_slow_series | last | . * 10000 | round / 10000),
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
