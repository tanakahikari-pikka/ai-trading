#!/bin/bash
# Configuration loader for currency pairs
# Usage: source lib/config.sh && load_currency_config "USDJPY"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$LIB_DIR/../config/currencies"

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

    # Load configuration into global variables
    SYMBOL=$(jq -r '.symbol' "$config_file")
    YAHOO_SYMBOL=$(jq -r '.yahoo_symbol' "$config_file")
    SAXO_UIC=$(jq -r '.saxo_uic' "$config_file")
    SAXO_ASSET_TYPE=$(jq -r '.saxo_asset_type' "$config_file")
    DISPLAY_NAME=$(jq -r '.display_name' "$config_file")
    DESCRIPTION=$(jq -r '.description' "$config_file")
    PIP_SIZE=$(jq -r '.pip_size' "$config_file")
    DECIMAL_PLACES=$(jq -r '.decimal_places' "$config_file")
    DEFAULT_PERCENTAGE=$(jq -r '.default_percentage' "$config_file")

    # Thresholds
    RSI_OVERBOUGHT=$(jq -r '.thresholds.rsi_overbought' "$config_file")
    RSI_OVERSOLD=$(jq -r '.thresholds.rsi_oversold' "$config_file")
    RSI_BUY_THRESHOLD=$(jq -r '.thresholds.rsi_buy_threshold' "$config_file")
    RSI_SELL_THRESHOLD=$(jq -r '.thresholds.rsi_sell_threshold' "$config_file")
    MIN_CONDITIONS=$(jq -r '.thresholds.min_conditions' "$config_file")
    FRESH_CROSS_LOOKBACK=$(jq -r '.thresholds.fresh_cross_lookback // 5' "$config_file")

    # Timeframes (ENV > JSON for workflow override)
    PRIMARY_TIMEFRAME="${PRIMARY_TIMEFRAME:-$(jq -r '.timeframes.primary' "$config_file")}"
    PRIMARY_RANGE="${PRIMARY_RANGE:-$(jq -r '.timeframes.primary_range' "$config_file")}"
    SECONDARY_TIMEFRAME="${SECONDARY_TIMEFRAME:-$(jq -r '.timeframes.secondary' "$config_file")}"
    SECONDARY_RANGE="${SECONDARY_RANGE:-$(jq -r '.timeframes.secondary_range' "$config_file")}"

    # SL/TP settings
    SL_TP_ENABLED=$(jq -r '.sl_tp.enabled // false' "$config_file")
    SL_MODE=$(jq -r '.sl_tp.stop_loss.mode // "atr"' "$config_file")
    SL_MULTIPLIER=$(jq -r '.sl_tp.stop_loss.multiplier // 1.5' "$config_file")
    TP_MODE=$(jq -r '.sl_tp.take_profit.mode // "ratio"' "$config_file")
    TP_VALUE=$(jq -r '.sl_tp.take_profit.value // 2.0' "$config_file")

    # Trading limits
    MAX_AMOUNT=$(jq -r '.max_amount // 10000' "$config_file")

    # Strategy (default: mean-reversion for backward compatibility)
    STRATEGY=$(jq -r '.strategy // "mean-reversion"' "$config_file")

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
