#!/bin/bash
# Strategy Base Interface
# All strategies must conform to this interface
#
# Input: JSON with OHLC data from get-chart.sh via stdin
# Output: JSON with required fields:
#   - signal: "Buy" | "Sell" | "Wait"
#   - trend: "上昇" | "下降" | "横ばい"
#   - buy_conditions_met: number (for display)
#   - sell_conditions_met: number (for display)
#   - indicators: { rsi_14, sma_20, sma_50, ... }
#   - rule_analysis: { ... }
#
# Usage:
#   cat price_data.json | ./strategies/<strategy-name>/analyze.sh

# Strategy types registry
readonly STRATEGY_TYPES=(
    "mean-reversion"
    "trend-following"
    "breakout"
)

# Validate strategy output has required fields
# Usage: validate_strategy_output <json_output>
validate_strategy_output() {
    local output="$1"

    # Check required top-level fields
    local signal=$(echo "$output" | jq -r '.rule_analysis.signal // empty')
    local trend=$(echo "$output" | jq -r '.rule_analysis.trend // empty')
    local buy_conditions=$(echo "$output" | jq -r '.rule_analysis.buy_conditions_met // empty')
    local sell_conditions=$(echo "$output" | jq -r '.rule_analysis.sell_conditions_met // empty')

    if [[ -z "$signal" || -z "$trend" ]]; then
        echo "Error: Strategy output missing required fields (signal, trend)" >&2
        return 1
    fi

    # Validate signal value
    if [[ "$signal" != "Buy" && "$signal" != "Sell" && "$signal" != "Wait" ]]; then
        echo "Error: Invalid signal value: $signal (expected: Buy|Sell|Wait)" >&2
        return 1
    fi

    return 0
}

# Check if strategy exists
# Usage: strategy_exists <strategy_name>
strategy_exists() {
    local strategy="$1"
    local strategy_dir
    strategy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/$strategy"

    [[ -d "$strategy_dir" && -f "$strategy_dir/analyze.sh" ]]
}

# Get strategy analyze script path
# Usage: get_strategy_script <strategy_name>
get_strategy_script() {
    local strategy="$1"
    local strategy_dir
    strategy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/$strategy"

    if [[ -f "$strategy_dir/analyze.sh" ]]; then
        echo "$strategy_dir/analyze.sh"
        return 0
    fi

    return 1
}

# List available strategies
# Usage: list_strategies
list_strategies() {
    local base_dir
    base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    echo "Available strategies:"
    for strategy_dir in "$base_dir"/*/; do
        local strategy_name=$(basename "$strategy_dir")
        # Skip base directory
        [[ "$strategy_name" == "base" ]] && continue

        if [[ -f "$strategy_dir/analyze.sh" ]]; then
            local config_file="$strategy_dir/config.json"
            if [[ -f "$config_file" ]]; then
                local desc=$(jq -r '.description // "No description"' "$config_file")
                echo "  $strategy_name - $desc"
            else
                echo "  $strategy_name"
            fi
        fi
    done
}
