#!/bin/bash
# Common functions for trading reports
# Usage: source this file

# Get script directory
REPORT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$REPORT_LIB_DIR/../../.." && pwd)"

# Load .env if exists
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Date calculation functions (cross-platform: macOS + Linux)
get_date_days_ago() {
    local days_back="$1"
    date -v-${days_back}d +%Y-%m-%d 2>/dev/null || date -d "-${days_back} days" +%Y-%m-%d
}

get_date_days_ahead() {
    local days_ahead="$1"
    date -v+${days_ahead}d +%Y-%m-%d 2>/dev/null || date -d "+${days_ahead} days" +%Y-%m-%d
}

get_day_of_week() {
    local target_date="${1:-$(date +%Y-%m-%d)}"
    date -jf "%Y-%m-%d" "$target_date" +%u 2>/dev/null || date -d "$target_date" +%u
}

# Get Monday of the week containing the given date
get_week_monday() {
    local target_date="${1:-$(date +%Y-%m-%d)}"
    local day_of_week
    day_of_week=$(get_day_of_week "$target_date")
    local days_since_monday=$((day_of_week - 1))

    if [[ "$(uname)" == "Darwin" ]]; then
        date -jf "%Y-%m-%d" -v-${days_since_monday}d "$target_date" +%Y-%m-%d 2>/dev/null
    else
        date -d "$target_date - $days_since_monday days" +%Y-%m-%d
    fi
}

# Get Sunday of the week containing the given date
get_week_sunday() {
    local target_date="${1:-$(date +%Y-%m-%d)}"
    local day_of_week
    day_of_week=$(get_day_of_week "$target_date")
    local days_until_sunday=$((7 - day_of_week))

    if [[ "$(uname)" == "Darwin" ]]; then
        date -jf "%Y-%m-%d" -v+${days_until_sunday}d "$target_date" +%Y-%m-%d 2>/dev/null
    else
        date -d "$target_date + $days_until_sunday days" +%Y-%m-%d
    fi
}

# Calculate days between two dates
days_between() {
    local start_date="$1"
    local end_date="$2"

    if [[ "$(uname)" == "Darwin" ]]; then
        local start_ts end_ts
        start_ts=$(date -jf "%Y-%m-%d" "$start_date" +%s 2>/dev/null)
        end_ts=$(date -jf "%Y-%m-%d" "$end_date" +%s 2>/dev/null)
        echo $(( (end_ts - start_ts) / 86400 ))
    else
        local start_ts end_ts
        start_ts=$(date -d "$start_date" +%s)
        end_ts=$(date -d "$end_date" +%s)
        echo $(( (end_ts - start_ts) / 86400 ))
    fi
}

# Aggregate trade statistics from trade history JSON
# Input: trade history JSON from get-trade-history.sh
aggregate_trades() {
    local trade_json="$1"

    echo "$trade_json" | jq '
    {
        total_trades: (.total_trades // 0),
        by_instrument: (.by_instrument // []) | map({
            symbol: .symbol,
            trades: .trades,
            buy_count: .buy_count,
            sell_count: .sell_count,
            estimated_pnl: .estimated_pnl,
            net_position: .net_position
        }),
        summary: {
            total_estimated_pnl: ([.by_instrument[].estimated_pnl] | add // 0),
            winning_instruments: ([.by_instrument[] | select(.estimated_pnl > 0)] | length),
            losing_instruments: ([.by_instrument[] | select(.estimated_pnl < 0)] | length)
        }
    }'
}

# Aggregate positions from get-positions.sh output
# Input: positions JSON array
aggregate_positions() {
    local positions_json="$1"

    echo "$positions_json" | jq '
    if type == "array" then
        {
            count: length,
            positions: map({
                symbol: .symbol,
                amount: .amount,
                openPrice: .openPrice,
                currentPrice: .currentPrice,
                profitLoss: .profitLoss
            }),
            total_unrealized_pnl: ([.[].profitLoss // 0] | add // 0)
        }
    else
        {
            count: 0,
            positions: [],
            total_unrealized_pnl: 0
        }
    end'
}

# Format currency value
format_currency() {
    local value="$1"
    local currency="${2:-USD}"

    if [[ "$currency" == "USD" ]]; then
        printf "$%.2f" "$value"
    elif [[ "$currency" == "JPY" ]]; then
        printf "%.0f" "$value"
    else
        printf "%.2f %s" "$value" "$currency"
    fi
}

# Determine color based on P/L value
# Returns: green (positive), red (negative), gray (zero/none)
get_pnl_color() {
    local pnl="$1"

    if [[ -z "$pnl" || "$pnl" == "null" ]]; then
        echo "gray"
    elif (( $(echo "$pnl > 0" | bc -l) )); then
        echo "green"
    elif (( $(echo "$pnl < 0" | bc -l) )); then
        echo "red"
    else
        echo "gray"
    fi
}

# Get Discord color code
# green = 3066993, red = 15158332, gray = 9807270
get_discord_color() {
    local color_name="$1"

    case "$color_name" in
        green) echo "3066993" ;;
        red) echo "15158332" ;;
        *) echo "9807270" ;;
    esac
}
