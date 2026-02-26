#!/bin/bash
# Send notification to Discord via Webhook
# Usage: echo "$JSON_RESULT" | discord.sh
# Requires: DISCORD_WEBHOOK_URL environment variable

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env if exists
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
    echo "Warning: DISCORD_WEBHOOK_URL not set, skipping notification" >&2
    exit 0
fi

# Read JSON from stdin
RESULT=$(cat)

# Extract values
DECISION=$(echo "$RESULT" | jq -r '.decision // "unknown"')
SYMBOL=$(echo "$RESULT" | jq -r '.symbol // "USDJPY"')
ACTION=$(echo "$RESULT" | jq -r '.action // "none"')
AMOUNT=$(echo "$RESULT" | jq -r '.amount // "N/A"')
RSI=$(echo "$RESULT" | jq -r '.rsi // "N/A"' | xargs printf "%.2f")
RULE_SIGNAL=$(echo "$RESULT" | jq -r '.rule_signal // "N/A"')
BID=$(echo "$RESULT" | jq -r '.price.bid // "N/A"')
ASK=$(echo "$RESULT" | jq -r '.price.ask // "N/A"')
AI_TREND=$(echo "$RESULT" | jq -r '.ai_analysis.trend // "N/A"')
AI_RISK=$(echo "$RESULT" | jq -r '.ai_analysis.risk // "N/A"')
AI_COMMENT=$(echo "$RESULT" | jq -r '.ai_analysis.comment // ""')

# Set color based on decision
if [[ "$DECISION" == "go" ]]; then
    if [[ "$ACTION" == "Buy" ]]; then
        COLOR=3066993  # Green
        EMOJI="🟢"
    else
        COLOR=15158332  # Red
        EMOJI="🔴"
    fi
else
    COLOR=9807270  # Gray
    EMOJI="⚪"
fi

# Build Discord embed
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PAYLOAD=$(jq -n \
    --arg emoji "$EMOJI" \
    --arg decision "$DECISION" \
    --arg symbol "$SYMBOL" \
    --arg action "$ACTION" \
    --arg amount "$AMOUNT" \
    --arg rsi "$RSI" \
    --arg rule_signal "$RULE_SIGNAL" \
    --arg bid "$BID" \
    --arg ask "$ASK" \
    --arg ai_trend "$AI_TREND" \
    --arg ai_risk "$AI_RISK" \
    --arg ai_comment "$AI_COMMENT" \
    --argjson color "$COLOR" \
    --arg timestamp "$TIMESTAMP" \
    '{
        embeds: [{
            title: "\($emoji) Auto Trade: \($symbol)",
            color: $color,
            fields: [
                {
                    name: "判断",
                    value: $decision,
                    inline: true
                },
                {
                    name: "アクション",
                    value: (if $action == "none" then "-" else $action end),
                    inline: true
                },
                {
                    name: "数量",
                    value: (if $amount == "N/A" then "-" else $amount end),
                    inline: true
                },
                {
                    name: "RSI(14)",
                    value: $rsi,
                    inline: true
                },
                {
                    name: "ルールシグナル",
                    value: $rule_signal,
                    inline: true
                },
                {
                    name: "リスク",
                    value: $ai_risk,
                    inline: true
                },
                {
                    name: "価格",
                    value: "Bid: \($bid) / Ask: \($ask)",
                    inline: false
                },
                {
                    name: "AI分析",
                    value: "トレンド: \($ai_trend)\n\($ai_comment)",
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
    "$DISCORD_WEBHOOK_URL")

if [[ "$RESPONSE" == "204" || "$RESPONSE" == "200" ]]; then
    echo "Discord notification sent successfully" >&2
else
    echo "Failed to send Discord notification (HTTP $RESPONSE)" >&2
fi
