#!/bin/bash
# Configuration loader for currency pairs
# Usage: source lib/config.sh && load_currency_config "USDJPY"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$LIB_DIR/../config/currencies"
STRATEGIES_DIR="$LIB_DIR/../config/strategies"
ASSIGNMENTS_FILE="$LIB_DIR/../config/assignments.json"

# Get strategies assigned to a currency
# Usage: get_strategies_for_currency <symbol>
# Returns: Array of strategy names (newline-separated)
get_strategies_for_currency() {
    local symbol="$1"

    if [[ -f "$ASSIGNMENTS_FILE" ]]; then
        jq -r --arg sym "$symbol" '.[$sym] // ["mean-reversion"] | .[]' "$ASSIGNMENTS_FILE"
    else
        echo "mean-reversion"
    fi
}

# Load merged configuration (currency + strategy defaults + overrides)
# Usage: load_merged_config <symbol> [strategy]
# Returns: Merged JSON to stdout
load_merged_config() {
    local symbol="$1"
    local strategy="${2:-}"
    local currency_file="$CONFIG_DIR/${symbol}.json"

    if [[ ! -f "$currency_file" ]]; then
        echo "{}"
        return 1
    fi

    # If strategy not specified, get from assignments (first one)
    if [[ -z "$strategy" ]]; then
        strategy=$(get_strategies_for_currency "$symbol" | head -n1)
    fi

    local strategy_defaults="$STRATEGIES_DIR/$strategy/defaults.json"
    local strategy_override="$STRATEGIES_DIR/$strategy/overrides/${symbol}.json"

    # Start with currency config
    local merged
    merged=$(cat "$currency_file")

    # Merge strategy defaults (if exists)
    if [[ -f "$strategy_defaults" ]]; then
        merged=$(echo "$merged" | jq --slurpfile defaults "$strategy_defaults" '. * $defaults[0]')
    fi

    # Merge currency-specific override (if exists)
    if [[ -f "$strategy_override" ]]; then
        merged=$(echo "$merged" | jq --slurpfile override "$strategy_override" '. * $override[0]')
    fi

    echo "$merged"
}

# Load currency configuration
# Usage: load_currency_config <symbol>
# Sets global variables: SYMBOL, YAHOO_SYMBOL, SAXO_UIC, etc.
load_currency_config() {
    local symbol="$1"
    local config_file="$CONFIG_DIR/${symbol}.json"

    if [[ ! -f "$config_file" ]]; then
        echo "Error: Configuration file not found: $config_file" >&2
        echo "Available currencies:" >&2
        list_available_currencies >&2
        return 1
    fi

    # Get merged configuration
    local merged_config
    merged_config=$(load_merged_config "$symbol")

    # Load configuration into global variables
    SYMBOL=$(echo "$merged_config" | jq -r '.symbol')
    YAHOO_SYMBOL=$(echo "$merged_config" | jq -r '.yahoo_symbol')
    SAXO_UIC=$(echo "$merged_config" | jq -r '.saxo_uic')
    SAXO_ASSET_TYPE=$(echo "$merged_config" | jq -r '.saxo_asset_type')
    DISPLAY_NAME=$(echo "$merged_config" | jq -r '.display_name')
    DESCRIPTION=$(echo "$merged_config" | jq -r '.description')
    PIP_SIZE=$(echo "$merged_config" | jq -r '.pip_size')
    DECIMAL_PLACES=$(echo "$merged_config" | jq -r '.decimal_places')
    DEFAULT_PERCENTAGE=$(echo "$merged_config" | jq -r '.default_percentage')

    # Thresholds
    RSI_OVERBOUGHT=$(echo "$merged_config" | jq -r '.thresholds.rsi_overbought')
    RSI_OVERSOLD=$(echo "$merged_config" | jq -r '.thresholds.rsi_oversold')
    RSI_BUY_THRESHOLD=$(echo "$merged_config" | jq -r '.thresholds.rsi_buy_threshold')
    RSI_SELL_THRESHOLD=$(echo "$merged_config" | jq -r '.thresholds.rsi_sell_threshold')
    MIN_CONDITIONS=$(echo "$merged_config" | jq -r '.thresholds.min_conditions')
    FRESH_CROSS_LOOKBACK=$(echo "$merged_config" | jq -r '.thresholds.fresh_cross_lookback // 5')

    # Timeframes (ENV > JSON for workflow override)
    PRIMARY_TIMEFRAME="${PRIMARY_TIMEFRAME:-$(echo "$merged_config" | jq -r '.timeframes.primary')}"
    PRIMARY_RANGE="${PRIMARY_RANGE:-$(echo "$merged_config" | jq -r '.timeframes.primary_range')}"
    SECONDARY_TIMEFRAME="${SECONDARY_TIMEFRAME:-$(echo "$merged_config" | jq -r '.timeframes.secondary')}"
    SECONDARY_RANGE="${SECONDARY_RANGE:-$(echo "$merged_config" | jq -r '.timeframes.secondary_range')}"

    # SL/TP settings
    SL_TP_ENABLED=$(echo "$merged_config" | jq -r '.sl_tp.enabled // false')
    SL_MODE=$(echo "$merged_config" | jq -r '.sl_tp.stop_loss.mode // "atr"')
    SL_MULTIPLIER=$(echo "$merged_config" | jq -r '.sl_tp.stop_loss.multiplier // 1.5')
    TP_MODE=$(echo "$merged_config" | jq -r '.sl_tp.take_profit.mode // "ratio"')
    TP_VALUE=$(echo "$merged_config" | jq -r '.sl_tp.take_profit.value // 2.0')

    # Trading limits
    MAX_AMOUNT=$(echo "$merged_config" | jq -r '.max_amount // 10000')

    # Strategy from assignments (first one for backward compatibility)
    STRATEGY=$(get_strategies_for_currency "$symbol" | head -n1)

    # Export for subshells
    export SYMBOL YAHOO_SYMBOL SAXO_UIC SAXO_ASSET_TYPE DISPLAY_NAME DESCRIPTION
    export PIP_SIZE DECIMAL_PLACES DEFAULT_PERCENTAGE MAX_AMOUNT
    export RSI_OVERBOUGHT RSI_OVERSOLD RSI_BUY_THRESHOLD RSI_SELL_THRESHOLD MIN_CONDITIONS FRESH_CROSS_LOOKBACK
    export PRIMARY_TIMEFRAME PRIMARY_RANGE SECONDARY_TIMEFRAME SECONDARY_RANGE
    export SL_TP_ENABLED SL_MODE SL_MULTIPLIER TP_MODE TP_VALUE
    export STRATEGY

    return 0
}

# List available currency configurations
list_available_currencies() {
    echo "Available currencies:"
    for config in "$CONFIG_DIR"/*.json; do
        if [[ -f "$config" ]]; then
            local sym=$(jq -r '.symbol' "$config")
            local desc=$(jq -r '.description' "$config")
            echo "  $sym - $desc"
        fi
    done
}

# Get currency config as JSON
get_currency_config_json() {
    local symbol="$1"
    local config_file="$CONFIG_DIR/${symbol}.json"

    if [[ -f "$config_file" ]]; then
        cat "$config_file"
    else
        echo "{}"
    fi
}

# Validate currency symbol
validate_currency() {
    local symbol="$1"
    local config_file="$CONFIG_DIR/${symbol}.json"
    [[ -f "$config_file" ]]
}

# Get strategy analyze script path
# Usage: get_strategy_analyze_script <strategy_name>
# Returns: path to analyze.sh, or empty if not found
get_strategy_analyze_script() {
    local strategy="${1:-mean-reversion}"
    local strategy_dir="$LIB_DIR/../strategies/$strategy"
    local script="$strategy_dir/analyze.sh"

    if [[ -f "$script" ]]; then
        echo "$script"
        return 0
    fi

    # Fallback to indicators/analyze.sh for backward compatibility
    local fallback="$LIB_DIR/../indicators/analyze.sh"
    if [[ -f "$fallback" ]]; then
        echo "$fallback"
        return 0
    fi

    return 1
}

# Validate strategy exists
# Usage: validate_strategy <strategy_name>
validate_strategy() {
    local strategy="$1"
    local strategy_dir="$LIB_DIR/../strategies/$strategy"
    [[ -d "$strategy_dir" && -f "$strategy_dir/analyze.sh" ]]
}
