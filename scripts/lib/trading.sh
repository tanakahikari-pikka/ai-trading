#!/bin/bash
# Trading functions for Saxo Bank
# Usage: source lib/trading.sh

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$LIB_DIR/.."

# Calculate Stop Loss and Take Profit prices
# Usage: calculate_sl_tp <entry_price> <action> <atr> <sl_multiplier> <tp_ratio> <decimal_places>
# Returns: JSON with sl_price and tp_price
calculate_sl_tp() {
    local entry_price="$1"
    local action="$2"
    local atr="$3"
    local sl_multiplier="${4:-1.5}"
    local tp_ratio="${5:-2.0}"
    local decimal_places="${6:-3}"

    # Calculate SL distance based on ATR
    local sl_distance=$(echo "$atr * $sl_multiplier" | bc -l)
    local tp_distance=$(echo "$sl_distance * $tp_ratio" | bc -l)

    local sl_price tp_price

    if [[ "$action" == "Buy" ]]; then
        # Buy: SL below entry, TP above entry
        sl_price=$(echo "$entry_price - $sl_distance" | bc -l)
        tp_price=$(echo "$entry_price + $tp_distance" | bc -l)
    else
        # Sell: SL above entry, TP below entry
        sl_price=$(echo "$entry_price + $sl_distance" | bc -l)
        tp_price=$(echo "$entry_price - $tp_distance" | bc -l)
    fi

    # Format to specified decimal places
    sl_price=$(printf "%.${decimal_places}f" "$sl_price")
    tp_price=$(printf "%.${decimal_places}f" "$tp_price")

    jq -n \
        --argjson sl_price "$sl_price" \
        --argjson tp_price "$tp_price" \
        --argjson sl_distance "$sl_distance" \
        --argjson tp_distance "$tp_distance" \
        '{
            sl_price: $sl_price,
            tp_price: $tp_price,
            sl_distance: $sl_distance,
            tp_distance: $tp_distance
        }'
}

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
# Usage: place_order <account_key> <uic> <action> <amount> <asset_type> [sl_price] [tp_price]
place_order() {
    local account_key="$1"
    local uic="$2"
    local action="$3"
    local amount="$4"
    local asset_type="${5:-FxSpot}"
    local sl_price="${6:-}"
    local tp_price="${7:-}"

    "$SCRIPTS_ROOT/saxo/place-order.sh" "$account_key" "$uic" "$action" "$amount" Market "" "$asset_type" "$sl_price" "$tp_price" 2>&1
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
