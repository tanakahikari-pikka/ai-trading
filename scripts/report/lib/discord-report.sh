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
WIN_COUNT=$(echo "$REPORT" | jq -r '.summary.win_count // 0')
LOSS_COUNT=$(echo "$REPORT" | jq -r '.summary.loss_count // 0')
REALIZED_PNL=$(echo "$REPORT" | jq -r '.summary.realized_pnl // 0')
UNREALIZED_PNL=$(echo "$REPORT" | jq -r '.summary.unrealized_pnl // 0')
WIN_RATE=$(echo "$REPORT" | jq -r '.summary.win_rate // 0')
PROFIT_FACTOR=$(echo "$REPORT" | jq -r '.summary.profit_factor // 0')
AVG_WINNER=$(echo "$REPORT" | jq -r '.summary.avg_winner // 0')
AVG_LOSER=$(echo "$REPORT" | jq -r '.summary.avg_loser // 0')
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

# Build instrument breakdown with win rate and profit factor
INSTRUMENT_BREAKDOWN=$(echo "$REPORT" | jq -r '
    .trades.by_instrument // [] |
    if length == 0 then
        "取引なし"
    else
        map("\(.symbol): \(.win_rate)% (\(.win_count)W/\(.loss_count)L) PF:\(.profit_factor)") |
        join("\n")
    end
')

# Build all trades list with win/loss indicators (limit to 15 for Discord)
ALL_TRADES=$(echo "$REPORT" | jq -r '
    .trades.all_trades // [] |
    if length == 0 then
        "トレードなし"
    else
        (length) as $total |
        .[0:15] |
        map(
            (if .is_winner then "+" else "-" end) as $icon |
            (if .pnl >= 0 then "+$" else "-$" end) as $pnl_prefix |
            (if .pnl < 0 then (-.pnl) else .pnl end) as $abs_pnl |
            (if .pips >= 0 then "+" else "" end) as $pips_prefix |
            "\($icon) \(.symbol) \(.direction) \($pips_prefix)\(.pips)pips (\($pnl_prefix)\($abs_pnl | . * 100 | round / 100))"
        ) |
        if $total > 15 then
            . + ["... 他 \($total - 15) 件"]
        else
            .
        end |
        join("\n")
    end
')

# Build session stats
SESSION_STATS=$(echo "$REPORT" | jq -r '
    .trades.by_session // [] |
    if length == 0 then
        "データなし"
    else
        # Sort: tokyo, london, ny, other
        sort_by(if .session == "tokyo" then 0 elif .session == "london" then 1 elif .session == "ny" then 2 else 3 end) |
        map(
            (if .session == "tokyo" then "🗼 東京" elif .session == "london" then "🏰 ロンドン" elif .session == "ny" then "🗽 NY" else "🌙 その他" end) as $name |
            (if .total_pnl >= 0 then "+" else "" end) as $sign |
            "\($name): \(.win_rate)% (\(.trade_count)回) \($sign)$\(.total_pnl)"
        ) |
        join("\n")
    end
')

# Build holding time distribution
HOLDING_STATS=$(echo "$REPORT" | jq -r '
    .trades.holding_distribution // [] |
    if length == 0 then
        "データなし"
    else
        map(
            (if .category == "scalp" then "⚡ スキャルプ(<5m)" elif .category == "short_term" then "🏃 短期(5-30m)" elif .category == "medium" then "🚶 中期(30m-2h)" else "🧘 長期(>2h)" end) as $name |
            (if .total_pnl >= 0 then "+" else "" end) as $sign |
            "\($name): \(.win_rate)% (\(.trade_count)回) \($sign)$\(.total_pnl)"
        ) |
        join("\n")
    end
')

# Build session × holding matrix (most important cross-tabulation)
# Format: 勝率%/PF(件数)
SESSION_HOLDING_MATRIX=$(echo "$REPORT" | jq -r '
    .trades.session_holding_matrix // [] |
    if length == 0 then
        "データなし"
    else
        # Group by session
        group_by(.session) |
        map(
            .[0].session as $sess |
            (if $sess == "tokyo" then "🗼東京" elif $sess == "london" then "🏰ロンドン" elif $sess == "ny" then "🗽NY" else "🌙他" end) as $sess_name |
            # Create row with all holding categories
            ($sess_name + "\n" + (
                . | map(
                    (if .holding == "scalp" then "  S:" elif .holding == "short_term" then "  短:" elif .holding == "medium" then "  中:" else "  長:" end) as $h |
                    "\($h) \(.win_rate)%/PF\(.profit_factor)(\(.trades)件)"
                ) | join("\n")
            ))
        ) |
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

# Format win/loss display
WIN_LOSS_DISPLAY="${WIN_COUNT}W/${LOSS_COUNT}L"

PAYLOAD=$(jq -n \
    --arg title "$EMOJI $TITLE" \
    --arg total_trades "$TOTAL_TRADES" \
    --arg win_rate "$WIN_RATE" \
    --arg win_loss "$WIN_LOSS_DISPLAY" \
    --arg profit_factor "$PROFIT_FACTOR" \
    --arg avg_winner "$AVG_WINNER" \
    --arg avg_loser "$AVG_LOSER" \
    --arg realized_pnl "$REALIZED_PNL_FMT" \
    --arg unrealized_pnl "$UNREALIZED_PNL_FMT" \
    --arg session_holding "$SESSION_HOLDING_MATRIX" \
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
                    value: "取引数: \($total_trades)\n勝率: \($win_rate)% (\($win_loss))\nPF: \($profit_factor)",
                    inline: true
                },
                {
                    name: "💰 損益",
                    value: "実現P/L: \($realized_pnl)\n含み損益: \($unrealized_pnl)\n平均勝ち: $\($avg_winner) / 負け: $\($avg_loser)",
                    inline: true
                },
                {
                    name: "💳 口座残高",
                    value: "\($cash_balance) \($currency)",
                    inline: true
                },
                {
                    name: "🎯 セッション×保有時間 (勝率/PF)",
                    value: $session_holding,
                    inline: false
                },
                {
                    name: "📊 通貨別パフォーマンス",
                    value: $instrument_breakdown,
                    inline: false
                },
                {
                    name: "📋 オープンポジション",
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
