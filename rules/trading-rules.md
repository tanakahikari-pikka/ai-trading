# USD/JPY 自動トレード運用ルール

## 概要

- **対象銘柄**: USD/JPY
- **実行頻度**: 1時間ごと
- **判断方式**: ハイブリッド（ルールベース候補抽出 + AI最終判断）

---

## データ取得

### 時間軸

| 時間軸 | 範囲 | ローソク足数 | 用途 |
|--------|------|-------------|------|
| 1h     | 10日 | 約240本     | 短期トレンド・エントリー判断 |
| 4h     | 30日 | 約180本     | 中期トレンド確認 |

### データソース

| ソース | 用途 |
|--------|------|
| Yahoo Finance API | 価格履歴（OHLC） |
| Saxo Bank API | リアルタイム価格・発注 |

---

## テクニカル指標

### 使用指標一覧

| 指標 | パラメータ | 用途 |
|------|-----------|------|
| RSI | 14期間 | 過熱感（売られすぎ/買われすぎ） |
| SMA | 20, 50期間 | トレンド方向 |
| EMA | 12, 26期間 | トレンドの勢い（MACD算出用） |
| MACD | 12, 26, 9 | トレンド転換・勢い |
| ボリンジャーバンド | 20期間, 2σ | ボラティリティ・過熱感 |
| ATR | 14期間 | ボラティリティ（ポジションサイズ計算用） |

---

## ルールベース判断

### Buy候補条件（2つ以上で発火）

| # | 条件 | 閾値 |
|---|------|------|
| 1 | RSI が売られ気味 | RSI < 40 |
| 2 | 上昇トレンド確認 | 価格 > SMA(20) |
| 3 | 勢いあり | MACD > シグナルライン |
| 4 | ボリンジャー下限付近 | 価格 < BB下限 + バンド幅×30% |

### Sell候補条件（2つ以上で発火）

| # | 条件 | 閾値 |
|---|------|------|
| 1 | RSI が買われ気味 | RSI > 60 |
| 2 | 下降トレンド確認 | 価格 < SMA(20) |
| 3 | 勢い弱い | MACD < シグナルライン |
| 4 | ボリンジャー上限付近 | 価格 > BB上限 - バンド幅×30% |

### MTFフィルター（マルチタイムフレーム確認）

条件を満たしても、上位トレンドに逆行するエントリーはブロックされる。

| 方向 | 許可条件 |
|------|----------|
| Buy | SMA(20) > SMA(50)（上昇トレンド） |
| Sell | SMA(20) < SMA(50)（下降トレンド） |

### 判断フロー

```
条件一致数 >= 2 → 候補
  ├─ MTFフィルター通過 → シグナル発火（Buy/Sell）
  └─ MTFフィルターでブロック → Wait
条件一致数 < 2  → Wait（見送り）
```

---

## プレフィルター（AI分析スキップ条件）

### 概要

AI分析はコストがかかるため、明らかにトレードチャンスがない場合は事前にスキップする。

### スキップ条件

| # | 条件 | 判定値 | 理由 |
|---|------|--------|------|
| 1 | シグナルなし | `BUY_CONDITIONS < 2 AND SELL_CONDITIONS < 2` | Buy/Sell どちらも2/4条件未満で方向性がない |
| 2 | 低ボラティリティ | `VOLATILITY == "low"` | 値動きが小さく利益が出にくい |

### 判定ロジック

```
if BUY_CONDITIONS < 2 AND SELL_CONDITIONS < 2:
    → AI分析スキップ（理由: 方向性なし）

elif VOLATILITY == "low":
    → AI分析スキップ（理由: 値動き不足）

else:
    → AI分析実行（どちらかが2/4以上）
```

### スキップ時の動作

| 項目 | 値 |
|------|-----|
| AI_DECISION | `not_order` |
| AI_CONFIDENCE | `0` |
| AI_SUMMARY | スキップ理由を表示 |
| FINAL_DECISION | `not_order` |

### 実装

`scripts/lib/prefilter.sh` の `check_prefilter()` 関数で判定。

---

## AI分析

### 役割

- ルールベースで抽出された候補の最終確認
- コンテキスト分析（ニュース、異常値、パターン認識）
- リスクが高い場合の拒否権（override）

### AIに渡す情報

```json
{
  "symbol": "USDJPY",
  "timeframes": {
    "1h": {
      "prices": { "open": [...], "high": [...], "low": [...], "close": [...] },
      "indicators": {
        "rsi_14": 42.5,
        "sma_20": 149.30,
        "sma_50": 148.90,
        "ema_12": 149.25,
        "ema_26": 149.10,
        "macd": { "macd": 0.15, "signal": 0.10, "histogram": 0.05 },
        "bollinger": { "upper": 150.20, "middle": 149.30, "lower": 148.40 },
        "atr_14": 0.45
      },
      "trend": "上昇"
    },
    "4h": { "..." }
  },
  "rule_analysis": {
    "buy_conditions_met": 2,
    "sell_conditions_met": 0,
    "signal": "Buy",
    "conditions": {
      "rsi_oversold": true,
      "above_sma20": true,
      "macd_bullish": false,
      "near_bb_lower": false
    }
  },
  "current_price": { "bid": 149.50, "ask": 149.52 }
}
```

### AI出力形式

```json
{
  "trend": "上昇/下降/横ばい",
  "risk": "high/medium/low",
  "comment": "補足コメント",
  "override": false,
  "final_decision": "go/not_order"
}
```

---

## 最終判断ロジック

```
if ルールベース == Wait:
    → 発注しない

if ルールベース == Buy/Sell:
    if AI.final_decision == "go":
        → 発注実行
    else:
        → 発注しない（AIがオーバーライド）
```

---

## ポジションサイズ

| 項目 | 設定 |
|------|------|
| 資金割合 | 残高の 10% |
| ATRによる調整 | 検討中（高ボラ時は縮小） |

---

## リスク管理

### 現状の制限

- 1回の取引で残高の10%まで
- AIによるリスク判断でのオーバーライド

---

## Stop Loss / Take Profit 設定

### 概要

エントリー時に自動でStop Loss（損切り）とTake Profit（利確）の関連注文を設定する。
ATR（Average True Range）を基準に動的に計算し、リスクリワード比 1:2 を維持する。

### 計算方式

| 項目 | 計算方法 | 例（USDJPY, ATR=0.50） |
|------|----------|------------------------|
| Stop Loss | エントリー価格 ± (ATR × 1.5) | Buy@150.00 → SL: 149.25 |
| Take Profit | エントリー価格 ± (SL幅 × 2.0) | TP: 151.50 |

### 方向による計算

**Buy の場合:**
```
SL価格 = エントリー価格 - (ATR × SL倍率)
TP価格 = エントリー価格 + (SL幅 × リスクリワード比)
```

**Sell の場合:**
```
SL価格 = エントリー価格 + (ATR × SL倍率)
TP価格 = エントリー価格 - (SL幅 × リスクリワード比)
```

### 設定パラメータ

| パラメータ | デフォルト値 | 説明 |
|-----------|-------------|------|
| `sl_tp.enabled` | `true` | SL/TP機能の有効/無効 |
| `sl_tp.stop_loss.mode` | `"atr"` | 計算モード（atr/pips/percentage） |
| `sl_tp.stop_loss.multiplier` | `1.5` | ATR倍率 |
| `sl_tp.take_profit.mode` | `"ratio"` | 計算モード（ratio/atr/pips/percentage） |
| `sl_tp.take_profit.value` | `2.0` | リスクリワード比 |

### 通貨設定例（config/currencies/*.json）

```json
{
  "symbol": "USDJPY",
  "sl_tp": {
    "enabled": true,
    "stop_loss": {
      "mode": "atr",
      "multiplier": 1.5
    },
    "take_profit": {
      "mode": "ratio",
      "value": 2.0
    }
  }
}
```

### Saxo Bank API 発注形式

エントリー注文と同時に `Orders` 配列で関連注文を設定：

```json
{
  "Amount": 10000,
  "BuySell": "Buy",
  "OrderType": "Market",
  "Uic": 42,
  "AssetType": "FxSpot",
  "ManualOrder": true,
  "OrderDuration": { "DurationType": "DayOrder" },
  "Orders": [
    {
      "BuySell": "Sell",
      "OrderPrice": 149.25,
      "OrderType": "Stop",
      "ManualOrder": true,
      "OrderDuration": { "DurationType": "GoodTillCancel" }
    },
    {
      "BuySell": "Sell",
      "OrderPrice": 151.50,
      "OrderType": "Limit",
      "ManualOrder": true,
      "OrderDuration": { "DurationType": "GoodTillCancel" }
    }
  ]
}
```

### AI による動的 SL/TP 調整

#### 設計思想

**「モデルの精度向上に成果が依存する」設計**

- AI にチャートデータと指標を渡し、最適な SL/TP を判断させる
- ルールを細かく指定せず、AI の分析力に委ねる
- モデルが賢くなれば、自然と良い SL/TP が提案されるようになる

#### AI レスポンス形式

```json
{
  "decision": {
    "action": "go",
    "direction": "Buy"
  },
  "sl_tp": {
    "stop_loss": 155.50,
    "take_profit": 157.20,
    "reasoning": "直近安値155.45の少し下にSL設定。BBアッパー157.30手前でTP。"
  }
}
```

#### AI への指示

```
エントリーする場合（action: go）、最適な Stop Loss と Take Profit の価格を提案してください。
チャートの形状、サポート/レジスタンス、ボラティリティなどを総合的に判断してください。
理由も簡潔に説明してください。
```

#### 処理フロー

```
1. AI が sl_tp.stop_loss と sl_tp.take_profit を提案
   ↓
2. 値が存在する場合 → AI 提案値を使用
   値がない/無効な場合 → 静的計算（ATR基準）にフォールバック
   ↓
3. 発注時に SL/TP を設定
```

#### フォールバック条件

以下の場合は静的計算（ATR × 1.5, リスクリワード 1:2）を使用：
- AI が `sl_tp` を返さない
- `stop_loss` または `take_profit` が null/undefined
- 値が現在価格に対して不合理（SL が TP より遠い等）

### 今後検討

- 日次/週次の損失上限
- 連続損失時の休止ルール
- トレーリングストップ対応

---

## 実行スケジュール

| 項目 | 設定 |
|------|------|
| 実行頻度 | 1時間ごと |
| 実行環境 | GitHub Actions |
| 通知 | Discord Webhook |

---

## 関連ドキュメント

- [AI分析レスポンス仕様書](./ai-response-spec.md) - AIの出力フォーマットと教育的フィードバックの詳細

---

## 変更履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-02-27 | 初版作成。ルールベース強化 + AI情報強化の設計を記載 |
| 2026-02-27 | AI分析レスポンス仕様書を追加。教育的フィードバック機能を定義 |
| 2026-02-27 | Stop Loss / Take Profit 仕様を追加。ATR基準 × リスクリワード 1:2 |
| 2026-02-27 | AI による動的 SL/TP 調整仕様を追加。モデル依存設計 |
| 2026-02-28 | プレフィルター仕様を追加。AI分析スキップ条件を定義 |
| 2026-02-28 | BB条件の矛盾修正（中央線→下限バンド付近）、MTFフィルター追加 |
