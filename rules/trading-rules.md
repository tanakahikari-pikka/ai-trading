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
| 4 | ボリンジャー下限付近 | 価格 < BB(-1σ) |

### Sell候補条件（2つ以上で発火）

| # | 条件 | 閾値 |
|---|------|------|
| 1 | RSI が買われ気味 | RSI > 60 |
| 2 | 下降トレンド確認 | 価格 < SMA(20) |
| 3 | 勢い弱い | MACD < シグナルライン |
| 4 | ボリンジャー上限付近 | 価格 > BB(+1σ) |

### 判断フロー

```
条件一致数 >= 2 → シグナル発火（Buy/Sell候補）
条件一致数 < 2  → Wait（見送り）
```

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

### 将来拡張: AI による動的調整

静的設定で動作確認後、AIからの判断で SL/TP 値を上書きする機能を追加予定：

```json
{
  "decision": {
    "action": "go",
    "direction": "Buy"
  },
  "sl_tp_override": {
    "stop_loss": 149.10,
    "take_profit": 152.00,
    "reason": "直近サポートライン考慮"
  }
}
```

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
