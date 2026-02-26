#!/bin/bash
# Auto Trade Script for USD/JPY
# Usage: auto-trade.sh [--dry-run]
# Executes full auto-trade flow without Claude Code Actions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE ===" >&2
fi

# Configuration
SYMBOL="USDJPY"
YAHOO_SYMBOL="USDJPY=X"
SAXO_UIC=42
PERCENTAGE=10

echo "========================================" >&2
echo "Auto Trade: $SYMBOL" >&2
echo "Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >&2
echo "========================================" >&2

# Step 1: Get price history from Yahoo Finance
echo "" >&2
echo "[Step 1] Fetching price history..." >&2
CHART_DATA=$("$SCRIPT_DIR/yahoo-finance/get-chart.sh" "$YAHOO_SYMBOL" 1h 10d 2>/dev/null)

if [[ -z "$CHART_DATA" ]]; then
    echo "Error: Failed to fetch chart data" >&2
    exit 1
fi

# Step 2: Calculate RSI
echo "[Step 2] Calculating RSI..." >&2
RSI_DATA=$(echo "$CHART_DATA" | "$SCRIPT_DIR/indicators/rsi.sh" 14 2>/dev/null)

RSI=$(echo "$RSI_DATA" | jq -r '.rsi')
RULE_SIGNAL=$(echo "$RSI_DATA" | jq -r '.tradeSignal')

echo "  RSI(14): $RSI" >&2
echo "  Rule Signal: $RULE_SIGNAL" >&2

# Step 3: Get real-time price from Saxo
echo "" >&2
echo "[Step 3] Fetching real-time price from Saxo..." >&2
ACCOUNT_INFO=$("$SCRIPT_DIR/saxo/get-accounts.sh" 2>&1) || {
    echo "Error: Failed to get account info" >&2
    echo "$ACCOUNT_INFO" >&2
    exit 1
}
ACCOUNT_KEY=$(echo "$ACCOUNT_INFO" | jq -r '.accountKey')

if [[ -z "$ACCOUNT_KEY" || "$ACCOUNT_KEY" == "null" ]]; then
    echo "Error: Could not extract accountKey" >&2
    echo "Account info: $ACCOUNT_INFO" >&2
    exit 1
fi

PRICE_DATA=$("$SCRIPT_DIR/saxo/get-prices.sh" "$ACCOUNT_KEY" "$SAXO_UIC" FxSpot 2>/dev/null)
BID=$(echo "$PRICE_DATA" | jq -r '.[0].bid')
ASK=$(echo "$PRICE_DATA" | jq -r '.[0].ask')

echo "  Bid: $BID / Ask: $ASK" >&2

# Step 4: Get balance and calculate trade amount
echo "" >&2
echo "[Step 4] Calculating trade amount..." >&2
BALANCE_DATA=$("$SCRIPT_DIR/saxo/get-balance.sh" "$PERCENTAGE" 2>/dev/null)
TRADE_AMOUNT_EUR=$(echo "$BALANCE_DATA" | jq -r '.tradeAmount')
CASH_BALANCE=$(echo "$BALANCE_DATA" | jq -r '.cashBalance')

# Convert EUR to USD amount (approximate)
# For USDJPY, we trade in USD units
TRADE_AMOUNT=$(echo "$TRADE_AMOUNT_EUR" | awk '{printf "%.0f", $1}')

echo "  Cash Balance: $CASH_BALANCE EUR" >&2
echo "  Trade Amount ($PERCENTAGE%): $TRADE_AMOUNT" >&2

# Step 5: AI Analysis (ChatGPT)
echo "" >&2
echo "[Step 5] Running AI analysis (ChatGPT)..." >&2
MARKET_DATA=$(jq -n \
    --arg symbol "$SYMBOL" \
    --argjson rsi "$RSI" \
    --argjson bid "$BID" \
    --argjson ask "$ASK" \
    --arg rule_signal "$RULE_SIGNAL" \
    '{symbol: $symbol, rsi: $rsi, bid: $bid, ask: $ask, rule_signal: $rule_signal}')

AI_RESULT=$(echo "$MARKET_DATA" | "$SCRIPT_DIR/ai/analyze-trade.sh" 2>/dev/null)

if [[ -z "$AI_RESULT" ]]; then
    echo "Warning: AI analysis failed, using rule-based only" >&2
    AI_DECISION="not_order"
    AI_TREND="unknown"
    AI_RISK="unknown"
    AI_COMMENT="AI analysis unavailable"
else
    AI_DECISION=$(echo "$AI_RESULT" | jq -r '.final_decision // "not_order"')
    AI_TREND=$(echo "$AI_RESULT" | jq -r '.trend // "unknown"')
    AI_RISK=$(echo "$AI_RESULT" | jq -r '.risk // "unknown"')
    AI_COMMENT=$(echo "$AI_RESULT" | jq -r '.comment // ""')
fi

echo "  AI Decision: $AI_DECISION" >&2
echo "  Trend: $AI_TREND" >&2
echo "  Risk: $AI_RISK" >&2

# Step 6: Final Decision
echo "" >&2
echo "[Step 6] Making final decision..." >&2

# Determine action based on rule signal
ACTION=""
if [[ "$RULE_SIGNAL" == "Buy" ]]; then
    ACTION="Buy"
elif [[ "$RULE_SIGNAL" == "Sell" ]]; then
    ACTION="Sell"
fi

# Final decision
FINAL_DECISION="not_order"
if [[ -n "$ACTION" && "$AI_DECISION" == "go" ]]; then
    FINAL_DECISION="go"
elif [[ -n "$ACTION" && "$AI_DECISION" != "go" ]]; then
    # AI overrode the rule signal
    echo "  AI override: Rule says $ACTION but AI says not_order" >&2
fi

echo "" >&2
echo "========================================" >&2
echo "FINAL DECISION: $FINAL_DECISION" >&2
if [[ "$FINAL_DECISION" == "go" ]]; then
    echo "ACTION: $ACTION $TRADE_AMOUNT units" >&2
fi
echo "========================================" >&2

# Step 7: Execute order if decision is "go"
if [[ "$FINAL_DECISION" == "go" && -n "$ACTION" ]]; then
    echo "" >&2
    echo "[Step 7] Executing order..." >&2

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would execute: $ACTION $TRADE_AMOUNT $SYMBOL" >&2
    else
        ORDER_RESULT=$("$SCRIPT_DIR/saxo/place-order.sh" "$ACCOUNT_KEY" "$SAXO_UIC" "$ACTION" "$TRADE_AMOUNT" Market "" FxSpot 2>&1)
        echo "$ORDER_RESULT" >&2
    fi
else
    echo "" >&2
    echo "[Step 7] No order executed (decision: $FINAL_DECISION)" >&2
fi

# Output final result as JSON
echo "" >&2
jq -n \
    --arg decision "$FINAL_DECISION" \
    --arg symbol "$SYMBOL" \
    --arg action "$ACTION" \
    --argjson amount "$TRADE_AMOUNT" \
    --argjson rsi "$RSI" \
    --arg rule_signal "$RULE_SIGNAL" \
    --arg ai_trend "$AI_TREND" \
    --arg ai_risk "$AI_RISK" \
    --arg ai_comment "$AI_COMMENT" \
    --argjson bid "$BID" \
    --argjson ask "$ASK" \
    '{
        decision: $decision,
        symbol: $symbol,
        action: (if $action == "" then null else $action end),
        amount: (if $decision == "go" then $amount else null end),
        rsi: $rsi,
        rule_signal: $rule_signal,
        ai_analysis: {
            trend: $ai_trend,
            risk: $ai_risk,
            comment: $ai_comment
        },
        price: {
            bid: $bid,
            ask: $ask
        }
    }'
