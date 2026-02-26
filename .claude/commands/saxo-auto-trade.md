---
description: 市場分析に基づく自動判断トレード（ルールベース + AI分析）
allowed-tools: Bash(*), Read, AskUserQuestion
---

# Saxo Bank Auto Trade

このスキルは市場分析に基づいて自動的にエントリー判断を行い、注文発注を補助する：

1. 銘柄選択
2. データ取得（価格履歴 + リアルタイム価格）
3. テクニカル分析（RSI）
4. ルールベース判断（80%）
5. AI分析（20%）
6. 総合判断表示
7. ユーザー確認（通常モードのみ）
8. 注文発注

## 実行モード

| モード | 引数 | 説明 |
|--------|------|------|
| 通常 | なし | ユーザー確認あり、銘柄選択あり |
| 自動 | `--auto` | ユーザー確認なし、USD/JPY固定、残高10%発注 |

### --auto モード（GitHub Actions 用）

`--auto` が指定された場合：
- 銘柄: USD/JPY 固定
- 発注量: 残高の 10%
- ユーザー確認: スキップ
- 判断結果: JSON 出力
- `go` の場合は自動発注

**自動モードの判断結果 JSON:**
```json
{
  "decision": "go",
  "symbol": "USDJPY",
  "action": "Buy",
  "amount": 10000,
  "rsi": 28.5,
  "rule_signal": "Buy",
  "ai_analysis": {
    "trend": "下降トレンド終盤",
    "risk": "low",
    "comment": "反発の兆候あり"
  },
  "reason": "RSI=28.5 < 30, AI分析: 低リスク"
}
```

**自動モード実行フロー:**
```
1. USD/JPY のデータ取得
2. RSI 計算
3. AI 分析（トレンド・リスク）
4. 総合判断 → go / not_order
5. go なら残高10%で自動発注
6. 結果 JSON を出力
```

## 実行手順（通常モード）

### Step 1: 銘柄選択

AskUserQuestion でトレード対象を確認。
よく使う銘柄を選択肢として提示：
- Gold (XAUUSD)
- EUR/USD
- USD/JPY

### Step 2: データ取得

**価格履歴（Yahoo Finance）:**
```bash
CHART_DATA=$(./scripts/yahoo-finance/get-chart.sh <yahoo_symbol> 1h 10d)
```

**リアルタイム価格（Saxo）:**
```bash
ACCOUNT_KEY=$(./scripts/saxo/get-accounts.sh 2>/dev/null | jq -r '.accountKey')
PRICE_DATA=$(./scripts/saxo/get-prices.sh "$ACCOUNT_KEY" <uic> FxSpot)
```

### Step 3: テクニカル分析

**RSI計算:**
```bash
RSI_DATA=$(echo "$CHART_DATA" | ./scripts/indicators/rsi.sh 14)
```

RSI値とシグナルを取得：
- `rsi`: RSI値（0-100）
- `signal`: overbought / oversold / neutral
- `tradeSignal`: Buy / Sell / Wait

### Step 4: ルールベース判断（80%）

RSIに基づく判断ルール：

| RSI | 状態 | シグナル |
|-----|------|----------|
| > 70 | 買われすぎ | **Sell** |
| < 30 | 売られすぎ | **Buy** |
| 30-70 | 中立 | **Wait** |

### Step 5: AI分析（20%）

Claudeが以下を分析して補足意見を提供：

1. **価格トレンド**: 直近の高値・安値の推移
2. **ボラティリティ**: 価格変動の大きさ
3. **市場状況**: 特異なパターンがないか
4. **リスク**: エントリーのリスク要因

AI分析は参考情報として扱い、ルールベース判断を補完する。

### Step 6: 総合判断表示

```
=== [銘柄] トレード判断 ===

【市場データ】
  現在価格: Bid xxx / Ask xxx
  RSI(14): xx.x

【ルールベース判断】
  RSIシグナル: Buy / Sell / Wait
  判断根拠: RSI < 30 で売られすぎ

【AI分析】
  トレンド: 上昇/下降/横ばい
  補足意見: ...

【総合判断】
  推奨: Buy / Sell / Wait
  確信度: 高/中/低
```

### Step 7: ユーザー確認

AskUserQuestion で確認：
- 「この判断でエントリーしますか？」
- Buy/Sellの場合、数量も確認

### Step 8: 注文発注

ユーザーが承認した場合のみ発注：
```bash
./scripts/saxo/place-order.sh "$ACCOUNT_KEY" <uic> <BuySell> <amount> Market "" FxSpot
```

## シンボルマッピング

| 銘柄 | Yahoo | Saxo UIC |
|------|-------|----------|
| Gold | GC=F | 8176 |
| EUR/USD | EURUSD=X | 21 |
| USD/JPY | USDJPY=X | 42 |
| GBP/USD | GBPUSD=X | 31 |

## スクリプトの場所

- `scripts/yahoo-finance/get-chart.sh` - 価格履歴
- `scripts/indicators/rsi.sh` - RSI計算
- `scripts/saxo/get-accounts.sh` - アカウント情報
- `scripts/saxo/get-prices.sh` - リアルタイム価格
- `scripts/saxo/place-order.sh` - 注文発注

## 拡張性

テクニカル指標を追加する場合：
1. `scripts/indicators/` に新しいスクリプトを追加
2. 同じインターフェース（stdin: 価格JSON, stdout: 結果JSON）
3. このスキルでStep 3に組み込み

## 注意事項

- シミュレーション環境（/sim）で動作
- 最終判断は必ずユーザーが確認
- AI分析は参考情報（責任は取れない）
- RSI閾値（70/30）は調整可能
