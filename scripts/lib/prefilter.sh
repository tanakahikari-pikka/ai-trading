#!/bin/bash
# Pre-filter logic for AI analysis
# Determines whether to skip AI analysis based on market conditions

# Check if AI analysis should be skipped
# Arguments:
#   $1 - RULE_SIGNAL (Buy/Sell/Wait)
#   $2 - VOLATILITY (low/medium/high)
#   $3 - BUY_CONDITIONS (0-3)
#   $4 - SELL_CONDITIONS (0-3)
# Returns:
#   JSON with skip decision and reason
check_prefilter() {
    local rule_signal="$1"
    local volatility="$2"
    local buy_conditions="$3"
    local sell_conditions="$4"

    local skip="false"
    local reason=""

    # Skip only if BOTH buy and sell conditions are below threshold
    if [[ "$buy_conditions" -lt 2 && "$sell_conditions" -lt 2 ]]; then
        skip="true"
        reason="No clear signal (Buy: ${buy_conditions}/3, Sell: ${sell_conditions}/3)"
    elif [[ "$volatility" == "low" ]]; then
        skip="true"
        reason="Low volatility - insufficient price movement"
    fi

    jq -n \
        --argjson skip "$skip" \
        --arg reason "$reason" \
        '{skip: $skip, reason: $reason}'
}
