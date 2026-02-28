# AI分析レスポンス仕様書

## 概要

AIは単なる売買判断だけでなく、投資初心者が学習できる教育的フィードバックを提供する。

## 設計思想

1. **判断の透明性**: なぜその判断になったか、根拠を明示する
2. **一次情報の提示**: 生の数値データを見せて、自分で判断できる力を養う
3. **教育的要素**: 毎回1つのトピックを取り上げ、知識を積み上げる
4. **実践的ガイド**: 具体的な価格水準を提示し、実際のトレードをイメージできるようにする

---

## AI出力フォーマット

```json
{
  "decision": {
    "action": "go | not_order",
    "direction": "Buy | Sell | null",
    "confidence": 0-100,
    "summary": "判断の要約（1文）"
  },

  "raw_data": {
    "price": {
      "current": 156.11,
      "sma20": 156.06,
      "sma50": 156.11,
      "distance_from_sma20_pct": 0.03,
      "bb_upper": 156.32,
      "bb_middle": 156.06,
      "bb_lower": 155.80
    },
    "momentum": {
      "rsi": 54.5,
      "rsi_zone": "中立(40-60) | 売られすぎ(<30) | 買われすぎ(>70) | やや売られ(30-40) | やや買われ(60-70)",
      "macd": 0.02,
      "macd_signal": 0.018,
      "macd_histogram": 0.002,
      "macd_trend": "買い優勢 | 売り優勢 | 中立"
    },
    "volatility": {
      "atr": 0.21,
      "atr_ema": 0.19,
      "atr_ratio": 1.1,
      "atr_percent": 0.14,
      "level": "低い | 普通 | 高い",
      "interpretation": "ボラティリティに関する解釈"
    },
    "trend_alignment": {
      "trend_1h": "上昇 | 下降 | 横ばい",
      "trend_4h": "上昇 | 下降 | 横ばい",
      "aligned": true | false,
      "alignment_note": "一致/不一致の説明"
    }
  },

  "analysis": {
    "technical": {
      "rsi_reading": "RSIの現状と意味の解説",
      "macd_reading": "MACDの現状と意味の解説",
      "bollinger_reading": "ボリンジャーバンドの現状と意味の解説",
      "trend_reading": "トレンドの現状と意味の解説"
    },
    "risk_assessment": {
      "level": "low | medium | high",
      "factors": [
        "リスク要因1",
        "リスク要因2"
      ]
    },
    "opportunity": {
      "exists": true | false,
      "type": "トレンドフォロー | 逆張り | ブレイクアウト | なし",
      "description": "機会の説明"
    }
  },

  "learning": {
    "today_topic": "今日のトピック名",
    "explanation": "トピックの基本説明（初心者向け）",
    "key_levels": {
      "レベル1": "説明",
      "レベル2": "説明"
    },
    "today_example": "今回のデータを使った具体例",
    "terminology": {
      "term": "今日の用語",
      "definition": "用語の定義"
    },
    "next_step": "さらに学ぶためのヒント"
  },

  "action_guide": {
    "recommendation": "様子見 | エントリー検討可 | 好機",
    "if_entry": {
      "direction": "Buy | Sell",
      "entry_zone": "エントリー推奨価格帯",
      "stop_loss": "損切りライン（説明）",
      "take_profit": "利確ライン（説明）",
      "risk_reward_ratio": "リスクリワード比"
    },
    "wait_for": [
      "エントリー条件1",
      "エントリー条件2"
    ],
    "warning": "注意事項（あれば）"
  },

  "sl_tp": {
    "stop_loss": 155.50,
    "take_profit": 157.20,
    "reasoning": "SL/TP設定の根拠（1-2文）"
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

### 2. raw_data（一次情報）

生の数値データを提示。ユーザーが自分で判断できるよう、加工せずに見せる。

#### price（価格情報）
- 現在価格と移動平均線の関係
- ボリンジャーバンドの各ライン

#### momentum（モメンタム）
- RSI値とそのゾーン判定
- MACD、シグナルライン、ヒストグラム

#### volatility（ボラティリティ）
- ATR値とATR_EMA(50)
- atr_ratio: 相対ボラティリティスコア（ATR / ATR_EMA(50)、1.0 = 平均的）
- ボラティリティレベルの判定（atr_ratio基準: >1.5=高い, <0.7=低い）

#### trend_alignment（トレンド一致）
- 各時間軸のトレンド
- 一致しているかどうか

### 3. analysis（分析）

#### technical（テクニカル分析）
各指標の読み方を初心者向けに解説。

#### risk_assessment（リスク評価）
- リスクレベル（low/medium/high）
- 具体的なリスク要因のリスト

#### opportunity（機会評価）
- トレード機会の有無
- 機会のタイプ（トレンドフォロー、逆張り等）

### 4. learning（学習）

**毎回1つのトピックを取り上げる。**

トピックのローテーション例：
1. RSIの読み方
2. MACDの読み方
3. ボリンジャーバンドの使い方
4. トレンドの見方
5. サポート/レジスタンス
6. リスクリワード比
7. ポジションサイズ
8. 損切りの考え方
9. マルチタイムフレーム分析
10. ダイバージェンス

#### today_example
今回の実際のデータを使って、トピックを具体的に説明する。

#### terminology
関連する専門用語を1つ紹介し、定義を説明する。

### 5. action_guide（行動ガイド）

#### recommendation
- `様子見`: 明確なシグナルなし
- `エントリー検討可`: 条件が揃いつつある
- `好機`: 明確なエントリーポイント

#### if_entry
エントリーする場合の具体的な価格水準：
- **entry_zone**: エントリー推奨価格帯
- **stop_loss**: 損切りライン（必須）
- **take_profit**: 利確ライン
- **risk_reward_ratio**: リスクリワード比（最低1:1.5推奨）

#### wait_for
今はエントリーしない場合、何を待つべきか具体的に列挙。

### 6. sl_tp（損切り・利確価格）

**エントリー時に使用する実際の価格値を提案する。**

| フィールド | 型 | 説明 |
|-----------|-----|------|
| stop_loss | number | 損切り価格（実際の値） |
| take_profit | number | 利確価格（実際の値） |
| reasoning | string | 設定根拠の説明（1-2文） |

#### 設計思想

- AI にチャート分析を委ね、最適な SL/TP を判断させる
- モデルの精度向上に応じて、より良い SL/TP が提案されるようになる
- ルールを細かく指定せず、AI の判断力に依存する設計

#### AIが考慮すべき要素（参考）

AI は以下のような要素を総合的に判断して SL/TP を決定する：
- 直近のサポート/レジスタンスライン
- ボリンジャーバンドの位置
- 直近の高値/安値
- ATR（ボラティリティ）
- 価格構造（トレンドライン等）

#### フォールバック

AI が `sl_tp` を提案しない場合、静的計算にフォールバック：
- SL: ATR × 1.5
- TP: SL幅 × 2.0（リスクリワード 1:2）

---

## AIへの指示（プロンプト要件）

1. **初心者目線**: 専門用語を使う場合は必ず簡単な説明を添える
2. **具体的な数値**: 「高い」「低い」ではなく、具体的な数値と閾値を示す
3. **根拠の明示**: 判断には必ず理由を付ける
4. **教育的姿勢**: 単に答えを示すのではなく、考え方を教える
5. **実践的**: 具体的な価格水準を提示し、実際に使える情報にする

---

## Discord通知での表示

Discord通知では、以下を優先的に表示：

1. **判断**: decision.action + decision.summary
2. **一次データ**: RSI、MACD、トレンド
3. **リスク**: analysis.risk_assessment.level + factors
4. **今日の学び**: learning.today_topic + today_example
5. **次のアクション**: action_guide.wait_for

---

## 変更履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-02-27 | 初版作成。教育的フィードバック付きAIレスポンス仕様を定義 |
| 2026-02-27 | `sl_tp` セクション追加。AI による動的 SL/TP 提案機能 |
| 2026-03-01 | volatilityに `atr_ema`, `atr_ratio` 追加。相対ボラティリティスコア対応 |
