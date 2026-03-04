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

# Extract basic values
DECISION=$(echo "$RESULT" | jq -r '.decision // "unknown"')
SYMBOL=$(echo "$RESULT" | jq -r '.symbol // "USDJPY"')
STRATEGY=$(echo "$RESULT" | jq -r '.strategy // "mean-reversion"')
ACTION=$(echo "$RESULT" | jq -r '.action // null')
AMOUNT=$(echo "$RESULT" | jq -r '.amount // null | if . == null then "-" else tostring end')

# Extract analysis
RSI_RAW=$(echo "$RESULT" | jq -r '.analysis.rsi // null')
if [[ "$RSI_RAW" != "null" && -n "$RSI_RAW" ]]; then
    RSI=$(printf "%.2f" "$RSI_RAW" 2>/dev/null || echo "$RSI_RAW")
else
    RSI="N/A"
fi
RULE_SIGNAL=$(echo "$RESULT" | jq -r '.analysis.rule_signal // "N/A"')
BUY_CONDITIONS=$(echo "$RESULT" | jq -r '.analysis.buy_conditions // "-" | if . == null then "-" else "\(.)/4" end')
SELL_CONDITIONS=$(echo "$RESULT" | jq -r '.analysis.sell_conditions // "-" | if . == null then "-" else "\(.)/4" end')
TREND_1H=$(echo "$RESULT" | jq -r '.analysis.trend_1h // "N/A"')
TREND_4H=$(echo "$RESULT" | jq -r '.analysis.trend_4h // "N/A"')
VOLATILITY=$(echo "$RESULT" | jq -r '.analysis.volatility // "N/A"')

# Extract AI analysis
AI_DECISION=$(echo "$RESULT" | jq -r '.ai_analysis.decision // "N/A"')
AI_CONFIDENCE=$(echo "$RESULT" | jq -r '.ai_analysis.confidence // 0')
AI_SUMMARY=$(echo "$RESULT" | jq -r '.ai_analysis.summary // ""')
AI_RISK=$(echo "$RESULT" | jq -r '.ai_analysis.risk // "N/A"')

# Price
BID=$(echo "$RESULT" | jq -r '.price.bid // "N/A"')
ASK=$(echo "$RESULT" | jq -r '.price.ask // "N/A"')

# SL/TP
SL_TP_ENABLED=$(echo "$RESULT" | jq -r '.sl_tp.enabled // false')
SL_PRICE=$(echo "$RESULT" | jq -r '.sl_tp.stop_loss // null')
TP_PRICE=$(echo "$RESULT" | jq -r '.sl_tp.take_profit // null')
SL_TP_SOURCE=$(echo "$RESULT" | jq -r '.sl_tp.source // null')
SL_TP_REASONING=$(echo "$RESULT" | jq -r '.sl_tp.reasoning // null')

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

# Truncate long text for Discord limits
AI_SUMMARY_SHORT="${AI_SUMMARY:0:200}"

# Build SL/TP display string
if [[ "$SL_TP_ENABLED" == "true" && "$SL_PRICE" != "null" && "$TP_PRICE" != "null" ]]; then
    if [[ "$SL_TP_SOURCE" == "ai" ]]; then
        SL_TP_VALUE="🤖 AI\nSL: ${SL_PRICE}\nTP: ${TP_PRICE}"
    else
        SL_TP_VALUE="📊 ATR\nSL: ${SL_PRICE}\nTP: ${TP_PRICE}"
    fi
else
    SL_TP_VALUE="-"
fi

PAYLOAD=$(jq -n \
    --arg emoji "$EMOJI" \
    --arg decision "$DECISION" \
    --arg symbol "$SYMBOL" \
    --arg strategy "$STRATEGY" \
    --arg action "${ACTION:-"-"}" \
    --arg amount "$AMOUNT" \
    --arg rsi "$RSI" \
    --arg rule_signal "$RULE_SIGNAL" \
    --arg buy_conditions "$BUY_CONDITIONS" \
    --arg sell_conditions "$SELL_CONDITIONS" \
    --arg trend_1h "$TREND_1H" \
    --arg trend_4h "$TREND_4H" \
    --arg volatility "$VOLATILITY" \
    --arg ai_decision "$AI_DECISION" \
    --arg ai_confidence "$AI_CONFIDENCE" \
    --arg ai_summary "$AI_SUMMARY_SHORT" \
    --arg ai_risk "$AI_RISK" \
    --arg bid "$BID" \
    --arg ask "$ASK" \
    --arg sl_tp "$SL_TP_VALUE" \
    --argjson color "$COLOR" \
    --arg timestamp "$TIMESTAMP" \
    '{
        embeds: [{
            title: "\($emoji) Auto Trade: \($symbol)",
            description: $ai_summary,
            color: $color,
            fields: [
                {
                    name: "📊 判断",
                    value: "**\($decision)** (確信度: \($ai_confidence)%)",
                    inline: true
                },
                {
                    name: "🎯 アクション",
                    value: (if $action == "-" or $action == "null" then "-" else $action end),
                    inline: true
                },
                {
                    name: "🧠 戦略",
                    value: $strategy,
                    inline: true
                },
                {
                    name: "📈 テクニカル",
                    value: "RSI: \($rsi)\nルール: \($rule_signal)\nBuy条件: \($buy_conditions) / Sell条件: \($sell_conditions)",
                    inline: true
                },
                {
                    name: "📉 トレンド",
                    value: "1h: \($trend_1h)\n4h: \($trend_4h)\nボラ: \($volatility)",
                    inline: true
                },
                {
                    name: "⚠️ リスク",
                    value: $ai_risk,
                    inline: true
                },
                {
                    name: "💰 価格",
                    value: "Bid: \($bid)\nAsk: \($ask)",
                    inline: true
                },
                {
                    name: "🛡️ SL/TP",
                    value: $sl_tp,
                    inline: true
                }
            ],
            timestamp: $timestamp
        }]
    }')

# Determine which webhook to use
if [[ "$DECISION" == "go" && -n "$DISCORD_ENTRY_WEBHOOK_URL" ]]; then
    TARGET_WEBHOOK="$DISCORD_ENTRY_WEBHOOK_URL"
    WEBHOOK_TYPE="entry"
else
    TARGET_WEBHOOK="$DISCORD_WEBHOOK_URL"
    WEBHOOK_TYPE="default"
fi

# Send to Discord
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$TARGET_WEBHOOK")

if [[ "$RESPONSE" == "204" || "$RESPONSE" == "200" ]]; then
    echo "Discord notification sent successfully ($WEBHOOK_TYPE)" >&2
else
    echo "Failed to send Discord notification (HTTP $RESPONSE)" >&2
fi
