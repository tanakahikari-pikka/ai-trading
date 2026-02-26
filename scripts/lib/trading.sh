#!/bin/bash
# Trading functions for Saxo Bank
# Usage: source lib/trading.sh

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$LIB_DIR/.."

# Get Saxo account info
# Returns: JSON with accountKey
get_saxo_account() {
    "$SCRIPTS_ROOT/saxo/get-accounts.sh" 2>&1
}

# Extract account key from account output
extract_account_key() {
    local account_output="$1"
    echo "$account_output" | awk '/^{/,/^}/' | jq -r '.accountKey' 2>/dev/null
}

# Get real-time price from Saxo
# Usage: get_saxo_price <account_key> <uic> <asset_type>
get_saxo_price() {
    local account_key="$1"
    local uic="$2"
    local asset_type="$3"

    "$SCRIPTS_ROOT/saxo/get-prices.sh" "$account_key" "$uic" "$asset_type" 2>/dev/null
}

# Get balance info
# Usage: get_balance <percentage>
get_balance() {
    local percentage="$1"
    "$SCRIPTS_ROOT/saxo/get-balance.sh" "$percentage" 2>/dev/null
}

# Place order
# Usage: place_order <account_key> <uic> <action> <amount> <asset_type>
place_order() {
    local account_key="$1"
    local uic="$2"
    local action="$3"
    local amount="$4"
    local asset_type="${5:-FxSpot}"

    "$SCRIPTS_ROOT/saxo/place-order.sh" "$account_key" "$uic" "$action" "$amount" Market "" "$asset_type" 2>&1
}

# Determine final decision
# Usage: determine_decision <rule_signal> <ai_decision>
# Returns: "go" or "not_order"
determine_decision() {
    local rule_signal="$1"
    local ai_decision="$2"

    local action=""
    if [[ "$rule_signal" == "Buy" ]]; then
        action="Buy"
    elif [[ "$rule_signal" == "Sell" ]]; then
        action="Sell"
    fi

    if [[ -n "$action" && "$ai_decision" == "go" ]]; then
        echo "go"
    else
        echo "not_order"
    fi
}

# Build final result JSON
build_final_result() {
    local decision="$1"
    local symbol="$2"
    local action="$3"
    local amount="$4"
    local rsi="$5"
    local rule_signal="$6"
    local buy_conditions="$7"
    local sell_conditions="$8"
    local trend_1h="$9"
    local trend_4h="${10}"
    local volatility="${11}"
    local ai_decision="${12}"
    local ai_confidence="${13}"
    local ai_summary="${14}"
    local ai_risk="${15}"
    local ai_recommendation="${16}"
    local ai_learning_topic="${17}"
    local ai_learning_example="${18}"
    local ai_wait_for="${19}"
    local bid="${20}"
    local ask="${21}"
    local ai_full="${22}"

    jq -n \
        --arg decision "$decision" \
        --arg symbol "$symbol" \
        --arg action "$action" \
        --argjson amount "$amount" \
        --argjson rsi "$rsi" \
        --arg rule_signal "$rule_signal" \
        --argjson buy_conditions "$buy_conditions" \
        --argjson sell_conditions "$sell_conditions" \
        --arg trend_1h "$trend_1h" \
        --arg trend_4h "$trend_4h" \
        --arg volatility "$volatility" \
        --arg ai_decision "$ai_decision" \
        --argjson ai_confidence "$ai_confidence" \
        --arg ai_summary "$ai_summary" \
        --arg ai_risk "$ai_risk" \
        --arg ai_recommendation "$ai_recommendation" \
        --arg ai_learning_topic "$ai_learning_topic" \
        --arg ai_learning_example "$ai_learning_example" \
        --argjson ai_wait_for "$ai_wait_for" \
        --argjson bid "$bid" \
        --argjson ask "$ask" \
        --argjson ai_full "$ai_full" \
        '{
            decision: $decision,
            symbol: $symbol,
            action: (if $action == "" then null else $action end),
            amount: (if $decision == "go" then $amount else null end),
            analysis: {
                rsi: $rsi,
                rule_signal: $rule_signal,
                buy_conditions: $buy_conditions,
                sell_conditions: $sell_conditions,
                trend_1h: $trend_1h,
                trend_4h: $trend_4h,
                volatility: $volatility
            },
            ai_analysis: {
                decision: $ai_decision,
                confidence: $ai_confidence,
                summary: $ai_summary,
                risk: $ai_risk,
                recommendation: $ai_recommendation
            },
            learning: {
                topic: $ai_learning_topic,
                example: $ai_learning_example
            },
            next_actions: $ai_wait_for,
            price: {
                bid: $bid,
                ask: $ask
            },
            ai_full_response: $ai_full
        }'
}
