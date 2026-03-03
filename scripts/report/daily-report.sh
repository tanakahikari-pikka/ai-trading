#!/bin/bash
# Daily Trading Report Generator
# Usage: daily-report.sh
# Environment variables:
#   REPORT_DATE: Target date (default: yesterday)
#   DISCORD_REPORT_WEBHOOK_URL: Discord webhook for reports
#   SAXO_ACCESS_TOKEN: Saxo Bank API token

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SAXO_SCRIPTS="$PROJECT_ROOT/scripts/saxo"

source "$SCRIPT_DIR/lib/common.sh"

# Determine report date (default: yesterday)
if [[ -n "$REPORT_DATE" ]]; then
    TARGET_DATE="$REPORT_DATE"
else
    TARGET_DATE=$(get_date_days_ago 1)
fi

echo "=== Daily Trading Report ===" >&2
echo "Date: $TARGET_DATE" >&2
echo "" >&2

# 1. Get trade history for the target date
echo "Fetching trade history..." >&2
TRADE_HISTORY=$("$SAXO_SCRIPTS/get-trade-history.sh" 1 2>/dev/null) || TRADE_HISTORY='{}'

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

# 4. Aggregate trade statistics
TRADES_AGGREGATED=$(aggregate_trades "$TRADE_HISTORY")
TOTAL_TRADES=$(echo "$TRADES_AGGREGATED" | jq -r '.total_trades // 0')
REALIZED_PNL=$(echo "$TRADES_AGGREGATED" | jq -r '.summary.total_estimated_pnl // 0')
WINNING=$(echo "$TRADES_AGGREGATED" | jq -r '.summary.winning_instruments // 0')
LOSING=$(echo "$TRADES_AGGREGATED" | jq -r '.summary.losing_instruments // 0')

# Calculate win rate
if [[ $((WINNING + LOSING)) -gt 0 ]]; then
    WIN_RATE=$(echo "scale=0; $WINNING * 100 / ($WINNING + $LOSING)" | bc)
else
    WIN_RATE=0
fi

# 5. Aggregate positions
POSITIONS_AGGREGATED=$(aggregate_positions "$POSITIONS_JSON")
UNREALIZED_PNL=$(echo "$POSITIONS_AGGREGATED" | jq -r '.total_unrealized_pnl // 0')

# 6. Extract balance info
CASH_BALANCE=$(echo "$BALANCE_JSON" | jq -r '.cashBalance // 0')
CURRENCY=$(echo "$BALANCE_JSON" | jq -r '.currency // "USD"')

# 7. Build final report JSON
REPORT=$(jq -n \
    --arg report_type "daily" \
    --arg report_date "$TARGET_DATE" \
    --argjson total_trades "$TOTAL_TRADES" \
    --argjson realized_pnl "$REALIZED_PNL" \
    --argjson unrealized_pnl "$UNREALIZED_PNL" \
    --argjson win_rate "$WIN_RATE" \
    --argjson cash_balance "$CASH_BALANCE" \
    --arg currency "$CURRENCY" \
    --argjson trades "$TRADES_AGGREGATED" \
    --argjson positions "$POSITIONS_AGGREGATED" \
    '{
        report_type: $report_type,
        report_date: $report_date,
        period: {
            start: $report_date,
            end: $report_date
        },
        summary: {
            total_trades: $total_trades,
            realized_pnl: $realized_pnl,
            unrealized_pnl: $unrealized_pnl,
            win_rate: $win_rate
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
echo "Daily report completed." >&2
