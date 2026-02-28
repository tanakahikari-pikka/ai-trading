# 売買ロジック・プレフィルターまとめ

## 1. プレフィルター（AI分析スキップ判定）

AI分析はコストがかかるため、明らかにトレードチャンスがない場合は事前にスキップする。

### スキップ条件

| # | 条件 | 判定値 | 理由 |
|---|------|--------|------|
| 1 | シグナルなし | `BUY_CONDITIONS < 2 AND SELL_CONDITIONS < 2` | Buy/Sell どちらも2/4条件未満で方向性がない |
| 2 | 低ボラティリティ | `VOLATILITY == "low"` | 値動きが小さく利益が出にくい |

### 判定ロジック

```
if BUY_CONDITIONS < 2 AND SELL_CONDITIONS < 2:
    → スキップ（方向性なし）

elif VOLATILITY == "low":
    → スキップ（値動き不足）

else:
    → AI分析実行
```

### 実装

`scripts/lib/prefilter.sh` の `check_prefilter()` 関数

---

## 2. テクニカル指標（ルールベース判断）

### 使用指標

| 指標 | パラメータ | 用途 |
|------|-----------|------|
| RSI | 14期間 | 過熱感（売られすぎ/買われすぎ） |
| SMA | 20, 50期間 | トレンド方向 |
| EMA | 12, 26期間 | トレンドの勢い（MACD算出用） |
| MACD | 12, 26, 9 | トレンド転換・勢い |
| ボリンジャーバンド | 20期間, 2σ | ボラティリティ・過熱感 |
| ATR | 14期間 | ボラティリティ（SL/TP計算用） |

### Buy条件（4つ中2つ以上で発火）

| # | 条件 | 閾値 |
|---|------|------|
| 1 | RSI が売られ気味 | RSI < 40 |
| 2 | 上昇トレンド | 価格 > SMA(20) |
| 3 | 勢いあり | MACD > シグナルライン |
| 4 | BB下限付近 | 価格 < BB下限 + バンド幅×30% |

### Sell条件（4つ中2つ以上で発火）

| # | 条件 | 閾値 |
|---|------|------|
| 1 | RSI が買われ気味 | RSI > 60 |
| 2 | 下降トレンド | 価格 < SMA(20) |
| 3 | 勢い弱い | MACD < シグナルライン |
| 4 | BB上限付近 | 価格 > BB上限 - バンド幅×30% |

### MTFフィルター（マルチタイムフレーム確認）

上位トレンドに逆行するエントリーをブロックする。

| 方向 | 許可条件 |
|------|----------|
| Buy | SMA(20) > SMA(50)（上昇トレンド） |
| Sell | SMA(20) < SMA(50)（下降トレンド） |

### シグナル判定

```
if BUY_COUNT >= 2 AND BUY_COUNT > SELL_COUNT:
    if SMA(20) > SMA(50):  # MTFフィルター
        SIGNAL = "Buy"
    else:
        SIGNAL = "Wait"  # 上位トレンドに逆行
elif SELL_COUNT >= 2 AND SELL_COUNT > BUY_COUNT:
    if SMA(20) < SMA(50):  # MTFフィルター
        SIGNAL = "Sell"
    else:
        SIGNAL = "Wait"  # 上位トレンドに逆行
else:
    SIGNAL = "Wait"
```

### 実装

`scripts/indicators/analyze.sh`

---

## 3. AI分析

### 役割

- ルールベースで抽出された候補の最終確認
- コンテキスト分析（パターン認識、異常値検出）
- リスクが高い場合の拒否権（override）
- SL/TP の動的提案

### AI判断

| 出力 | 説明 |
|------|------|
| `action: "go"` | 発注を推奨 |
| `action: "not_order"` | 見送りを推奨 |
| `confidence: 0-100` | 確信度 |

### 実装

`scripts/ai/analyze-trade.sh`

---

## 4. 最終判断フロー

```
[Step 1] 価格履歴取得（Yahoo Finance）
    ↓
[Step 2] テクニカル分析（全指標計算）
    ↓
[Step 3] リアルタイム価格取得（Saxo Bank）
    ↓
[Step 4] 取引量計算（残高の10%）
    ↓
[Step 4.5] プレフィルター判定
    ├─ スキップ条件に該当 → not_order で終了
    └─ 通過 ↓
[Step 5] AI分析
    ↓
[Step 6] 最終判断
    ├─ RULE_SIGNAL == "Buy/Sell" AND AI == "go" → 発注実行
    └─ それ以外 → not_order
    ↓
[Step 7] SL/TP計算（発注時のみ）
    ↓
[Step 8] 発注実行（Saxo Bank API）
    ↓
[Step 9] Discord通知
```

### 最終判断ロジック

```
if RULE_SIGNAL in ["Buy", "Sell"]:
    if AI_DECISION == "go":
        → 発注実行
    else:
        → not_order（AIがオーバーライド）
else:
    → not_order
```

---

## 5. 判断例

| Buy条件 | Sell条件 | Volatility | RULE_SIGNAL | プレフィルター | AI分析 | 結果 |
|---------|----------|------------|-------------|----------------|--------|------|
| 1/4 | 1/4 | medium | Wait | スキップ | - | not_order |
| 2/4 | 1/4 | low | Buy | スキップ | - | not_order |
| 2/4 | 1/4 | medium | Buy | 通過 | go | **発注** |
| 2/4 | 1/4 | medium | Buy | 通過 | not_order | not_order |
| 2/4 | 2/4 | medium | Wait | 通過 | go | not_order* |
| 3/4 | 1/4 | high | Buy | 通過 | go | **発注** |

*同点の場合、RULE_SIGNAL が Wait なので発注されない

---

## 6. 通知

| 状況 | 送信先 |
|------|--------|
| エントリー (go) | `DISCORD_ENTRY_WEBHOOK_URL` |
| 見送り (not_order) | `DISCORD_WEBHOOK_URL` |

---

## 関連ファイル

| ファイル | 役割 |
|----------|------|
| `scripts/auto-trade.sh` | メインオーケストレーター |
| `scripts/lib/prefilter.sh` | プレフィルター関数 |
| `scripts/indicators/analyze.sh` | テクニカル分析 |
| `scripts/ai/analyze-trade.sh` | AI分析 |
| `scripts/notify/discord.sh` | Discord通知 |
| `rules/trading-rules.md` | 運用ルール詳細 |
