#!/bin/bash
# Pre-filter logic for AI analysis
# Determines whether to skip AI analysis based on market conditions

# Check if AI analysis should be skipped
# Arguments:
#   $1 - RULE_SIGNAL (Buy/Sell/Wait)
#   $2 - VOLATILITY (low/medium/high)
#   $3 - BUY_CONDITIONS (0-4)
#   $4 - SELL_CONDITIONS (0-4)
# Returns:
#   JSON with skip decision and reason
check_prefilter() {
    local rule_signal="$1"
    local volatility="$2"
    local buy_conditions="$3"
    local sell_conditions="$4"

    local skip="false"
    local reason=""

    if [[ "$rule_signal" == "Wait" ]]; then
        skip="true"
        reason="No clear signal (Buy: ${buy_conditions}/4, Sell: ${sell_conditions}/4)"
    elif [[ "$volatility" == "low" ]]; then
        skip="true"
        reason="Low volatility - insufficient price movement"
    fi

    jq -n \
        --argjson skip "$skip" \
        --arg reason "$reason" \
        '{skip: $skip, reason: $reason}'
}
