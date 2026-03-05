#!/bin/bash
# Weekly Trading Report Generator
# Usage: weekly-report.sh
# Environment variables:
#   WEEK_OFFSET: 0 = last week (default), 1 = two weeks ago, etc.
#   DISCORD_REPORT_WEBHOOK_URL: Discord webhook for reports
#   SAXO_ACCESS_TOKEN: Saxo Bank API token

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SAXO_SCRIPTS="$PROJECT_ROOT/scripts/saxo"

source "$SCRIPT_DIR/lib/common.sh"

# Determine week offset (default: 0 = last week)
WEEK_OFFSET="${WEEK_OFFSET:-0}"

# Calculate target week dates
TODAY=$(date +%Y-%m-%d)
DAYS_TO_LAST_MONDAY=$(( $(get_day_of_week "$TODAY") - 1 + 7 + ($WEEK_OFFSET * 7) ))

if [[ "$(uname)" == "Darwin" ]]; then
    WEEK_START=$(date -v-${DAYS_TO_LAST_MONDAY}d +%Y-%m-%d 2>/dev/null)
else
    WEEK_START=$(date -d "$TODAY - $DAYS_TO_LAST_MONDAY days" +%Y-%m-%d)
fi

WEEK_END=$(get_week_sunday "$WEEK_START")
DAYS_BACK=$(days_between "$WEEK_START" "$TODAY")

echo "=== Weekly Trading Report ===" >&2
echo "Period: $WEEK_START ~ $WEEK_END" >&2
echo "Days back from today: $DAYS_BACK" >&2
echo "" >&2

# 1. Get trade history for the week (detailed mode for per-trade analysis)
echo "Fetching trade history..." >&2
TRADE_HISTORY=$("$SAXO_SCRIPTS/get-trade-history.sh" "$DAYS_BACK" detailed 2>/dev/null) || TRADE_HISTORY='{}'

# 2. Get account balance
echo "Fetching account balance..." >&2
BALANCE_RAW=$("$SAXO_SCRIPTS/get-balance.sh" 2>/dev/null) || BALANCE_RAW='{}'
# Extract JSON object from output
BALANCE_JSON=$(echo "$BALANCE_RAW" | sed -n '/^{/,/^}/p' | jq -c '.' 2>/dev/null || echo '{}')

# 3. Get open positions
echo "Fetching positions..." >&2
POSITIONS_RAW=$("$SAXO_SCRIPTS/get-positions.sh" 2>/dev/null) || POSITIONS_RAW='[]'

# Extract JSON array from output (skip text lines before JSON)
POSITIONS_JSON=$(echo "$POSITIONS_RAW" | sed -n '/^\[/,/^\]/p' | jq -c '.' 2>/dev/null || echo '[]')

# 4. Aggregate trade statistics (using detailed round-trip data)
TRADES_AGGREGATED=$(aggregate_round_trips "$TRADE_HISTORY")
TOTAL_TRADES=$(echo "$TRADES_AGGREGATED" | jq -r '.total_trades // 0')
REALIZED_PNL=$(echo "$TRADES_AGGREGATED" | jq -r '.total_pnl // 0')
WIN_COUNT=$(echo "$TRADES_AGGREGATED" | jq -r '.win_count // 0')
LOSS_COUNT=$(echo "$TRADES_AGGREGATED" | jq -r '.loss_count // 0')
WIN_RATE=$(echo "$TRADES_AGGREGATED" | jq -r '.win_rate // 0')
AVG_WINNER=$(echo "$TRADES_AGGREGATED" | jq -r '.avg_winner // 0')
AVG_LOSER=$(echo "$TRADES_AGGREGATED" | jq -r '.avg_loser // 0')
PROFIT_FACTOR=$(echo "$TRADES_AGGREGATED" | jq -r '.profit_factor // 0')
RISK_REWARD=$(echo "$TRADES_AGGREGATED" | jq -r '.risk_reward_ratio // 0')

# 5. Aggregate positions
POSITIONS_AGGREGATED=$(aggregate_positions "$POSITIONS_JSON")
UNREALIZED_PNL=$(echo "$POSITIONS_AGGREGATED" | jq -r '.total_unrealized_pnl // 0')

# 6. Extract balance info
CASH_BALANCE=$(echo "$BALANCE_JSON" | jq -r '.cashBalance // 0')
CURRENCY=$(echo "$BALANCE_JSON" | jq -r '.currency // "USD"')

# 7. Build final report JSON
REPORT=$(jq -n \
    --arg report_type "weekly" \
    --arg report_date "$WEEK_START" \
    --arg period_start "$WEEK_START" \
    --arg period_end "$WEEK_END" \
    --argjson total_trades "$TOTAL_TRADES" \
    --argjson realized_pnl "$REALIZED_PNL" \
    --argjson unrealized_pnl "$UNREALIZED_PNL" \
    --argjson win_rate "$WIN_RATE" \
    --argjson win_count "$WIN_COUNT" \
    --argjson loss_count "$LOSS_COUNT" \
    --argjson avg_winner "$AVG_WINNER" \
    --argjson avg_loser "$AVG_LOSER" \
    --argjson profit_factor "$PROFIT_FACTOR" \
    --argjson risk_reward "$RISK_REWARD" \
    --argjson cash_balance "$CASH_BALANCE" \
    --arg currency "$CURRENCY" \
    --argjson trades "$TRADES_AGGREGATED" \
    --argjson positions "$POSITIONS_AGGREGATED" \
    '{
        report_type: $report_type,
        report_date: $report_date,
        period: {
            start: $period_start,
            end: $period_end
        },
        summary: {
            total_trades: $total_trades,
            win_count: $win_count,
            loss_count: $loss_count,
            realized_pnl: $realized_pnl,
            unrealized_pnl: $unrealized_pnl,
            win_rate: $win_rate,
            avg_winner: $avg_winner,
            avg_loser: $avg_loser,
            profit_factor: $profit_factor,
            risk_reward_ratio: $risk_reward
        },
        balance: {
            cash_balance: $cash_balance,
            currency: $currency
        },
        trades: $trades,
        positions: $positions
    }')

# Output report JSON
echo "$REPORT"

# 8. Send to Discord if webhook is configured
if [[ -n "$DISCORD_REPORT_WEBHOOK_URL" ]]; then
    echo "" >&2
    echo "Sending to Discord..." >&2
    echo "$REPORT" | "$SCRIPT_DIR/lib/discord-report.sh"
fi

echo "" >&2
echo "Weekly report completed." >&2
