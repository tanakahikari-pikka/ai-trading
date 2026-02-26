---
description: 銘柄の市場分析（価格履歴・テクニカル指標）を実行
allowed-tools: Bash(*), Read, AskUserQuestion
---

# Saxo Bank Market Analysis

このスキルは銘柄の市場分析を行う：

1. 銘柄選択
2. 価格履歴取得（Yahoo Finance API）
3. リアルタイム価格取得（Saxo Bank API）
4. テクニカル指標計算（RSI）
5. 分析結果表示

## 実行手順

### Step 1: 銘柄選択

AskUserQuestion で分析対象を確認：
- 通貨ペア（EUR, USD, JPY関連）
- ゴールド（GC=F, XAUUSD）
- 株価指数（^DJI, ^GSPC）

**シンボルマッピング:**
- Gold: Yahoo=`GC=F`, Saxo=`XAUUSD`(UIC:8176)
- EUR/USD: Yahoo=`EURUSD=X`, Saxo=`EURUSD`(UIC:21)
- USD/JPY: Yahoo=`USDJPY=X`, Saxo=`USDJPY`(UIC:31)
- GBP/USD: Yahoo=`GBPUSD=X`, Saxo=`GBPUSD`(UIC:31)

### Step 2: 価格履歴取得

Yahoo Finance APIで価格履歴を取得：
```bash
./scripts/yahoo-finance/get-chart.sh <yahoo_symbol> 1h 10d
```

### Step 3: テクニカル指標計算

RSI(14)を計算：
```bash
./scripts/yahoo-finance/get-chart.sh <symbol> 1h 10d | ./scripts/indicators/rsi.sh 14
```

### Step 4: リアルタイム価格取得（Saxo）

Saxo Bank APIで現在価格を取得：
```bash
./scripts/saxo/get-prices.sh "<account_key>" "<uic>" FxSpot
```

AccountKeyは `./scripts/saxo/get-accounts.sh` で取得。

### Step 5: 分析結果表示

以下の情報をユーザーに表示：

```
=== [銘柄名] 市場分析 ===

【現在価格】
  Bid: xxx / Ask: xxx
  スプレッド: xxx

【テクニカル指標】
  RSI(14): xx.x (買われすぎ/売られすぎ/中立)

【価格推移（直近）】
  高値: xxx
  安値: xxx
  変動幅: xxx

【シグナル】
  RSI判定: Buy / Sell / Wait
```

## スクリプトの場所

- `scripts/yahoo-finance/get-chart.sh` - 価格履歴取得
- `scripts/indicators/rsi.sh` - RSI計算
- `scripts/saxo/get-prices.sh` - リアルタイム価格
- `scripts/saxo/get-accounts.sh` - アカウント情報

## 注意事項

- 価格履歴はYahoo Finance（外部API）を使用
- Saxo Bank simはChart APIが利用不可のため
- シンボルの対応付けに注意
