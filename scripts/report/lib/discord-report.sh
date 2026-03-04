#!/bin/bash
# Discord report sender for trading reports
# Usage: echo "$REPORT_JSON" | discord-report.sh
# Requires: DISCORD_REPORT_WEBHOOK_URL environment variable

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ -z "$DISCORD_REPORT_WEBHOOK_URL" ]]; then
    echo "Warning: DISCORD_REPORT_WEBHOOK_URL not set, skipping notification" >&2
    exit 0
fi

# Read report JSON from stdin
REPORT=$(cat)

# Extract report type
REPORT_TYPE=$(echo "$REPORT" | jq -r '.report_type // "unknown"')
REPORT_DATE=$(echo "$REPORT" | jq -r '.report_date // "unknown"')
PERIOD_START=$(echo "$REPORT" | jq -r '.period.start // ""')
PERIOD_END=$(echo "$REPORT" | jq -r '.period.end // ""')

# Extract summary data
TOTAL_TRADES=$(echo "$REPORT" | jq -r '.summary.total_trades // 0')
REALIZED_PNL=$(echo "$REPORT" | jq -r '.summary.realized_pnl // 0')
UNREALIZED_PNL=$(echo "$REPORT" | jq -r '.summary.unrealized_pnl // 0')
WIN_RATE=$(echo "$REPORT" | jq -r '.summary.win_rate // 0')
CASH_BALANCE=$(echo "$REPORT" | jq -r '.balance.cash_balance // 0')
CURRENCY=$(echo "$REPORT" | jq -r '.balance.currency // "USD"')

# Determine color based on realized P/L
COLOR_NAME=$(get_pnl_color "$REALIZED_PNL")
COLOR=$(get_discord_color "$COLOR_NAME")

# Build title
if [[ "$REPORT_TYPE" == "daily" ]]; then
    TITLE="Daily Trading Report ($REPORT_DATE)"
    EMOJI="📊"
elif [[ "$REPORT_TYPE" == "weekly" ]]; then
    TITLE="Weekly Trading Report ($PERIOD_START ~ $PERIOD_END)"
    EMOJI="📈"
else
    TITLE="Trading Report"
    EMOJI="📊"
fi

# Format P/L with sign
format_pnl() {
    local value="$1"
    if (( $(echo "$value >= 0" | bc -l) )); then
        printf '+$%.2f' "$value"
    else
        # Remove leading minus and format with negative sign
        local abs_value="${value#-}"
        printf -- '-$%.2f' "$abs_value"
    fi
}

REALIZED_PNL_FMT=$(format_pnl "$REALIZED_PNL")
UNREALIZED_PNL_FMT=$(format_pnl "$UNREALIZED_PNL")

# Build instrument breakdown
INSTRUMENT_BREAKDOWN=$(echo "$REPORT" | jq -r '
    .trades.by_instrument // [] |
    if length == 0 then
        "取引なし"
    else
        map("\(.symbol): \(if .estimated_pnl >= 0 then "+" else "" end)\(.estimated_pnl | . * 100 | round / 100) (\(.trades)取引)") |
        join("\n")
    end
')

# Build positions summary
POSITIONS_SUMMARY=$(echo "$REPORT" | jq -r '
    .positions.positions // [] |
    if length == 0 then
        "オープンポジションなし"
    else
        map("\(.symbol) \(if .amount > 0 then "Buy" else "Sell" end) \(.amount | fabs) @ \(.openPrice) → \(.currentPrice) (\(if .profitLoss >= 0 then "+" else "" end)\(.profitLoss | . * 100 | round / 100))") |
        join("\n")
    end
')

# Build embed fields
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PAYLOAD=$(jq -n \
    --arg title "$EMOJI $TITLE" \
    --arg total_trades "$TOTAL_TRADES" \
    --arg win_rate "$WIN_RATE" \
    --arg realized_pnl "$REALIZED_PNL_FMT" \
    --arg unrealized_pnl "$UNREALIZED_PNL_FMT" \
    --arg instrument_breakdown "$INSTRUMENT_BREAKDOWN" \
    --arg positions_summary "$POSITIONS_SUMMARY" \
    --arg cash_balance "$CASH_BALANCE" \
    --arg currency "$CURRENCY" \
    --argjson color "$COLOR" \
    --arg timestamp "$TIMESTAMP" \
    '{
        embeds: [{
            title: $title,
            color: $color,
            fields: [
                {
                    name: "📈 取引サマリ",
                    value: "取引数: \($total_trades)\n勝率: \($win_rate)%",
                    inline: true
                },
                {
                    name: "💰 損益",
                    value: "実現P/L: \($realized_pnl)\n含み損益: \($unrealized_pnl)",
                    inline: true
                },
                {
                    name: "💳 口座残高",
                    value: "\($cash_balance) \($currency)",
                    inline: true
                },
                {
                    name: "📋 通貨別内訳",
                    value: $instrument_breakdown,
                    inline: false
                },
                {
                    name: "📊 オープンポジション",
                    value: $positions_summary,
                    inline: false
                }
            ],
            timestamp: $timestamp
        }]
    }')

# Send to Discord
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$DISCORD_REPORT_WEBHOOK_URL")

if [[ "$RESPONSE" == "204" || "$RESPONSE" == "200" ]]; then
    echo "Discord report notification sent successfully" >&2
else
    echo "Failed to send Discord report notification (HTTP $RESPONSE)" >&2
    exit 1
fi
