#!/bin/bash
# AI Trade Analysis with Educational Feedback
# Usage: echo "$MARKET_DATA_JSON" | analyze-trade.sh
# Input: Comprehensive JSON with multi-timeframe indicators
# Output: Educational JSON with analysis and learning points

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

# Extract key information for prompt
SYMBOL=$(echo "$MARKET_DATA" | jq -r '.symbol // "USDJPY"')
BID=$(echo "$MARKET_DATA" | jq -r '.current_price.bid // "N/A"')
ASK=$(echo "$MARKET_DATA" | jq -r '.current_price.ask // "N/A"')
RULE_SIGNAL=$(echo "$MARKET_DATA" | jq -r '.summary.rule_signal // "Wait"')
TREND_1H=$(echo "$MARKET_DATA" | jq -r '.summary.trend_1h // "N/A"')
TREND_4H=$(echo "$MARKET_DATA" | jq -r '.summary.trend_4h // "N/A"')

# Extract 1h indicators
RSI_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.rsi_14 // "N/A"')
SMA20_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.sma_20 // "N/A"')
SMA50_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.sma_50 // "N/A"')
MACD_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.macd.macd // "N/A"')
MACD_SIGNAL_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.macd.signal // "N/A"')
MACD_HIST_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.macd.histogram // "N/A"')
BB_UPPER_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.bollinger.upper // "N/A"')
BB_MIDDLE_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.bollinger.middle // "N/A"')
BB_LOWER_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.bollinger.lower // "N/A"')
BB_POSITION_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.bollinger.position // "N/A"')
ATR_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.atr.value // "N/A"')
ATR_PCT_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.atr.percent // "N/A"')
VOLATILITY_1H=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].indicators.atr.volatility // "N/A"')
BUY_CONDITIONS=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].rule_analysis.buy_conditions_met // 0')
SELL_CONDITIONS=$(echo "$MARKET_DATA" | jq -r '.timeframes["1h"].rule_analysis.sell_conditions_met // 0')

# Extract 4h indicators
RSI_4H=$(echo "$MARKET_DATA" | jq -r '.timeframes["4h"].indicators.rsi_14 // "N/A"')
TREND_4H_DETAIL=$(echo "$MARKET_DATA" | jq -r '.timeframes["4h"].rule_analysis.trend // "N/A"')

# Recent prices for context
RECENT_PRICES_1H=$(echo "$MARKET_DATA" | jq -c '.timeframes["1h"].recent_prices // []')

# Select today's learning topic (rotate based on hour)
HOUR=$(date +%H)
TOPICS=("RSIの読み方" "MACDの読み方" "ボリンジャーバンドの使い方" "トレンドの見方" "マルチタイムフレーム分析" "リスクリワード比" "損切りの考え方" "ポジションサイズ")
TOPIC_INDEX=$((10#$HOUR % ${#TOPICS[@]}))
TODAY_TOPIC="${TOPICS[$TOPIC_INDEX]}"

# Build comprehensive prompt
PROMPT="あなたは投資初心者を教育するFXトレードメンターです。
単に売買判断を伝えるだけでなく、なぜその判断になったか、今日学べることは何かを丁寧に説明してください。

## 市場データ
- 銘柄: $SYMBOL
- 現在価格: Bid $BID / Ask $ASK

## 1時間足テクニカル指標
- RSI(14): $RSI_1H
- SMA(20): $SMA20_1H
- SMA(50): $SMA50_1H
- MACD: $MACD_1H (Signal: $MACD_SIGNAL_1H, Histogram: $MACD_HIST_1H)
- ボリンジャーバンド: Upper $BB_UPPER_1H / Middle $BB_MIDDLE_1H / Lower $BB_LOWER_1H
- バンド位置: $BB_POSITION_1H
- ATR(14): $ATR_1H ($ATR_PCT_1H%)
- ボラティリティ: $VOLATILITY_1H
- Buy条件達成: $BUY_CONDITIONS/4
- Sell条件達成: $SELL_CONDITIONS/4
- ルールシグナル: $RULE_SIGNAL
- トレンド: $TREND_1H

## 4時間足
- RSI(14): $RSI_4H
- トレンド: $TREND_4H_DETAIL

## 直近価格（1h、24本）
$RECENT_PRICES_1H

## 今日の学習トピック
「$TODAY_TOPIC」について、今回のデータを使って説明してください。

## 出力形式
以下のJSON形式で回答してください。説明文は全て日本語で、初心者にわかりやすく書いてください。

{
  \"decision\": {
    \"action\": \"go または not_order\",
    \"direction\": \"Buy/Sell/null\",
    \"confidence\": 0-100の数値,
    \"summary\": \"判断理由を1文で（初心者向け）\"
  },
  \"raw_data\": {
    \"price\": {
      \"current\": 現在価格,
      \"sma20\": SMA20の値,
      \"sma50\": SMA50の値,
      \"distance_from_sma20_pct\": SMA20からの乖離率,
      \"bb_upper\": BB上限,
      \"bb_middle\": BB中央,
      \"bb_lower\": BB下限
    },
    \"momentum\": {
      \"rsi\": RSI値,
      \"rsi_zone\": \"中立(40-60)/売られすぎ(<30)/買われすぎ(>70)/やや売られ(30-40)/やや買われ(60-70)\",
      \"macd\": MACD値,
      \"macd_signal\": シグナル値,
      \"macd_histogram\": ヒストグラム値,
      \"macd_trend\": \"買い優勢/売り優勢/中立\"
    },
    \"volatility\": {
      \"atr\": ATR値,
      \"atr_percent\": ATRパーセント,
      \"level\": \"低い/普通/高い\",
      \"interpretation\": \"ボラティリティの解釈\"
    },
    \"trend_alignment\": {
      \"trend_1h\": \"1時間足トレンド\",
      \"trend_4h\": \"4時間足トレンド\",
      \"aligned\": true/false,
      \"alignment_note\": \"一致/不一致の説明\"
    }
  },
  \"analysis\": {
    \"technical\": {
      \"rsi_reading\": \"RSIの現状と意味（初心者向け解説）\",
      \"macd_reading\": \"MACDの現状と意味（初心者向け解説）\",
      \"bollinger_reading\": \"BBの現状と意味（初心者向け解説）\",
      \"trend_reading\": \"トレンドの現状と意味（初心者向け解説）\"
    },
    \"risk_assessment\": {
      \"level\": \"low/medium/high\",
      \"factors\": [\"リスク要因1\", \"リスク要因2\"]
    },
    \"opportunity\": {
      \"exists\": true/false,
      \"type\": \"トレンドフォロー/逆張り/ブレイクアウト/なし\",
      \"description\": \"機会の説明\"
    }
  },
  \"learning\": {
    \"today_topic\": \"$TODAY_TOPIC\",
    \"explanation\": \"トピックの基本説明（初心者向け、3-4文）\",
    \"key_levels\": {
      \"重要な水準1\": \"説明\",
      \"重要な水準2\": \"説明\"
    },
    \"today_example\": \"今回のデータを使った具体例（2-3文）\",
    \"terminology\": {
      \"term\": \"今日の用語\",
      \"definition\": \"用語の定義（1-2文）\"
    },
    \"next_step\": \"さらに学ぶためのヒント\"
  },
  \"action_guide\": {
    \"recommendation\": \"様子見/エントリー検討可/好機\",
    \"if_entry\": {
      \"direction\": \"Buy/Sell\",
      \"entry_zone\": \"エントリー推奨価格帯\",
      \"stop_loss\": \"損切りライン（説明）\",
      \"take_profit\": \"利確ライン（説明）\",
      \"risk_reward_ratio\": \"リスクリワード比\"
    },
    \"wait_for\": [\"エントリー条件1\", \"エントリー条件2\"],
    \"warning\": \"注意事項\"
  },
  \"sl_tp\": {
    \"stop_loss\": 損切り価格（数値）,
    \"take_profit\": 利確価格（数値）,
    \"reasoning\": \"SL/TP設定の根拠（1-2文）\"
  }
}

重要な注意:
- ルールシグナルがWaitの場合、基本的にnot_orderにする
- 1hと4hのトレンドが一致していない場合は慎重に判断
- 初心者にわかりやすい言葉で説明する
- 具体的な数値を使って説明する
- JSON以外のテキストは出力しない

sl_tp（損切り・利確価格）について:
- action が go の場合、必ず sl_tp に具体的な価格を設定する
- stop_loss は Buy なら現在価格より下、Sell なら現在価格より上に設定
- take_profit は Buy なら現在価格より上、Sell なら現在価格より下に設定
- 直近の高値/安値、サポート/レジスタンス、ボリンジャーバンドなどを考慮して最適な価格を判断
- reasoning にはなぜその価格を選んだか簡潔に説明
- action が not_order の場合、sl_tp は null でよい"

echo "Calling OpenAI API for educational analysis..." >&2

RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "$(jq -n \
        --arg prompt "$PROMPT" \
        '{
            model: "gpt-4o-mini",
            messages: [
                {role: "system", content: "You are an educational FX trading mentor for beginners. Always respond with valid JSON only in Japanese. Be clear, specific, and educational."},
                {role: "user", content: $prompt}
            ],
            max_tokens: 2000,
            temperature: 0.3
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

# Clean up potential markdown formatting
CONTENT=$(echo "$CONTENT" | sed 's/```json//g' | sed 's/```//g')

# Validate JSON
if ! echo "$CONTENT" | jq . > /dev/null 2>&1; then
    echo "Warning: Invalid JSON from API, attempting to fix..." >&2
    # Try to extract JSON object
    CONTENT=$(echo "$CONTENT" | grep -o '{.*}' | head -1)
fi

echo "" >&2
echo "=== AI Educational Analysis ===" >&2
echo "$CONTENT" | jq -r '.decision.summary // "Analysis complete"' >&2

# Output the JSON
echo "$CONTENT"
