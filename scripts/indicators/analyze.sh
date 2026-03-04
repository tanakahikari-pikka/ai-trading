#!/bin/bash
# Comprehensive Technical Analysis - Compatibility Wrapper
# Usage: analyze.sh < price_data.json
#
# This script is a compatibility wrapper that delegates to the
# strategy-based analysis system. For new implementations, use
# scripts/strategies/<strategy>/analyze.sh directly.
#
# Input: JSON with OHLC data from get-chart.sh
# Output: JSON with all indicators and rule-based signal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default to mean-reversion strategy for backward compatibility
STRATEGY="${STRATEGY:-mean-reversion}"
STRATEGY_SCRIPT="$SCRIPT_DIR/../strategies/$STRATEGY/analyze.sh"

if [[ -f "$STRATEGY_SCRIPT" ]]; then
    # Delegate to strategy-specific analyzer
    exec "$STRATEGY_SCRIPT"
else
    echo "Error: Strategy script not found: $STRATEGY_SCRIPT" >&2
    echo "Available strategies:" >&2
    for dir in "$SCRIPT_DIR/../strategies"/*/; do
        if [[ -d "$dir" && -f "$dir/analyze.sh" ]]; then
            echo "  - $(basename "$dir")" >&2
        fi
    done
    exit 1
fi
