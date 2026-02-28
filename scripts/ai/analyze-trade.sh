#!/bin/bash
# AI Trade Analysis
# Usage: echo "$MARKET_DATA_JSON" | analyze-trade.sh
# Input: Comprehensive JSON with multi-timeframe indicators
# Output: Decision JSON with analysis and SL/TP

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

# Load system prompt from file
SYSTEM_PROMPT_FILE="$SCRIPT_DIR/prompts/system.txt"
if [[ ! -f "$SYSTEM_PROMPT_FILE" ]]; then
    echo "Error: System prompt file not found: $SYSTEM_PROMPT_FILE" >&2
    exit 1
fi
SYSTEM_PROMPT=$(cat "$SYSTEM_PROMPT_FILE")

# Build user prompt - pass market data directly as JSON
USER_PROMPT="以下の市場データを分析し、売買判断とSL/TP価格を提案してください。

$MARKET_DATA"

echo "Calling OpenAI API for analysis..." >&2

# Build request using jq for proper JSON escaping
REQUEST_JSON=$(jq -n \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_PROMPT" \
    '{
        model: "gpt-4o-mini",
        messages: [
            {role: "system", content: $system},
            {role: "user", content: $user}
        ],
        max_tokens: 800,
        temperature: 0.2
    }')

RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "$REQUEST_JSON")

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

# Clean up potential markdown formatting
CONTENT=$(echo "$CONTENT" | sed 's/```json//g' | sed 's/```//g')

# Validate JSON
if ! echo "$CONTENT" | jq . > /dev/null 2>&1; then
    echo "Warning: Invalid JSON from API, attempting to fix..." >&2
    # Try to extract JSON object
    CONTENT=$(echo "$CONTENT" | grep -o '{.*}' | head -1)
fi

echo "" >&2
echo "=== AI Analysis ===" >&2
echo "$CONTENT" | jq -r '.decision.summary // "Analysis complete"' >&2

# Output the JSON
echo "$CONTENT"
