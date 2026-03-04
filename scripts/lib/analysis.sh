#!/bin/bash
# Common analysis functions
# Usage: source lib/analysis.sh

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$LIB_DIR/.."

# Fetch price data from Yahoo Finance
# Usage: fetch_price_data <yahoo_symbol> <interval> <range>
fetch_price_data() {
    local yahoo_symbol="$1"
    local interval="$2"
    local range="$3"

    "$SCRIPTS_ROOT/yahoo-finance/get-chart.sh" "$yahoo_symbol" "$interval" "$range" 2>/dev/null
}

# Run technical analysis on price data
# Usage: echo "$PRICE_DATA" | run_technical_analysis [strategy]
# If strategy is not provided, uses $STRATEGY variable or defaults to mean-reversion
run_technical_analysis() {
    local strategy="${1:-${STRATEGY:-mean-reversion}}"
    local strategy_script="$SCRIPTS_ROOT/strategies/$strategy/analyze.sh"

    # Use strategy-specific script if available
    if [[ -f "$strategy_script" ]]; then
        "$strategy_script" 2>/dev/null
    else
        # Fallback to legacy indicators/analyze.sh
        "$SCRIPTS_ROOT/indicators/analyze.sh" 2>/dev/null
    fi
}

# Run AI analysis
# Usage: echo "$MARKET_DATA" | run_ai_analysis
run_ai_analysis() {
    "$SCRIPTS_ROOT/ai/analyze-trade.sh" 2>/dev/null
}

# Build market data JSON for AI
# Usage: build_market_data <symbol> <bid> <ask> <analysis_1h> <analysis_4h> <recent_1h> <recent_4h> <rule_signal> <trend_1h> <trend_4h>
build_market_data() {
    local symbol="$1"
    local bid="$2"
    local ask="$3"
    local analysis_1h="$4"
    local analysis_4h="$5"
    local recent_1h="$6"
    local recent_4h="$7"
    local rule_signal="$8"
    local trend_1h="$9"
    local trend_4h="${10}"

    jq -n \
        --arg symbol "$symbol" \
        --argjson bid "$bid" \
        --argjson ask "$ask" \
        --argjson analysis_1h "$analysis_1h" \
        --argjson analysis_4h "$analysis_4h" \
        --argjson recent_prices_1h "$recent_1h" \
        --argjson recent_prices_4h "$recent_4h" \
        --arg rule_signal "$rule_signal" \
        --arg trend_1h "$trend_1h" \
        --arg trend_4h "$trend_4h" \
        '{
            symbol: $symbol,
            current_price: { bid: $bid, ask: $ask },
            timeframes: {
                "1h": {
                    indicators: $analysis_1h.indicators,
                    rule_analysis: $analysis_1h.rule_analysis,
                    recent_prices: $recent_prices_1h
                },
                "4h": {
                    indicators: $analysis_4h.indicators,
                    rule_analysis: $analysis_4h.rule_analysis,
                    recent_prices: $recent_prices_4h
                }
            },
            summary: {
                rule_signal: $rule_signal,
                trend_1h: $trend_1h,
                trend_4h: $trend_4h
            }
        }'
}

# Extract analysis results
# Usage: extract_analysis_results <analysis_json>
extract_rsi() { echo "$1" | jq -r '.indicators.rsi_14'; }
extract_signal() { echo "$1" | jq -r '.rule_analysis.signal'; }
extract_trend() { echo "$1" | jq -r '.rule_analysis.trend'; }
extract_buy_conditions() { echo "$1" | jq -r '.rule_analysis.buy_conditions_met'; }
extract_sell_conditions() { echo "$1" | jq -r '.rule_analysis.sell_conditions_met'; }
extract_volatility() { echo "$1" | jq -r '.indicators.atr.volatility'; }
extract_atr() { echo "$1" | jq -r '.indicators.atr.value // .indicators.atr_14 // 0'; }
extract_sma20() { echo "$1" | jq -r '.indicators.sma_20 // 0'; }
extract_sma50() { echo "$1" | jq -r '.indicators.sma_50 // 0'; }
