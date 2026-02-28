#!/bin/bash
# Comprehensive Technical Analysis
# Usage: analyze.sh < price_data.json
#
# Input: JSON with OHLC data from get-chart.sh
# Output: JSON with all indicators and rule-based signal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read input from stdin and save to temp file for multiple reads
INPUT=$(cat)
TEMP_FILE=$(mktemp)
echo "$INPUT" > "$TEMP_FILE"

# Validate input
if [[ -z "$INPUT" ]]; then
    echo "Error: No input data" >&2
    rm -f "$TEMP_FILE"
    exit 1
fi

# Get current price
CURRENT_PRICE=$(echo "$INPUT" | jq -r '[.close[] | select(. != null)] | last // 0')

echo "=== Technical Analysis ===" >&2
echo "Current Price: $CURRENT_PRICE" >&2
echo "" >&2

# Calculate all indicators
RSI_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/rsi.sh" 14 2>/dev/null || echo '{"rsi":50}')
SMA20_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/sma.sh" 20 2>/dev/null || echo '{"sma":0}')
SMA50_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/sma.sh" 50 2>/dev/null || echo '{"sma":0}')
EMA12_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/ema.sh" 12 2>/dev/null || echo '{"ema":0}')
EMA26_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/ema.sh" 26 2>/dev/null || echo '{"ema":0}')
MACD_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/macd.sh" 12 26 9 2>/dev/null || echo '{"macd":0,"signal":0,"histogram":0}')
BB_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/bollinger.sh" 20 2 2>/dev/null || echo '{"upper":0,"middle":0,"lower":0,"position":"unknown"}')
ATR_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/atr.sh" 14 2>/dev/null || echo '{"atr":0,"atr_percent":0,"volatility":"unknown"}')

rm -f "$TEMP_FILE"

# Extract values with defaults
RSI=$(echo "$RSI_DATA" | jq -r '.rsi // 50')
SMA20=$(echo "$SMA20_DATA" | jq -r '.sma // 0')
SMA50=$(echo "$SMA50_DATA" | jq -r '.sma // 0')
EMA12=$(echo "$EMA12_DATA" | jq -r '.ema // 0')
EMA26=$(echo "$EMA26_DATA" | jq -r '.ema // 0')
MACD=$(echo "$MACD_DATA" | jq -r '.macd // 0')
MACD_SIGNAL=$(echo "$MACD_DATA" | jq -r '.signal // 0')
MACD_HISTOGRAM=$(echo "$MACD_DATA" | jq -r '.histogram // 0')
BB_UPPER=$(echo "$BB_DATA" | jq -r '.upper // 0')
BB_MIDDLE=$(echo "$BB_DATA" | jq -r '.middle // 0')
BB_LOWER=$(echo "$BB_DATA" | jq -r '.lower // 0')
BB_POSITION=$(echo "$BB_DATA" | jq -r '.position // "unknown"')
ATR=$(echo "$ATR_DATA" | jq -r '.atr // 0')
ATR_PCT=$(echo "$ATR_DATA" | jq -r '.atr_percent // 0')
VOLATILITY=$(echo "$ATR_DATA" | jq -r '.volatility // "unknown"')

# Ensure numeric values
RSI=${RSI:-50}
SMA20=${SMA20:-0}
SMA50=${SMA50:-0}
MACD=${MACD:-0}
MACD_SIGNAL=${MACD_SIGNAL:-0}
BB_MIDDLE=${BB_MIDDLE:-0}

# Calculate BB band thresholds (30% into the band from lower/upper)
BB_BUY_THRESHOLD=$(echo "$BB_LOWER + ($BB_MIDDLE - $BB_LOWER) * 0.3" | bc -l 2>/dev/null || echo 0)
BB_SELL_THRESHOLD=$(echo "$BB_UPPER - ($BB_UPPER - $BB_MIDDLE) * 0.3" | bc -l 2>/dev/null || echo 0)

# Determine SMA trend alignment (MTF filter)
SMA_TREND_UP=$(echo "$SMA20 > $SMA50" | bc -l 2>/dev/null || echo 0)
SMA_TREND_DOWN=$(echo "$SMA20 < $SMA50" | bc -l 2>/dev/null || echo 0)

# Rule-based analysis (2/4 conditions for signal)
# Buy conditions
BUY_RSI=$(echo "$RSI < 40" | bc -l 2>/dev/null || echo 0)
BUY_SMA=$(echo "$CURRENT_PRICE > $SMA20" | bc -l 2>/dev/null || echo 0)
BUY_MACD=$(echo "$MACD > $MACD_SIGNAL" | bc -l 2>/dev/null || echo 0)
BUY_BB=$(echo "$CURRENT_PRICE < $BB_BUY_THRESHOLD" | bc -l 2>/dev/null || echo 0)
BUY_COUNT=$((BUY_RSI + BUY_SMA + BUY_MACD + BUY_BB))

# Sell conditions
SELL_RSI=$(echo "$RSI > 60" | bc -l 2>/dev/null || echo 0)
SELL_SMA=$(echo "$CURRENT_PRICE < $SMA20" | bc -l 2>/dev/null || echo 0)
SELL_MACD=$(echo "$MACD < $MACD_SIGNAL" | bc -l 2>/dev/null || echo 0)
SELL_BB=$(echo "$CURRENT_PRICE > $BB_SELL_THRESHOLD" | bc -l 2>/dev/null || echo 0)
SELL_COUNT=$((SELL_RSI + SELL_SMA + SELL_MACD + SELL_BB))

# Determine signal (2/4 threshold + MTF alignment)
SIGNAL="Wait"
if [[ $BUY_COUNT -ge 2 && $BUY_COUNT -gt $SELL_COUNT ]]; then
    # Buy only allowed when SMA20 > SMA50 (uptrend)
    if [[ $SMA_TREND_UP -eq 1 ]]; then
        SIGNAL="Buy"
    else
        SIGNAL="Wait"
        echo "  [MTF Filter] Buy blocked: SMA20 < SMA50 (downtrend)" >&2
    fi
elif [[ $SELL_COUNT -ge 2 && $SELL_COUNT -gt $BUY_COUNT ]]; then
    # Sell only allowed when SMA20 < SMA50 (downtrend)
    if [[ $SMA_TREND_DOWN -eq 1 ]]; then
        SIGNAL="Sell"
    else
        SIGNAL="Wait"
        echo "  [MTF Filter] Sell blocked: SMA20 > SMA50 (uptrend)" >&2
    fi
fi

# Determine trend
TREND="横ばい"
if (( $(echo "$CURRENT_PRICE > $SMA20 && $SMA20 > $SMA50" | bc -l 2>/dev/null || echo 0) )); then
    TREND="上昇"
elif (( $(echo "$CURRENT_PRICE < $SMA20 && $SMA20 < $SMA50" | bc -l 2>/dev/null || echo 0) )); then
    TREND="下降"
fi

echo "--- Rule Analysis ---" >&2
echo "Buy conditions: $BUY_COUNT/4 (RSI:$BUY_RSI SMA:$BUY_SMA MACD:$BUY_MACD BB:$BUY_BB)" >&2
echo "Sell conditions: $SELL_COUNT/4 (RSI:$SELL_RSI SMA:$SELL_SMA MACD:$SELL_MACD BB:$SELL_BB)" >&2
echo "MTF Filter: SMA20 vs SMA50 = $(if [[ $SMA_TREND_UP -eq 1 ]]; then echo 'Uptrend'; elif [[ $SMA_TREND_DOWN -eq 1 ]]; then echo 'Downtrend'; else echo 'Flat'; fi)" >&2
echo "Signal: $SIGNAL" >&2
echo "Trend: $TREND" >&2

# Build comprehensive output
OUTPUT=$(jq -n \
    --argjson rsi "${RSI:-50}" \
    --argjson sma20 "${SMA20:-0}" \
    --argjson sma50 "${SMA50:-0}" \
    --argjson ema12 "${EMA12:-0}" \
    --argjson ema26 "${EMA26:-0}" \
    --argjson macd "${MACD:-0}" \
    --argjson macd_signal "${MACD_SIGNAL:-0}" \
    --argjson macd_histogram "${MACD_HISTOGRAM:-0}" \
    --argjson bb_upper "${BB_UPPER:-0}" \
    --argjson bb_middle "${BB_MIDDLE:-0}" \
    --argjson bb_lower "${BB_LOWER:-0}" \
    --arg bb_position "${BB_POSITION:-unknown}" \
    --argjson atr "${ATR:-0}" \
    --argjson atr_pct "${ATR_PCT:-0}" \
    --arg volatility "${VOLATILITY:-unknown}" \
    --argjson current_price "${CURRENT_PRICE:-0}" \
    --arg signal "$SIGNAL" \
    --arg trend "$TREND" \
    --argjson buy_count "$BUY_COUNT" \
    --argjson sell_count "$SELL_COUNT" \
    --argjson buy_rsi "${BUY_RSI:-0}" \
    --argjson buy_sma "${BUY_SMA:-0}" \
    --argjson buy_macd "${BUY_MACD:-0}" \
    --argjson buy_bb "${BUY_BB:-0}" \
    --argjson sell_rsi "${SELL_RSI:-0}" \
    --argjson sell_sma "${SELL_SMA:-0}" \
    --argjson sell_macd "${SELL_MACD:-0}" \
    --argjson sell_bb "${SELL_BB:-0}" \
    --argjson sma_trend_up "${SMA_TREND_UP:-0}" \
    --argjson sma_trend_down "${SMA_TREND_DOWN:-0}" \
    '{
        current_price: $current_price,
        indicators: {
            rsi_14: $rsi,
            sma_20: $sma20,
            sma_50: $sma50,
            ema_12: $ema12,
            ema_26: $ema26,
            macd: {
                macd: $macd,
                signal: $macd_signal,
                histogram: $macd_histogram
            },
            bollinger: {
                upper: $bb_upper,
                middle: $bb_middle,
                lower: $bb_lower,
                position: $bb_position
            },
            atr: {
                value: $atr,
                percent: $atr_pct,
                volatility: $volatility
            }
        },
        rule_analysis: {
            signal: $signal,
            trend: $trend,
            buy_conditions_met: $buy_count,
            sell_conditions_met: $sell_count,
            conditions: {
                buy: {
                    rsi_oversold: ($buy_rsi == 1),
                    above_sma20: ($buy_sma == 1),
                    macd_bullish: ($buy_macd == 1),
                    near_bb_lower: ($buy_bb == 1)
                },
                sell: {
                    rsi_overbought: ($sell_rsi == 1),
                    below_sma20: ($sell_sma == 1),
                    macd_bearish: ($sell_macd == 1),
                    near_bb_upper: ($sell_bb == 1)
                }
            },
            mtf_filter: {
                sma20_above_sma50: ($sma_trend_up == 1),
                sma20_below_sma50: ($sma_trend_down == 1),
                trend_direction: (if $sma_trend_up == 1 then "uptrend" elif $sma_trend_down == 1 then "downtrend" else "flat" end)
            }
        }
    }')

echo ""
echo "$OUTPUT"
