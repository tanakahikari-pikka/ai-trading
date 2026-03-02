# 売買ロジック・プレフィルターまとめ

## 1. プレフィルター（AI分析スキップ判定）

AI分析はコストがかかるため、明らかにトレードチャンスがない場合は事前にスキップする。

### スキップ条件

| # | 条件 | 判定値 | 理由 |
|---|------|--------|------|
| 1 | シグナルなし | `BUY_CONDITIONS < 2 AND SELL_CONDITIONS < 2` | Buy/Sell どちらも2/3条件未満で方向性がない |
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

> **Note:** 低ボラ判定（`VOLATILITY == "low"` = `atr_ratio < 0.7`）はATRフィルターと重複するが、これは意図的な防御的設計。`analyze.sh`が単独で呼ばれるケースに対応するため、両方でガードしている。

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
| ATR | 14期間 | ボラティリティ（SL/TP計算、相対ATR比率でフィルタ） |

### カテゴリ分割方式

条件を「位置系」と「勢い系」に分類。位置系ANY（1/2）で発火、勢い系はオプショナル。

### Buy条件

**発火: 位置系ANY（1/2）、勢い系オプショナル**

| カテゴリ | 条件 | 閾値 | 必須 |
|----------|------|------|:----:|
| 位置系 | RSI が売られ気味 | RSI < RSI_BUY_THRESHOLD（動的） | どちらか1つ |
| 位置系 | BB下限付近 | %B < 30 | どちらか1つ |
| 勢い系 | MACDフレッシュモメンタム | MACD > Signal AND (フレッシュクロス5本以内 OR hist3本連続増加) | オプション |

### Sell条件

**発火: 位置系ANY（1/2）、勢い系オプショナル**

| カテゴリ | 条件 | 閾値 | 必須 |
|----------|------|------|:----:|
| 位置系 | RSI が買われ気味 | RSI > RSI_SELL_THRESHOLD（動的） | どちらか1つ |
| 位置系 | BB上限付近 | %B > 70 | どちらか1つ |
| 勢い系 | MACDフレッシュモメンタム | MACD < Signal AND (フレッシュクロス5本以内 OR hist3本連続減少) | オプション |

### %B（ボリンジャーバンド位置）

%B = (価格 - BB下限) / バンド幅 × 100（0=下限、50=中央、100=上限）

### RSI動的閾値

| 条件 | Buy閾値 | Sell閾値 |
|------|---------|----------|
| atr_ratio > 1.5（高ボラ） | 30 | 70 |
| atr_ratio <= 1.5（通常） | 40 | 60 |

### MTFフィルター（マルチタイムフレーム確認）

**4h足**のトレンドで上位方向を確認し、逆行エントリーをブロックする。
ただし、**横ばい（SMA差が0.1%以内）の場合は許容**される。

| 方向 | 許可条件（4h足） |
|------|------------------|
| Buy | 4h SMA(20) > 4h SMA(50)（上昇トレンド）**または横ばい** |
| Sell | 4h SMA(20) < 4h SMA(50)（下降トレンド）**または横ばい** |

**設計根拠:**
- 1h足のMACD条件とMTFフィルターが重複していた問題を解消
- 本来のMTF（上位時間軸確認）の意図を正しく実装
- 1hでは短期的に買いシグナルが出ても、4hが下降トレンドならブロック
- **横ばい許容**: 4hが明確なトレンドでない場合は1hシグナルを尊重

### ATRフィルター（異常ボラ抑制）

異常なボラティリティ環境ではシグナルを抑制：

| 条件 | 動作 |
|------|------|
| atr_ratio < 0.7 | Signal = "Wait" に強制変更（低ボラ / レンジ相場） |
| atr_ratio > 3.0 | Signal = "Wait" に強制変更（極端高ボラ / スプレッド・スリッページリスク） |

### シグナル判定

**Step 1: 1h足分析（analyze.sh）**
```
# ATRフィルター（異常ボラ抑制）
if atr_ratio < 0.7:
    SIGNAL = "Wait"  # 低ボラ = レンジ相場の可能性
elif atr_ratio > 3.0:
    SIGNAL = "Wait"  # 極端高ボラ = スプレッド拡大・スリッページリスク

# BBスクイーズフィルター（ボラティリティ収縮検出）
elif band_width_pct < 2.0 AND 0.7 <= atr_ratio < 1.0:
    SIGNAL = "Wait"  # スクイーズ状態 = 方向性不明確

# 位置系ANY（1/2）、勢い系オプショナル
elif (BUY_RSI OR BUY_BB):  # 位置系どちらか1つでOK
    if not (SELL_RSI OR SELL_BB):  # Sellの位置系と競合しない
        SIGNAL = "Buy"  # MTFフィルターは後段で適用

elif (SELL_RSI OR SELL_BB):  # 位置系どちらか1つでOK
    SIGNAL = "Sell"  # MTFフィルターは後段で適用

else:
    SIGNAL = "Wait"
```

**Step 2: MTFフィルター（auto-trade.sh）**
```
# 4h足のSMA20 vs SMA50 でフィルター（横ばい0.1%以内は許容）
SMA_DIFF_PCT = (4h_SMA20 - 4h_SMA50) / 4h_SMA50 * 100
IS_SIDEWAYS = |SMA_DIFF_PCT| <= 0.1

if RULE_SIGNAL == "Buy":
    if 4h_SMA20 > 4h_SMA50 OR IS_SIDEWAYS:  # 上昇トレンドまたは横ばい
        → 通過
    else:
        → Wait（上位トレンドに逆行）

elif RULE_SIGNAL == "Sell":
    if 4h_SMA20 < 4h_SMA50 OR IS_SIDEWAYS:  # 下降トレンドまたは横ばい
        → 通過
    else:
        → Wait（上位トレンドに逆行）
```

### 実装

- 1h分析: `scripts/indicators/analyze.sh`
- MTFフィルター: `scripts/auto-trade.sh`

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
| 1/3 | 1/3 | medium | Wait | スキップ | - | not_order |
| 2/3 | 1/3 | low | Buy | スキップ | - | not_order |
| 2/3 | 1/3 | medium | Buy | 通過 | go | **発注** |
| 2/3 | 1/3 | medium | Buy | 通過 | not_order | not_order |
| 2/3 | 2/3 | medium | Wait | 通過 | go | not_order* |
| 3/3 | 1/3 | high | Buy | 通過 | go | **発注** |

*同点の場合、RULE_SIGNAL が Wait なので発注されない

---

## 6. 通知

| 状況 | 送信先 |
|------|--------|
| エントリー (go) | `DISCORD_ENTRY_WEBHOOK_URL` |
| 見送り (not_order) | `DISCORD_WEBHOOK_URL` |

---

## 7. ボラティリティ判定基準

**相対ATR比率**（ATR / ATR_EMA(50)）で評価：

| 出力値 | 説明 |
|--------|------|
| `atr_ratio` | 連続値スコア（1.0 = 平均的） |

後方互換用ラベル：

| レベル | 条件 | 動作 |
|--------|------|------|
| high | atr_ratio > 1.5 | AI分析実行 |
| medium | 0.7 ≤ atr_ratio ≤ 1.5 | AI分析実行 |
| low | atr_ratio < 0.7 | プレフィルターでスキップ |

---

## 8. 環境変数

| 変数 | 説明 |
|------|------|
| `SAXO_ACCESS_TOKEN` | Saxo Bank API トークン |
| `OPENAI_API_KEY` | OpenAI API キー |
| `DISCORD_WEBHOOK_URL` | Discord通知（見送り用） |
| `DISCORD_ENTRY_WEBHOOK_URL` | Discord通知（エントリー用） |

---

## 関連ファイル

| ファイル | 役割 |
|----------|------|
| `scripts/auto-trade.sh` | メインオーケストレーター |
| `scripts/lib/prefilter.sh` | プレフィルター関数 |
| `scripts/indicators/analyze.sh` | テクニカル分析 |
| `scripts/ai/analyze-trade.sh` | AI分析 |
| `scripts/notify/discord.sh` | Discord通知 |
| `scripts/config/currencies/*.json` | 通貨ペア設定 |
| `rules/trading-rules.md` | 運用ルール詳細 |
