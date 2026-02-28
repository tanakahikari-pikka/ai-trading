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

# Calculate SMA20 slope (current vs 3 periods ago)
# Extract SMA20 values at current position and 3 periods back
SMA20_SLOPE_DATA=$(echo "$INPUT" | jq '
    [.close[] | select(. != null)] as $closes |
    if ($closes | length) >= 23 then
        # SMA20 at current position (last 20 values)
        ($closes[-20:] | add / 20) as $sma20_current |
        # SMA20 at 3 periods ago (values from -23 to -4)
        ($closes[-23:-3] | add / 20) as $sma20_3ago |
        {
            sma20_current: $sma20_current,
            sma20_3ago: $sma20_3ago,
            slope_up: ($sma20_current > $sma20_3ago),
            slope_down: ($sma20_current < $sma20_3ago)
        }
    else
        {
            sma20_current: 0,
            sma20_3ago: 0,
            slope_up: false,
            slope_down: false
        }
    end
')
SMA20_SLOPE_UP=$(echo "$SMA20_SLOPE_DATA" | jq -r 'if .slope_up then 1 else 0 end')
SMA20_SLOPE_DOWN=$(echo "$SMA20_SLOPE_DATA" | jq -r 'if .slope_down then 1 else 0 end')
SMA20_3AGO=$(echo "$SMA20_SLOPE_DATA" | jq -r '.sma20_3ago // 0')

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
BB_DATA=$(cat "$TEMP_FILE" | "$SCRIPT_DIR/bollinger.sh" 20 2 2>/dev/null || echo '{"upper":0,"middle":0,"lower":0,"position":"unknown","percent_b":50}')
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
# Histogram history for momentum detection (last 3 values)
HIST_HISTORY=$(echo "$MACD_DATA" | jq -r '.histogram_history // []')
BB_UPPER=$(echo "$BB_DATA" | jq -r '.upper // 0')
BB_MIDDLE=$(echo "$BB_DATA" | jq -r '.middle // 0')
BB_LOWER=$(echo "$BB_DATA" | jq -r '.lower // 0')
BB_POSITION=$(echo "$BB_DATA" | jq -r '.position // "unknown"')
ATR=$(echo "$ATR_DATA" | jq -r '.atr // 0')
ATR_PCT=$(echo "$ATR_DATA" | jq -r '.atr_percent // 0')
ATR_RATIO=$(echo "$ATR_DATA" | jq -r '.atr_ratio // 1')
ATR_EMA=$(echo "$ATR_DATA" | jq -r '.atr_ema // null')
VOLATILITY=$(echo "$ATR_DATA" | jq -r '.volatility // "unknown"')

# Ensure numeric values
RSI=${RSI:-50}
SMA20=${SMA20:-0}
SMA50=${SMA50:-0}
MACD=${MACD:-0}
MACD_SIGNAL=${MACD_SIGNAL:-0}
BB_MIDDLE=${BB_MIDDLE:-0}

# Extract %B from Bollinger Bands (already calculated in bollinger.sh)
# %B = (price - lower) / (upper - lower) * 100
# 0 = at lower band, 50 = at middle, 100 = at upper band
PERCENT_B=$(echo "$BB_DATA" | jq -r '.percent_b // 50')

# Calculate SMA20 proximity bands (ATR-based, directional)
# Buy: SMA20 - ATR < price <= SMA20 (pullback from below)
# Sell: SMA20 < price < SMA20 + ATR (retracement from above)
SMA20_BUY_LOWER=$(echo "$SMA20 - $ATR" | bc -l 2>/dev/null || echo 0)
SMA20_SELL_UPPER=$(echo "$SMA20 + $ATR" | bc -l 2>/dev/null || echo 0)
BUY_NEAR_SMA20=$(echo "$CURRENT_PRICE > $SMA20_BUY_LOWER && $CURRENT_PRICE <= $SMA20" | bc -l 2>/dev/null || echo 0)
SELL_NEAR_SMA20=$(echo "$CURRENT_PRICE > $SMA20 && $CURRENT_PRICE < $SMA20_SELL_UPPER" | bc -l 2>/dev/null || echo 0)

# Determine SMA trend alignment (MTF filter)
SMA_TREND_UP=$(echo "$SMA20 > $SMA50" | bc -l 2>/dev/null || echo 0)
SMA_TREND_DOWN=$(echo "$SMA20 < $SMA50" | bc -l 2>/dev/null || echo 0)

# Dynamic RSI thresholds based on ATR ratio
# High volatility (atr_ratio > 1.5): stricter thresholds (30/70)
# Normal volatility: relaxed thresholds (40/60)
HIGH_VOLATILITY=$(echo "$ATR_RATIO > 1.5" | bc -l 2>/dev/null || echo 0)
if [[ $HIGH_VOLATILITY -eq 1 ]]; then
    RSI_BUY_THRESHOLD=30
    RSI_SELL_THRESHOLD=70
else
    RSI_BUY_THRESHOLD=40
    RSI_SELL_THRESHOLD=60
fi

# Category-based analysis (position >= 2 AND momentum >= 1)
# Buy position conditions (3 conditions)
BUY_RSI=$(echo "$RSI < $RSI_BUY_THRESHOLD" | bc -l 2>/dev/null || echo 0)
# BUY_NEAR_SMA20 already calculated above (SMA20 - ATR < price <= SMA20)
# %B < 30 means price is in the lower 30% of the band (normalized, volatility-independent)
BUY_BB=$(echo "$PERCENT_B < 30" | bc -l 2>/dev/null || echo 0)
BUY_POSITION_COUNT=$((BUY_RSI + BUY_NEAR_SMA20 + BUY_BB))

# Buy momentum conditions (2 conditions, need 1)
BUY_MACD=$(echo "$MACD > $MACD_SIGNAL" | bc -l 2>/dev/null || echo 0)
# Histogram increasing: hist[-1] > hist[-2] > hist[-3] (momentum recovery)
BUY_HIST_INCREASING=$(echo "$HIST_HISTORY" | jq '
    if length >= 3 then
        (.[2] > .[1] and .[1] > .[0]) | if . then 1 else 0 end
    else 0 end
')
BUY_MOMENTUM_COUNT=$((BUY_MACD > 0 ? 1 : 0))
if [[ $BUY_HIST_INCREASING -eq 1 ]]; then
    BUY_MOMENTUM_COUNT=1
fi

# Legacy count for backward compatibility
BUY_COUNT=$((BUY_RSI + BUY_NEAR_SMA20 + BUY_MACD + BUY_BB))

# Sell position conditions (3 conditions)
SELL_RSI=$(echo "$RSI > $RSI_SELL_THRESHOLD" | bc -l 2>/dev/null || echo 0)
# SELL_NEAR_SMA20 already calculated above (SMA20 < price < SMA20 + ATR)
# %B > 70 means price is in the upper 30% of the band (normalized, volatility-independent)
SELL_BB=$(echo "$PERCENT_B > 70" | bc -l 2>/dev/null || echo 0)
SELL_POSITION_COUNT=$((SELL_RSI + SELL_NEAR_SMA20 + SELL_BB))

# Sell momentum conditions (2 conditions, need 1)
SELL_MACD=$(echo "$MACD < $MACD_SIGNAL" | bc -l 2>/dev/null || echo 0)
# Histogram decreasing: hist[-1] < hist[-2] < hist[-3] (momentum fading)
SELL_HIST_DECREASING=$(echo "$HIST_HISTORY" | jq '
    if length >= 3 then
        (.[2] < .[1] and .[1] < .[0]) | if . then 1 else 0 end
    else 0 end
')
SELL_MOMENTUM_COUNT=$((SELL_MACD > 0 ? 1 : 0))
if [[ $SELL_HIST_DECREASING -eq 1 ]]; then
    SELL_MOMENTUM_COUNT=1
fi

# Legacy count for backward compatibility
SELL_COUNT=$((SELL_RSI + SELL_NEAR_SMA20 + SELL_MACD + SELL_BB))

# Check ATR filter (range market suppression)
LOW_VOLATILITY=$(echo "$ATR_RATIO < 0.7" | bc -l 2>/dev/null || echo 0)

# Determine signal (category-based: position >= 2 AND momentum >= 1)
# Note: MTF filter is applied in auto-trade.sh using 4h timeframe data
SIGNAL="Wait"

# ATR filter: suppress signals in low volatility (range market)
if [[ $LOW_VOLATILITY -eq 1 ]]; then
    SIGNAL="Wait"
    echo "  [ATR Filter] Signal blocked: atr_ratio=$ATR_RATIO < 0.7 (low volatility / range market)" >&2
elif [[ $BUY_POSITION_COUNT -ge 2 && $BUY_MOMENTUM_COUNT -ge 1 ]]; then
    # Check if Buy is stronger than Sell
    if [[ $SELL_POSITION_COUNT -lt 2 || $SELL_MOMENTUM_COUNT -lt 1 ]]; then
        SIGNAL="Buy"
    elif [[ $BUY_POSITION_COUNT -gt $SELL_POSITION_COUNT ]]; then
        SIGNAL="Buy"
    fi
elif [[ $SELL_POSITION_COUNT -ge 2 && $SELL_MOMENTUM_COUNT -ge 1 ]]; then
    # Check if Sell is stronger than Buy
    if [[ $BUY_POSITION_COUNT -lt 2 || $BUY_MOMENTUM_COUNT -lt 1 ]]; then
        SIGNAL="Sell"
    elif [[ $SELL_POSITION_COUNT -gt $BUY_POSITION_COUNT ]]; then
        SIGNAL="Sell"
    fi
fi

# Determine trend
TREND="横ばい"
if (( $(echo "$CURRENT_PRICE > $SMA20 && $SMA20 > $SMA50" | bc -l 2>/dev/null || echo 0) )); then
    TREND="上昇"
elif (( $(echo "$CURRENT_PRICE < $SMA20 && $SMA20 < $SMA50" | bc -l 2>/dev/null || echo 0) )); then
    TREND="下降"
fi

echo "--- Rule Analysis (Category-based) ---" >&2
echo "RSI Thresholds: buy<$RSI_BUY_THRESHOLD sell>$RSI_SELL_THRESHOLD (high_vol=$HIGH_VOLATILITY)" >&2
echo "Buy Position: $BUY_POSITION_COUNT/3 (RSI:$BUY_RSI SMA20:$BUY_NEAR_SMA20 BB:$BUY_BB)" >&2
echo "Buy Momentum: $BUY_MOMENTUM_COUNT/1 (MACD:$BUY_MACD HistInc:$BUY_HIST_INCREASING)" >&2
echo "Sell Position: $SELL_POSITION_COUNT/3 (RSI:$SELL_RSI SMA20:$SELL_NEAR_SMA20 BB:$SELL_BB)" >&2
echo "Sell Momentum: $SELL_MOMENTUM_COUNT/1 (MACD:$SELL_MACD HistDec:$SELL_HIST_DECREASING)" >&2
echo "Legacy counts: Buy=$BUY_COUNT/4 Sell=$SELL_COUNT/4" >&2
echo "Bollinger %B: $PERCENT_B (buy<30, sell>70)" >&2
echo "SMA20 Proximity: buy=$BUY_NEAR_SMA20 (SMA20-ATR=$SMA20_BUY_LOWER to SMA20=$SMA20) sell=$SELL_NEAR_SMA20 (SMA20=$SMA20 to SMA20+ATR=$SMA20_SELL_UPPER)" >&2
echo "SMA20 Slope: up=$SMA20_SLOPE_UP down=$SMA20_SLOPE_DOWN (AI参考用)" >&2
echo "ATR Filter: atr_ratio=$ATR_RATIO (low_vol=$LOW_VOLATILITY, threshold=0.7)" >&2
echo "1h SMA Trend: SMA20 vs SMA50 = $(if [[ $SMA_TREND_UP -eq 1 ]]; then echo 'Uptrend'; elif [[ $SMA_TREND_DOWN -eq 1 ]]; then echo 'Downtrend'; else echo 'Flat'; fi) (参考用、MTFフィルターは4hで適用)" >&2
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
    --argjson hist_history "${HIST_HISTORY:-[]}" \
    --argjson bb_upper "${BB_UPPER:-0}" \
    --argjson bb_middle "${BB_MIDDLE:-0}" \
    --argjson bb_lower "${BB_LOWER:-0}" \
    --arg bb_position "${BB_POSITION:-unknown}" \
    --argjson percent_b "${PERCENT_B:-50}" \
    --argjson atr "${ATR:-0}" \
    --argjson atr_pct "${ATR_PCT:-0}" \
    --argjson atr_ema "${ATR_EMA:-null}" \
    --argjson atr_ratio "${ATR_RATIO:-1}" \
    --argjson low_volatility "${LOW_VOLATILITY:-0}" \
    --argjson high_volatility "${HIGH_VOLATILITY:-0}" \
    --argjson rsi_buy_threshold "${RSI_BUY_THRESHOLD:-40}" \
    --argjson rsi_sell_threshold "${RSI_SELL_THRESHOLD:-60}" \
    --arg volatility "${VOLATILITY:-unknown}" \
    --argjson current_price "${CURRENT_PRICE:-0}" \
    --arg signal "$SIGNAL" \
    --arg trend "$TREND" \
    --argjson buy_count "$BUY_COUNT" \
    --argjson sell_count "$SELL_COUNT" \
    --argjson buy_position_count "${BUY_POSITION_COUNT:-0}" \
    --argjson buy_momentum_count "${BUY_MOMENTUM_COUNT:-0}" \
    --argjson sell_position_count "${SELL_POSITION_COUNT:-0}" \
    --argjson sell_momentum_count "${SELL_MOMENTUM_COUNT:-0}" \
    --argjson buy_rsi "${BUY_RSI:-0}" \
    --argjson buy_near_sma20 "${BUY_NEAR_SMA20:-0}" \
    --argjson buy_macd "${BUY_MACD:-0}" \
    --argjson buy_bb "${BUY_BB:-0}" \
    --argjson buy_hist_increasing "${BUY_HIST_INCREASING:-0}" \
    --argjson sell_rsi "${SELL_RSI:-0}" \
    --argjson sell_near_sma20 "${SELL_NEAR_SMA20:-0}" \
    --argjson sell_macd "${SELL_MACD:-0}" \
    --argjson sell_bb "${SELL_BB:-0}" \
    --argjson sell_hist_decreasing "${SELL_HIST_DECREASING:-0}" \
    --argjson sma_trend_up "${SMA_TREND_UP:-0}" \
    --argjson sma_trend_down "${SMA_TREND_DOWN:-0}" \
    --argjson sma20_buy_lower "${SMA20_BUY_LOWER:-0}" \
    --argjson sma20_sell_upper "${SMA20_SELL_UPPER:-0}" \
    --argjson sma20_slope_up "${SMA20_SLOPE_UP:-0}" \
    --argjson sma20_slope_down "${SMA20_SLOPE_DOWN:-0}" \
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
                histogram: $macd_histogram,
                histogram_history: $hist_history
            },
            bollinger: {
                upper: $bb_upper,
                middle: $bb_middle,
                lower: $bb_lower,
                position: $bb_position,
                percent_b: $percent_b
            },
            atr: {
                value: $atr,
                percent: $atr_pct,
                atr_ema: $atr_ema,
                atr_ratio: $atr_ratio,
                volatility: $volatility
            }
        },
        rule_analysis: {
            signal: $signal,
            trend: $trend,
            buy_conditions_met: $buy_count,
            sell_conditions_met: $sell_count,
            category_based: {
                buy: {
                    position_count: $buy_position_count,
                    momentum_count: $buy_momentum_count,
                    position_met: ($buy_position_count >= 2),
                    momentum_met: ($buy_momentum_count >= 1),
                    fired: (($buy_position_count >= 2) and ($buy_momentum_count >= 1))
                },
                sell: {
                    position_count: $sell_position_count,
                    momentum_count: $sell_momentum_count,
                    position_met: ($sell_position_count >= 2),
                    momentum_met: ($sell_momentum_count >= 1),
                    fired: (($sell_position_count >= 2) and ($sell_momentum_count >= 1))
                }
            },
            conditions: {
                buy: {
                    position: {
                        rsi_oversold: ($buy_rsi == 1),
                        near_sma20: ($buy_near_sma20 == 1),
                        near_bb_lower: ($buy_bb == 1)
                    },
                    momentum: {
                        macd_bullish: ($buy_macd == 1),
                        histogram_increasing: ($buy_hist_increasing == 1)
                    }
                },
                sell: {
                    position: {
                        rsi_overbought: ($sell_rsi == 1),
                        near_sma20: ($sell_near_sma20 == 1),
                        near_bb_upper: ($sell_bb == 1)
                    },
                    momentum: {
                        macd_bearish: ($sell_macd == 1),
                        histogram_decreasing: ($sell_hist_decreasing == 1)
                    }
                }
            },
            sma20_proximity: {
                buy_zone: ($buy_near_sma20 == 1),
                sell_zone: ($sell_near_sma20 == 1),
                buy_lower: $sma20_buy_lower,
                sell_upper: $sma20_sell_upper
            },
            sma20_slope: {
                slope_up: ($sma20_slope_up == 1),
                slope_down: ($sma20_slope_down == 1)
            },
            mtf_filter: {
                sma20_above_sma50: ($sma_trend_up == 1),
                sma20_below_sma50: ($sma_trend_down == 1),
                trend_direction: (if $sma_trend_up == 1 then "uptrend" elif $sma_trend_down == 1 then "downtrend" else "flat" end)
            },
            atr_filter: {
                atr_ratio: $atr_ratio,
                low_volatility: ($low_volatility == 1),
                threshold: 0.7
            },
            rsi_thresholds: {
                buy_threshold: $rsi_buy_threshold,
                sell_threshold: $rsi_sell_threshold,
                high_volatility: ($high_volatility == 1),
                mode: (if $high_volatility == 1 then "strict (30/70)" else "relaxed (40/60)" end)
            }
        }
    }')

echo ""
echo "$OUTPUT"
