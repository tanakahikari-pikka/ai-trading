#!/bin/bash
# Auto Trade Script - Multi-Currency Support
# Usage: auto-trade.sh <SYMBOL> [--dry-run]
# Examples:
#   auto-trade.sh USDJPY
#   auto-trade.sh EURUSD --dry-run
#   auto-trade.sh XAUUSD

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/analysis.sh"
source "$SCRIPT_DIR/lib/trading.sh"

# Parse arguments
CURRENCY=""
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --list)
            list_available_currencies
            exit 0
            ;;
        --help|-h)
            echo "Usage: auto-trade.sh <SYMBOL> [--dry-run]"
            echo ""
            echo "Arguments:"
            echo "  SYMBOL     Currency pair (e.g., USDJPY, EURUSD, XAUUSD)"
            echo "  --dry-run  Run without executing orders"
            echo "  --list     List available currencies"
            echo ""
            list_available_currencies
            exit 0
            ;;
        *)
            if [[ -z "$CURRENCY" ]]; then
                CURRENCY="$arg"
            fi
            ;;
    esac
done

# Validate currency
if [[ -z "$CURRENCY" ]]; then
    echo "Error: Currency symbol is required" >&2
    echo "Usage: auto-trade.sh <SYMBOL> [--dry-run]" >&2
    echo "" >&2
    list_available_currencies >&2
    exit 1
fi

# Load currency configuration
if ! load_currency_config "$CURRENCY"; then
    exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "=== DRY RUN MODE ===" >&2
fi

echo "========================================" >&2
echo "Auto Trade: $DISPLAY_NAME ($DESCRIPTION)" >&2
echo "Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >&2
echo "========================================" >&2

# Step 1: Get price history from Yahoo Finance (Multi-timeframe)
echo "" >&2
echo "[Step 1] Fetching price history (Multi-timeframe)..." >&2

# Primary timeframe data
CHART_DATA_1H=$(fetch_price_data "$YAHOO_SYMBOL" "$PRIMARY_TIMEFRAME" "$PRIMARY_RANGE")
if [[ -z "$CHART_DATA_1H" ]]; then
    echo "Error: Failed to fetch $PRIMARY_TIMEFRAME chart data" >&2
    exit 1
fi
echo "  $PRIMARY_TIMEFRAME data: OK" >&2

# Secondary timeframe data
CHART_DATA_4H=$(fetch_price_data "$YAHOO_SYMBOL" "$SECONDARY_TIMEFRAME" "$SECONDARY_RANGE")
if [[ -z "$CHART_DATA_4H" ]]; then
    echo "Warning: Failed to fetch $SECONDARY_TIMEFRAME chart data, using primary only" >&2
    CHART_DATA_4H="$CHART_DATA_1H"
fi
echo "  $SECONDARY_TIMEFRAME data: OK" >&2

# Step 2: Technical Analysis (All indicators)
echo "" >&2
echo "[Step 2] Running technical analysis..." >&2

# Analyze primary timeframe
echo "  Analyzing $PRIMARY_TIMEFRAME timeframe..." >&2
ANALYSIS_1H=$(echo "$CHART_DATA_1H" | run_technical_analysis)

# Analyze secondary timeframe
echo "  Analyzing $SECONDARY_TIMEFRAME timeframe..." >&2
ANALYSIS_4H=$(echo "$CHART_DATA_4H" | run_technical_analysis)

# Extract key values
RSI=$(extract_rsi "$ANALYSIS_1H")
RULE_SIGNAL=$(extract_signal "$ANALYSIS_1H")
TREND_1H=$(extract_trend "$ANALYSIS_1H")
TREND_4H=$(extract_trend "$ANALYSIS_4H")
BUY_CONDITIONS=$(extract_buy_conditions "$ANALYSIS_1H")
SELL_CONDITIONS=$(extract_sell_conditions "$ANALYSIS_1H")
VOLATILITY=$(extract_volatility "$ANALYSIS_1H")
ATR_VALUE=$(extract_atr "$ANALYSIS_1H")

echo "" >&2
echo "  === $PRIMARY_TIMEFRAME Analysis ===" >&2
echo "  RSI(14): $RSI" >&2
echo "  Signal: $RULE_SIGNAL" >&2
echo "  Trend: $TREND_1H" >&2
echo "  Buy conditions: $BUY_CONDITIONS/4" >&2
echo "  Sell conditions: $SELL_CONDITIONS/4" >&2
echo "  Volatility: $VOLATILITY" >&2
echo "  ATR(14): $ATR_VALUE" >&2
echo "" >&2
echo "  === $SECONDARY_TIMEFRAME Analysis ===" >&2
echo "  Trend: $TREND_4H" >&2

# Step 3: Get real-time price from Saxo
echo "" >&2
echo "[Step 3] Fetching real-time price from Saxo..." >&2

# Load .env if exists
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Check token
if [[ -z "$SAXO_ACCESS_TOKEN" || "$SAXO_ACCESS_TOKEN" == "your_access_token_here" ]]; then
    echo "Error: SAXO_ACCESS_TOKEN is not configured" >&2
    exit 1
fi

echo "  Token configured: yes (${#SAXO_ACCESS_TOKEN} chars)" >&2

# Get account info
ACCOUNT_OUTPUT=$(get_saxo_account)
ACCOUNT_EXIT_CODE=$?

if [[ $ACCOUNT_EXIT_CODE -ne 0 ]]; then
    echo "Error: get-accounts.sh failed" >&2
    echo "$ACCOUNT_OUTPUT" >&2
    exit 1
fi

ACCOUNT_KEY=$(extract_account_key "$ACCOUNT_OUTPUT")

if [[ -z "$ACCOUNT_KEY" || "$ACCOUNT_KEY" == "null" ]]; then
    echo "Error: Could not extract accountKey" >&2
    exit 1
fi

PRICE_DATA=$(get_saxo_price "$ACCOUNT_KEY" "$SAXO_UIC" "$SAXO_ASSET_TYPE")
BID=$(echo "$PRICE_DATA" | jq -r '.[0].bid // 0')
ASK=$(echo "$PRICE_DATA" | jq -r '.[0].ask // 0')

echo "  Bid: $BID / Ask: $ASK" >&2

# Step 4: Get balance and calculate trade amount
echo "" >&2
echo "[Step 4] Calculating trade amount..." >&2
BALANCE_DATA=$(get_balance "$DEFAULT_PERCENTAGE")
TRADE_AMOUNT_EUR=$(echo "$BALANCE_DATA" | jq -r '.tradeAmount')
CASH_BALANCE=$(echo "$BALANCE_DATA" | jq -r '.cashBalance')

# Convert to trade amount
TRADE_AMOUNT=$(echo "$TRADE_AMOUNT_EUR" | awk '{printf "%.0f", $1}')

echo "  Cash Balance: $CASH_BALANCE EUR" >&2
echo "  Trade Amount ($DEFAULT_PERCENTAGE%): $TRADE_AMOUNT" >&2

# Step 5: AI Analysis with comprehensive data
echo "" >&2
echo "[Step 5] Running AI analysis (Educational Mode)..." >&2

# Get recent prices for context
RECENT_CLOSES_1H=$(echo "$CHART_DATA_1H" | jq '.close[-24:]')
RECENT_CLOSES_4H=$(echo "$CHART_DATA_4H" | jq '.close[-12:]')

# Build comprehensive market data for AI
MARKET_DATA=$(build_market_data "$SYMBOL" "$BID" "$ASK" "$ANALYSIS_1H" "$ANALYSIS_4H" "$RECENT_CLOSES_1H" "$RECENT_CLOSES_4H" "$RULE_SIGNAL" "$TREND_1H" "$TREND_4H")

AI_RESULT=$(echo "$MARKET_DATA" | run_ai_analysis)

if [[ -z "$AI_RESULT" ]]; then
    echo "Warning: AI analysis failed, using rule-based only" >&2
    AI_DECISION="not_order"
    AI_DIRECTION=""
    AI_CONFIDENCE=0
    AI_SUMMARY="AI analysis unavailable"
    AI_RISK="unknown"
    AI_LEARNING_TOPIC=""
    AI_LEARNING_EXAMPLE=""
    AI_RECOMMENDATION="様子見"
    AI_WAIT_FOR="[]"
else
    # Extract from new educational format
    AI_DECISION=$(echo "$AI_RESULT" | jq -r '.decision.action // "not_order"')
    AI_DIRECTION=$(echo "$AI_RESULT" | jq -r '.decision.direction // ""')
    AI_CONFIDENCE=$(echo "$AI_RESULT" | jq -r '.decision.confidence // 0')
    AI_SUMMARY=$(echo "$AI_RESULT" | jq -r '.decision.summary // ""')
    AI_RISK=$(echo "$AI_RESULT" | jq -r '.analysis.risk_assessment.level // "unknown"')
    AI_LEARNING_TOPIC=$(echo "$AI_RESULT" | jq -r '.learning.today_topic // ""')
    AI_LEARNING_EXAMPLE=$(echo "$AI_RESULT" | jq -r '.learning.today_example // ""')
    AI_RECOMMENDATION=$(echo "$AI_RESULT" | jq -r '.action_guide.recommendation // "様子見"')
    AI_WAIT_FOR=$(echo "$AI_RESULT" | jq -c '.action_guide.wait_for // []')
fi

echo "  AI Decision: $AI_DECISION (confidence: $AI_CONFIDENCE%)" >&2
echo "  Summary: $AI_SUMMARY" >&2
echo "  Risk: $AI_RISK" >&2
echo "  Recommendation: $AI_RECOMMENDATION" >&2

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
FINAL_DECISION=$(determine_decision "$RULE_SIGNAL" "$AI_DECISION")

if [[ -n "$ACTION" && "$AI_DECISION" != "go" ]]; then
    echo "  AI override: Rule says $ACTION but AI says not_order" >&2
fi

echo "" >&2
echo "========================================" >&2
echo "FINAL DECISION: $FINAL_DECISION" >&2
if [[ "$FINAL_DECISION" == "go" ]]; then
    echo "ACTION: $ACTION $TRADE_AMOUNT units of $DISPLAY_NAME" >&2
fi
echo "========================================" >&2

# Step 7: Calculate SL/TP if enabled
SL_PRICE=""
TP_PRICE=""
SL_TP_SOURCE=""
AI_SL_TP_REASONING=""

if [[ "$FINAL_DECISION" == "go" && -n "$ACTION" && "$SL_TP_ENABLED" == "true" ]]; then
    echo "" >&2
    echo "[Step 7] Calculating SL/TP..." >&2

    # Determine entry price based on action
    if [[ "$ACTION" == "Buy" ]]; then
        ENTRY_PRICE="$ASK"
    else
        ENTRY_PRICE="$BID"
    fi

    # Try to get AI-suggested SL/TP first
    AI_SL_RAW=$(echo "$AI_RESULT" | jq -r '.sl_tp.stop_loss // "null"' 2>/dev/null)
    AI_TP_RAW=$(echo "$AI_RESULT" | jq -r '.sl_tp.take_profit // "null"' 2>/dev/null)
    AI_SL_TP_REASONING=$(echo "$AI_RESULT" | jq -r '.sl_tp.reasoning // ""' 2>/dev/null)

    echo "  Entry Price: $ENTRY_PRICE" >&2
    echo "  AI SL/TP: SL=$AI_SL_RAW, TP=$AI_TP_RAW" >&2

    # Validate AI SL/TP values
    USE_AI_SLTP=false
    if [[ "$AI_SL_RAW" != "null" && "$AI_TP_RAW" != "null" && -n "$AI_SL_RAW" && -n "$AI_TP_RAW" ]]; then
        # Check if values are valid numbers
        if [[ "$AI_SL_RAW" =~ ^[0-9]+\.?[0-9]*$ && "$AI_TP_RAW" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            # Validate SL/TP positions based on action
            if [[ "$ACTION" == "Buy" ]]; then
                # For Buy: SL should be below entry, TP should be above entry
                SL_VALID=$(echo "$AI_SL_RAW < $ENTRY_PRICE" | bc -l)
                TP_VALID=$(echo "$AI_TP_RAW > $ENTRY_PRICE" | bc -l)
            else
                # For Sell: SL should be above entry, TP should be below entry
                SL_VALID=$(echo "$AI_SL_RAW > $ENTRY_PRICE" | bc -l)
                TP_VALID=$(echo "$AI_TP_RAW < $ENTRY_PRICE" | bc -l)
            fi

            if [[ "$SL_VALID" == "1" && "$TP_VALID" == "1" ]]; then
                USE_AI_SLTP=true
                echo "  AI SL/TP validation: PASSED" >&2
            else
                echo "  AI SL/TP validation: FAILED (invalid positions)" >&2
                echo "    SL_VALID=$SL_VALID, TP_VALID=$TP_VALID" >&2
            fi
        else
            echo "  AI SL/TP validation: FAILED (not numeric)" >&2
        fi
    else
        echo "  AI SL/TP: not provided" >&2
    fi

    # Use AI values or fallback to static calculation
    if [[ "$USE_AI_SLTP" == "true" ]]; then
        SL_PRICE="$AI_SL_RAW"
        TP_PRICE="$AI_TP_RAW"
        SL_TP_SOURCE="ai"
        echo "" >&2
        echo "  [Using AI SL/TP]" >&2
        echo "  Stop Loss: $SL_PRICE" >&2
        echo "  Take Profit: $TP_PRICE" >&2
        echo "  Reasoning: $AI_SL_TP_REASONING" >&2
    else
        # Fallback to static ATR-based calculation
        echo "" >&2
        echo "  [Fallback to static calculation]" >&2
        SL_TP_RESULT=$(calculate_sl_tp "$ENTRY_PRICE" "$ACTION" "$ATR_VALUE" "$SL_MULTIPLIER" "$TP_VALUE" "$DECIMAL_PLACES")
        SL_PRICE=$(echo "$SL_TP_RESULT" | jq -r '.sl_price')
        TP_PRICE=$(echo "$SL_TP_RESULT" | jq -r '.tp_price')
        SL_DISTANCE=$(echo "$SL_TP_RESULT" | jq -r '.sl_distance')
        TP_DISTANCE=$(echo "$SL_TP_RESULT" | jq -r '.tp_distance')
        SL_TP_SOURCE="static"

        echo "  Stop Loss: $SL_PRICE (ATR×$SL_MULTIPLIER = $SL_DISTANCE)" >&2
        echo "  Take Profit: $TP_PRICE (SL×$TP_VALUE = $TP_DISTANCE)" >&2
    fi

    echo "  Source: $SL_TP_SOURCE" >&2
fi

# Step 8: Execute order if decision is "go"
if [[ "$FINAL_DECISION" == "go" && -n "$ACTION" ]]; then
    echo "" >&2
    echo "[Step 8] Executing order..." >&2

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would execute: $ACTION $TRADE_AMOUNT $DISPLAY_NAME" >&2
        if [[ -n "$SL_PRICE" ]]; then
            echo "  [DRY RUN] With SL: $SL_PRICE / TP: $TP_PRICE" >&2
        fi
    else
        ORDER_RESULT=$(place_order "$ACCOUNT_KEY" "$SAXO_UIC" "$ACTION" "$TRADE_AMOUNT" "$SAXO_ASSET_TYPE" "$SL_PRICE" "$TP_PRICE")
        echo "$ORDER_RESULT" >&2
    fi
else
    echo "" >&2
    echo "[Step 8] No order executed (decision: $FINAL_DECISION)" >&2
fi

# Output final result as JSON
echo "" >&2

# Handle SL/TP for JSON output
SL_PRICE_JSON="${SL_PRICE:-null}"
TP_PRICE_JSON="${TP_PRICE:-null}"
if [[ "$SL_PRICE_JSON" != "null" ]]; then
    SL_PRICE_JSON="$SL_PRICE"
fi
if [[ "$TP_PRICE_JSON" != "null" ]]; then
    TP_PRICE_JSON="$TP_PRICE"
fi

FINAL_RESULT=$(jq -n \
    --arg decision "$FINAL_DECISION" \
    --arg symbol "$SYMBOL" \
    --arg display_name "$DISPLAY_NAME" \
    --arg action "$ACTION" \
    --argjson amount "$TRADE_AMOUNT" \
    --argjson rsi "$RSI" \
    --arg rule_signal "$RULE_SIGNAL" \
    --argjson buy_conditions "$BUY_CONDITIONS" \
    --argjson sell_conditions "$SELL_CONDITIONS" \
    --arg trend_1h "$TREND_1H" \
    --arg trend_4h "$TREND_4H" \
    --arg volatility "$VOLATILITY" \
    --argjson atr "$ATR_VALUE" \
    --arg ai_decision "$AI_DECISION" \
    --argjson ai_confidence "$AI_CONFIDENCE" \
    --arg ai_summary "$AI_SUMMARY" \
    --arg ai_risk "$AI_RISK" \
    --arg ai_recommendation "$AI_RECOMMENDATION" \
    --arg ai_learning_topic "$AI_LEARNING_TOPIC" \
    --arg ai_learning_example "$AI_LEARNING_EXAMPLE" \
    --argjson ai_wait_for "$AI_WAIT_FOR" \
    --argjson bid "$BID" \
    --argjson ask "$ASK" \
    --arg sl_price "$SL_PRICE" \
    --arg tp_price "$TP_PRICE" \
    --arg sl_tp_enabled "$SL_TP_ENABLED" \
    --arg sl_tp_source "$SL_TP_SOURCE" \
    --arg sl_tp_reasoning "$AI_SL_TP_REASONING" \
    --argjson ai_full "$AI_RESULT" \
    '{
        decision: $decision,
        symbol: $symbol,
        display_name: $display_name,
        action: (if $action == "" then null else $action end),
        amount: (if $decision == "go" then $amount else null end),
        analysis: {
            rsi: $rsi,
            rule_signal: $rule_signal,
            buy_conditions: $buy_conditions,
            sell_conditions: $sell_conditions,
            trend_1h: $trend_1h,
            trend_4h: $trend_4h,
            volatility: $volatility,
            atr: $atr
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
        sl_tp: {
            enabled: ($sl_tp_enabled == "true"),
            stop_loss: (if $sl_price == "" then null else ($sl_price | tonumber) end),
            take_profit: (if $tp_price == "" then null else ($tp_price | tonumber) end),
            source: (if $sl_tp_source == "" then null else $sl_tp_source end),
            reasoning: (if $sl_tp_reasoning == "" then null else $sl_tp_reasoning end)
        },
        ai_full_response: $ai_full
    }')

echo "$FINAL_RESULT"

# Step 9: Send Discord notification
echo "" >&2
echo "[Step 9] Sending Discord notification..." >&2
if [[ -f "$SCRIPT_DIR/notify/discord.sh" ]]; then
    echo "$FINAL_RESULT" | "$SCRIPT_DIR/notify/discord.sh"
else
    echo "  Discord notification script not found, skipping" >&2
fi
