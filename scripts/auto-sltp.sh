#!/bin/bash
set -eo pipefail
# Auto SL/TP setter - Sets SL/TP on positions that don't have them
# Usage: auto-sltp.sh [--dry-run]
#
# SL/TP calculation:
#   - Stop Loss: ATR × 1.5 from entry price
#   - Take Profit: SL distance × 2.0 (Risk:Reward = 1:2)

AUTO_SLTP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$AUTO_SLTP_DIR/.." && pwd)"

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE ===" >&2
fi

# Load environment
source "$AUTO_SLTP_DIR/saxo/auth.sh"

# Symbol to Yahoo Finance symbol mapping
get_yahoo_symbol() {
    local symbol="$1"
    case "$symbol" in
        USDJPY) echo "USDJPY=X" ;;
        EURUSD) echo "EURUSD=X" ;;
        GBPUSD) echo "GBPUSD=X" ;;
        GBPJPY) echo "GBPJPY=X" ;;
        EURJPY) echo "EURJPY=X" ;;
        AUDUSD) echo "AUDUSD=X" ;;
        USDPLN) echo "PLN=X" ;;
        XAUUSD) echo "GC=F" ;;
        XAGUSD) echo "SI=F" ;;
        *) echo "${symbol}=X" ;;
    esac
}

# Get decimal places for symbol
get_decimal_places() {
    local symbol="$1"
    case "$symbol" in
        *JPY) echo "3" ;;
        XAUUSD) echo "2" ;;
        XAGUSD) echo "3" ;;
        *) echo "5" ;;
    esac
}

# Calculate ATR for a symbol
calculate_atr() {
    local yahoo_symbol="$1"

    PRICE_DATA=$("$AUTO_SLTP_DIR/yahoo-finance/get-chart.sh" "$yahoo_symbol" "1h" "10d") || true
    if [[ -z "$PRICE_DATA" ]]; then
        echo "ERROR: get-chart.sh returned empty for $yahoo_symbol" >&2
        echo "null"
        return 1
    fi

    ATR_DATA=$(echo "$PRICE_DATA" | "$AUTO_SLTP_DIR/indicators/atr.sh" 14) || true
    if [[ -z "$ATR_DATA" ]]; then
        echo "ERROR: atr.sh returned empty for $yahoo_symbol" >&2
        echo "null"
        return 1
    fi

    echo "$ATR_DATA" | jq -r '.atr'
}

# Set SL/TP for a position using PositionId + Orders array (FifoEndOfDay mode)
# This links orders to the position - they auto-cancel when position closes
set_sltp() {
    local position_id="$1"
    local account_key="$2"
    local uic="$3"
    local asset_type="$4"
    local symbol="$5"
    local amount="$6"
    local open_price="$7"
    local sl_price="$8"
    local tp_price="$9"
    local needs_sl="${10}"
    local needs_tp="${11}"

    # Determine close direction (opposite of position)
    local close_direction
    if (( $(echo "$amount > 0" | bc -l) )); then
        close_direction="Sell"
    else
        close_direction="Buy"
    fi

    local amount_abs=$(echo "$amount" | tr -d '-')

    # Build Orders array
    local orders="[]"

    if [[ "$needs_sl" == "true" ]]; then
        echo "  Setting SL @ $sl_price" >&2
        orders=$(echo "$orders" | jq \
            --arg buySell "$close_direction" \
            --argjson uic "$uic" \
            --argjson amount "$amount_abs" \
            --argjson orderPrice "$sl_price" \
            --arg assetType "$asset_type" \
            '. + [{
                Uic: $uic,
                BuySell: $buySell,
                Amount: $amount,
                AssetType: $assetType,
                OrderType: "Stop",
                OrderPrice: $orderPrice,
                ManualOrder: true,
                OrderDuration: { DurationType: "GoodTillCancel" }
            }]')
    fi

    if [[ "$needs_tp" == "true" ]]; then
        echo "  Setting TP @ $tp_price" >&2
        orders=$(echo "$orders" | jq \
            --arg buySell "$close_direction" \
            --argjson uic "$uic" \
            --argjson amount "$amount_abs" \
            --argjson orderPrice "$tp_price" \
            --arg assetType "$asset_type" \
            '. + [{
                Uic: $uic,
                BuySell: $buySell,
                Amount: $amount,
                AssetType: $assetType,
                OrderType: "Limit",
                OrderPrice: $orderPrice,
                ManualOrder: true,
                OrderDuration: { DurationType: "GoodTillCancel" }
            }]')
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        # Use PositionId + Orders array to link orders to position
        RESPONSE=$(curl -s -X POST "$SAXO_BASE_URL/trade/v2/orders" \
            -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg positionId "$position_id" \
                --argjson orders "$orders" \
                '{
                    PositionId: $positionId,
                    Orders: $orders
                }')")

        # Check response
        if echo "$RESPONSE" | jq -e '.Orders[0].OrderId' > /dev/null 2>&1; then
            local order_ids=$(echo "$RESPONSE" | jq -r '.Orders[].OrderId' | tr '\n' ', ' | sed 's/,$//')
            echo "  Linked to position: OrderIds [$order_ids]" >&2
        else
            # Extract error message
            local error_msg=$(echo "$RESPONSE" | jq -r '.Orders[0].ErrorInfo.Message // .Message // .ErrorInfo.Message // "Unknown error"')
            echo "  FAILED: $error_msg" >&2
            return 1
        fi
    fi
}

# Main
echo "=== Auto SL/TP Setter ===" >&2
echo "Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >&2
echo "" >&2

# Check positions without SL/TP
CHECK_STDERR=$(mktemp)
MISSING=$("$AUTO_SLTP_DIR/saxo/check-sltp-status.sh" 2>"$CHECK_STDERR") || true
CHECK_EXIT=$?
if [[ $CHECK_EXIT -ne 0 ]]; then
    echo "FATAL: check-sltp-status.sh failed with exit code $CHECK_EXIT" >&2
    cat "$CHECK_STDERR" >&2
    rm -f "$CHECK_STDERR"
    exit 1
fi
cat "$CHECK_STDERR" >&2
rm -f "$CHECK_STDERR"

if ! echo "$MISSING" | jq empty 2>/dev/null; then
    echo "FATAL: check-sltp-status.sh returned invalid JSON" >&2
    echo "Output: $MISSING" >&2
    exit 1
fi

MISSING_COUNT=$(echo "$MISSING" | jq 'length')

if [[ "$MISSING_COUNT" -eq 0 ]]; then
    echo "All positions have SL/TP set." >&2
    echo '{"status":"ok","message":"All positions have SL/TP","processed":0}'
    exit 0
fi

echo "" >&2
echo "Processing $MISSING_COUNT positions..." >&2
echo "" >&2

PROCESSED=0
FAILED=0

# Process each position (process substitution to avoid subshell)
while read -r position; do
    POSITION_ID=$(echo "$position" | jq -r '.positionId')
    SYMBOL=$(echo "$position" | jq -r '.symbol')
    AMOUNT=$(echo "$position" | jq -r '.amount')
    OPEN_PRICE=$(echo "$position" | jq -r '.openPrice')
    UIC=$(echo "$position" | jq -r '.uic')
    ASSET_TYPE=$(echo "$position" | jq -r '.assetType')
    ACCOUNT_KEY=$(echo "$position" | jq -r '.accountKey')
    DIRECTION=$(echo "$position" | jq -r '.direction')
    NEEDS_SL=$(echo "$position" | jq -r '.needsSL')
    NEEDS_TP=$(echo "$position" | jq -r '.needsTP')

    echo "[$SYMBOL] $DIRECTION @ $OPEN_PRICE (Pos: $POSITION_ID)" >&2

    # Get Yahoo symbol and calculate ATR
    YAHOO_SYMBOL=$(get_yahoo_symbol "$SYMBOL")
    DECIMALS=$(get_decimal_places "$SYMBOL")

    ATR=$(calculate_atr "$YAHOO_SYMBOL")

    if [[ "$ATR" == "null" || -z "$ATR" ]]; then
        echo "  ERROR: Could not calculate ATR for $SYMBOL, skipping" >&2
        FAILED=$((FAILED + 1))
        continue
    fi

    echo "  ATR: $ATR" >&2

    # Calculate SL/TP based on direction
    SL_DISTANCE=$(echo "$ATR * 1.5" | bc -l)
    TP_DISTANCE=$(echo "$SL_DISTANCE * 2.0" | bc -l)

    if [[ "$DIRECTION" == "Long" ]]; then
        SL_PRICE=$(printf "%.${DECIMALS}f" $(echo "$OPEN_PRICE - $SL_DISTANCE" | bc -l))
        TP_PRICE=$(printf "%.${DECIMALS}f" $(echo "$OPEN_PRICE + $TP_DISTANCE" | bc -l))
    else
        SL_PRICE=$(printf "%.${DECIMALS}f" $(echo "$OPEN_PRICE + $SL_DISTANCE" | bc -l))
        TP_PRICE=$(printf "%.${DECIMALS}f" $(echo "$OPEN_PRICE - $TP_DISTANCE" | bc -l))
    fi

    echo "  Calculated: SL=$SL_PRICE, TP=$TP_PRICE" >&2

    # Set SL/TP
    if set_sltp "$POSITION_ID" "$ACCOUNT_KEY" "$UIC" "$ASSET_TYPE" "$SYMBOL" "$AMOUNT" "$OPEN_PRICE" "$SL_PRICE" "$TP_PRICE" "$NEEDS_SL" "$NEEDS_TP"; then
        PROCESSED=$((PROCESSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
    echo "" >&2
done < <(echo "$MISSING" | jq -c '.[]')

echo "=== Complete ===" >&2
echo "Processed: $PROCESSED, Failed: $FAILED, Total: $MISSING_COUNT" >&2

if [[ $FAILED -gt 0 ]]; then
    echo "WARNING: $FAILED positions failed to get SL/TP" >&2
fi

# Output result JSON
jq -n \
    --arg status "$(if [[ $FAILED -gt 0 ]]; then echo "partial"; else echo "ok"; fi)" \
    --argjson processed "$PROCESSED" \
    --argjson failed "$FAILED" \
    --argjson total "$MISSING_COUNT" \
    --arg dryRun "$DRY_RUN" \
    '{
        status: $status,
        processed: $processed,
        failed: $failed,
        total: $total,
        dryRun: ($dryRun == "true"),
        timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    }'
