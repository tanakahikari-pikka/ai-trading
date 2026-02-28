# AI分析レスポンス仕様書

## 概要

AIはテクニカル指標を分析し、売買判断とSL/TP価格を提案する。

## 設計思想

1. **シンプルさ**: 必要な情報のみ出力し、トークン消費を最小化
2. **具体性**: SL/TP価格は明確なルールに基づいて計算
3. **判断の透明性**: なぜその判断になったか、根拠を明示

---

## AI出力フォーマット

```json
{
  "decision": {
    "action": "go | not_order",
    "direction": "Buy | Sell | null",
    "confidence": 0-100,
    "summary": "判断理由（1文）"
  },

  "analysis": {
    "technical": {
      "rsi": "RSI値と状態の説明",
      "macd": "MACDの状態説明",
      "bollinger": "BB位置の説明",
      "trend": "トレンド状況"
    },
    "risk": {
      "level": "low | medium | high",
      "factors": ["要因1", "要因2"]
    }
  },

  "sl_tp": {
    "stop_loss": number,
    "take_profit": number,
    "reasoning": "設定根拠（1文）"
  }
}
```

---

## 各セクションの詳細

### 1. decision（判断）

| フィールド | 説明 |
|-----------|------|
| action | `go`（発注）または `not_order`（見送り） |
| direction | 発注方向。`go`の場合は `Buy` または `Sell`、`not_order`の場合は `null` |
| confidence | 判断の確信度（0-100%） |
| summary | 判断理由の1文要約 |

### 2. analysis（分析）

#### technical（テクニカル分析）

各指標の現在値と状態を簡潔に説明。

| フィールド | 説明 |
|-----------|------|
| rsi | RSI値と状態（例: "RSI 35で売られすぎゾーン"） |
| macd | MACDの状態（例: "MACDがシグナルを上抜け"） |
| bollinger | BB位置（例: "価格がBB下限付近"） |
| trend | トレンド状況（例: "1h/4h共に上昇トレンド"） |

#### risk（リスク評価）

| フィールド | 説明 |
|-----------|------|
| level | リスクレベル（low/medium/high） |
| factors | 具体的なリスク要因のリスト |

### 3. sl_tp（損切り・利確価格）

**エントリー時に使用する実際の価格値を提案する。**

| フィールド | 型 | 説明 |
|-----------|-----|------|
| stop_loss | number | 損切り価格（実際の値） |
| take_profit | number | 利確価格（実際の値） |
| reasoning | string | 設定根拠の説明（1文） |

#### SL/TP計算ルール

1. **基本計算**:
   - SL距離 = ATR × 1.5
   - TP距離 = SL距離 × 2.0 (RR 1:2)

2. **価格計算**:
   - Buy: stop_loss = entry - SL距離, take_profit = entry + TP距離
   - Sell: stop_loss = entry + SL距離, take_profit = entry - TP距離

3. **調整ルール**:
   - Buy: SLが直近安値より上なら、直近安値の少し下に調整
   - Sell: SLが直近高値より下なら、直近高値の少し上に調整

4. **制約**: 調整後もRR比 1.5以上を維持

#### フォールバック

AI が `sl_tp` を提案しない場合、静的計算にフォールバック：
- SL: ATR × 1.5
- TP: SL幅 × 2.0（リスクリワード 1:2）

---

## 判断基準

### エントリー条件

**Buy シグナル (すべて満たす必要あり)**:
- RSI < rsi_buy_threshold (通常40, 高ボラ時30)
- %B < 30 (BB下限付近)
- MACD > Signal (ゴールデンクロス)

**Sell シグナル (すべて満たす必要あり)**:
- RSI > rsi_sell_threshold (通常60, 高ボラ時70)
- %B > 70 (BB上限付近)
- MACD < Signal (デッドクロス)

### フィルター

| 条件 | 結果 |
|------|------|
| atr_ratio < 0.7 | not_order (ボラ不足) |
| atr_ratio > 3.0 | not_order (異常ボラ) |
| rule_signal = "Wait" | 基本 not_order |
| 1hと4hトレンド不一致 | confidence -20 |

---

## 入力データ形式

AIには以下のJSON形式でデータが提供される:

```json
{
  "symbol": "USDJPY",
  "current_price": { "bid": 150.123, "ask": 150.126 },
  "timeframes": {
    "1h": {
      "indicators": {
        "rsi_14": 45.2,
        "sma_20": 150.05,
        "sma_50": 149.80,
        "macd": { "macd": 0.02, "signal": 0.01, "histogram": 0.01 },
        "bollinger": { "upper": 150.50, "middle": 150.05, "lower": 149.60, "percent_b": 52.3 },
        "atr": { "value": 0.25, "percent": 0.17, "atr_ratio": 1.2 }
      },
      "rule_analysis": { "signal": "Buy", "trend": "上昇" },
      "recent_prices": [149.80, 149.90, 150.00, ...]
    },
    "4h": {
      "indicators": { ... },
      "rule_analysis": { "signal": "Wait", "trend": "上昇" }
    }
  },
  "summary": {
    "rule_signal": "Buy",
    "trend_1h": "上昇",
    "trend_4h": "上昇"
  }
}
```

---

## Discord通知での表示

Discord通知では、以下を優先的に表示：

1. **判断**: decision.action + decision.summary
2. **テクニカル**: RSI、MACD、トレンド
3. **リスク**: analysis.risk.level + factors
4. **SL/TP**: sl_tp.stop_loss / sl_tp.take_profit

---

## 変更履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-02-27 | 初版作成。教育的フィードバック付きAIレスポンス仕様を定義 |
| 2026-02-27 | `sl_tp` セクション追加。AI による動的 SL/TP 提案機能 |
| 2026-03-01 | volatilityに `atr_ema`, `atr_ratio` 追加。相対ボラティリティスコア対応 |
| 2026-03-01 | スキーマ簡素化。`learning`, `raw_data`, `action_guide` を削除。トークン消費削減 |
