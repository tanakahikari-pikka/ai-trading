#!/bin/bash
# AI Trade Analysis using OpenAI API (ChatGPT)
# Usage: echo "$MARKET_DATA_JSON" | analyze-trade.sh
# Input: JSON with rsi, price, symbol
# Output: JSON with AI analysis

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Load .env
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "Error: OPENAI_API_KEY not found in .env" >&2
    exit 1
fi

# Read market data from stdin
MARKET_DATA=$(cat)

RSI=$(echo "$MARKET_DATA" | jq -r '.rsi // "N/A"')
BID=$(echo "$MARKET_DATA" | jq -r '.bid // "N/A"')
ASK=$(echo "$MARKET_DATA" | jq -r '.ask // "N/A"')
SYMBOL=$(echo "$MARKET_DATA" | jq -r '.symbol // "USDJPY"')
RULE_SIGNAL=$(echo "$MARKET_DATA" | jq -r '.rule_signal // "Wait"')

# Build prompt
PROMPT="あなたはFXトレードアナリストです。以下の市場データを分析し、トレード判断を補助してください。

## 市場データ
- 銘柄: $SYMBOL
- 現在価格: Bid $BID / Ask $ASK
- RSI(14): $RSI
- ルールベースシグナル: $RULE_SIGNAL

## 分析してほしい項目
1. トレンド分析（上昇/下降/横ばい）
2. リスク評価（high/medium/low）
3. 補足コメント

## 出力形式
以下のJSON形式のみで回答してください。説明文は不要です。
{
  \"trend\": \"上昇/下降/横ばい\",
  \"risk\": \"high/medium/low\",
  \"comment\": \"補足コメント\",
  \"override\": false,
  \"final_decision\": \"go/not_order\"
}

注意:
- RSI > 70 で Sell シグナル、RSI < 30 で Buy シグナルがルールです
- ルールベースが Wait の場合、通常は not_order です
- 明確なリスクがある場合のみ override: true で判断を覆せます"

echo "Calling OpenAI API for analysis..." >&2

RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "$(jq -n \
        --arg prompt "$PROMPT" \
        '{
            model: "gpt-4o-mini",
            messages: [
                {role: "user", content: $prompt}
            ],
            max_tokens: 500
        }')")

# Check for error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "API Error:" >&2
    echo "$RESPONSE" | jq '.error' >&2
    exit 1
fi

# Extract content
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [[ -z "$CONTENT" ]]; then
    echo "Error: Empty response from API" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

echo "" >&2
echo "=== AI Analysis (ChatGPT) ===" >&2
echo "$CONTENT" >&2

# Output the JSON
echo "$CONTENT"
