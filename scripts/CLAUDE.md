# scripts/ - マルチ通貨自動トレードシステム

## 概要

複数通貨ペア対応の自動トレードシステム。テクニカル指標（RSI, MACD, ボリンジャーバンド, ATR）+ AI分析で判断し、Saxo Bank API で発注。教育的フィードバック機能付き。

## 開発ルール

### 取引ロジック変更時の手順

**重要**: 取引ロジック（エントリー条件、フィルター、SL/TP等）を変更する際は、必ず以下の順序で行うこと。

1. **先に `rules/` ドキュメントを更新**
   - `rules/trading-rules.md` - 運用ルール詳細
   - `rules/trading-logic-summary.md` - ロジックまとめ
2. **その後にコードを実装**
   - `scripts/indicators/analyze.sh` - テクニカル分析
   - `scripts/lib/prefilter.sh` - プレフィルター
   - `scripts/auto-trade.sh` - メインロジック

ドキュメント先行で設計を明確にしてから実装する。

## 対応通貨ペア

| シンボル | 名称 | 説明 |
|----------|------|------|
| USDJPY | USD/JPY | 米ドル/日本円 |
| EURUSD | EUR/USD | ユーロ/米ドル |
| GBPUSD | GBP/USD | 英ポンド/米ドル |
| GBPJPY | GBP/JPY | 英ポンド/日本円 |
| EURJPY | EUR/JPY | ユーロ/日本円 |
| AUDUSD | AUD/USD | 豪ドル/米ドル |
| XAUUSD | XAU/USD | 金/米ドル (Gold) |
| USDCAD | USD/CAD | 米ドル/カナダドル |
| XPTUSD | XPT/USD | プラチナ/米ドル (Platinum) |

## ディレクトリ構成

| ディレクトリ | 責務 |
|--------------|------|
| `ai/` | AI分析（詳細: `rules/ai-response-spec.md`） |
| `config/currencies/` | 通貨ペア設定ファイル（JSON） |
| `indicators/` | テクニカル指標計算（RSI, SMA, EMA, MACD, ボリンジャー, ATR） |
| `strategies/` | 戦略別分析ロジック（mean-reversion, trend-following, breakout等） |
| `lib/` | 共通ライブラリ（config, analysis, trading） |
| `notify/` | 通知（Discord Webhook） |
| `saxo/` | Saxo Bank API クライアント（認証・価格・発注） |
| `yahoo-finance/` | 価格履歴取得（OHLC データ） |

## 戦略管理システム

### 利用可能な戦略

| 戦略名 | 説明 | 状態 | 詳細 |
|--------|------|------|------|
| `mean-reversion` | 平均回帰型: RSI/BBで過買い・過売りを検出 | 実装済み | `rules/strategies/mean-reversion.md` |
| `trend-following` | トレンドフォロー型: トレンド方向に沿った取引 | 設計中 | `rules/strategies/trend-following.md` |
| `breakout` | ブレイクアウト型: サポート/レジスタンスの突破を狙う | 設計中 | `rules/strategies/breakout.md` |

### 戦略の指定方法

通貨設定ファイルで `strategy` フィールドを指定:

```json
{
  "symbol": "USDJPY",
  "strategy": "mean-reversion",
  ...
}
```

### 戦略追加方法

1. `strategies/<strategy-name>/` ディレクトリを作成
2. `analyze.sh` スクリプトを実装（インターフェースは `base/strategy.sh` 参照）
3. `config.json` で戦略メタデータを定義
4. `rules/strategies/<strategy-name>.md` でドキュメント作成

### 同一通貨で複数戦略を並行実行する場合

通貨設定を複製:
```
config/currencies/USDJPY-MR.json  # Mean Reversion
config/currencies/USDJPY-TF.json  # Trend Following
```

## メインスクリプト

`auto-trade.sh <SYMBOL> [--dry-run]` - マルチ通貨対応オーケストレーター

### 処理フロー

```
1. config/currencies/ → 通貨設定読み込み（strategy フィールド含む）
2. yahoo-finance → 価格履歴（1h + 1d マルチタイムフレーム）
3. strategies/<strategy>/analyze.sh → 戦略別分析 + ルールベース判断
4. saxo → リアルタイム価格・残高
5. ai/analyze-trade.sh → AI分析（仕様: rules/ai-response-spec.md）
6. 最終判断（ルールベース + AI確認）
7. SL/TP価格計算（ATR基準）
8. saxo/place-order → 発注 + SL/TP関連注文（go判定時）
9. notify/discord → 結果通知
```

## テクニカル指標

| 指標 | ファイル | パラメータ |
|------|----------|-----------|
| RSI | `indicators/rsi.sh` | 14期間 |
| SMA | `indicators/sma.sh` | 20, 50期間 |
| EMA | `indicators/ema.sh` | 12, 26期間 |
| MACD | `indicators/macd.sh` | 12, 26, 9 |
| ボリンジャーバンド | `indicators/bollinger.sh` | 20期間, 2σ |
| ATR | `indicators/atr.sh` | 14期間 |
| 一括分析 | `indicators/analyze.sh` | 全指標 + ルール判定 |

## ルールベース判断

エントリー条件、フィルター、閾値等の詳細は以下を参照:

| ドキュメント | 内容 |
|--------------|------|
| `rules/trading-rules.md` | 運用ルール詳細（エントリー条件、フィルター、閾値） |
| `rules/trading-logic-summary.md` | ロジックまとめ（概要版） |

**概要:**
- Buy/Sell: 位置系（RSI + %B）ALL AND 勢い系（MACD）
- フィルター: ATR異常値抑制 + MTF確認（4h足）
- RSI閾値: ボラティリティに応じて動的調整

## Stop Loss / Take Profit

詳細: `rules/trading-rules.md` の「Stop Loss / Take Profit 設定」セクション

**概要:**
- 優先順位: AI提案値 > ATR基準の静的計算
- 静的計算: SL = ATR × 1.5、TP = SL幅 × 2.0
- 設定: `config/currencies/*.json` の `sl_tp` フィールド

## 環境変数（.env）

| 変数 | 説明 |
|------|------|
| `SAXO_ACCESS_TOKEN` | Saxo API トークン（24h有効） |
| `OPENAI_API_KEY` | OpenAI API キー |
| `DISCORD_WEBHOOK_URL` | Discord Webhook |

## 使用方法

```bash
# ヘルプ表示
./auto-trade.sh --help

# 利用可能な通貨一覧
./auto-trade.sh --list

# 各通貨でトレード
./auto-trade.sh USDJPY           # USD/JPY 本番
./auto-trade.sh USDJPY --dry-run # USD/JPY ドライラン
./auto-trade.sh EURUSD --dry-run # EUR/USD ドライラン
./auto-trade.sh XAUUSD --dry-run # Gold ドライラン
```

## 通貨追加・削除方法

**重要**: 通貨ペアを追加・削除する際は、設定ファイルとワークフローの両方を必ず同時に更新すること。片方だけ更新すると不整合が発生する。

### 更新が必要なファイル一覧

| # | ファイル | 内容 |
|---|----------|------|
| 1 | `scripts/config/currencies/<SYMBOL>.json` | 通貨設定ファイル |
| 2 | `.github/workflows/auto-trade-1h.yml` | 1時間足ワークフロー（選択肢 + デフォルト配列） |
| 3 | `.github/workflows/auto-trade-30m.yml` | 30分足ワークフロー（選択肢 + デフォルト配列） |
| 4 | `scripts/CLAUDE.md` | 対応通貨ペア一覧（このファイル） |

### 追加手順

#### 1. Saxo UIC を検索

```bash
./saxo/search-instruments.sh "GBPJPY"
```

#### 2. `config/currencies/` に JSON ファイルを追加

```json
{
  "symbol": "GBPJPY",
  "strategy": "mean-reversion",
  "yahoo_symbol": "GBPJPY=X",
  "saxo_uic": 99,
  "saxo_asset_type": "FxSpot",
  "display_name": "GBP/JPY",
  "description": "英ポンド/日本円",
  "pip_size": 0.01,
  "decimal_places": 3,
  "default_percentage": 10,
  "thresholds": {
    "rsi_overbought": 70,
    "rsi_oversold": 30,
    "rsi_buy_threshold": 40,
    "rsi_sell_threshold": 60,
    "min_conditions": 2
  },
  "timeframes": {
    "primary": "1h",
    "primary_range": "10d",
    "secondary": "1d",
    "secondary_range": "30d"
  },
  "sl_tp": {
    "enabled": true,
    "stop_loss": { "mode": "atr", "multiplier": 1.5 },
    "take_profit": { "mode": "ratio", "value": 2.0 }
  }
}
```

#### 3. ワークフローに追加

`auto-trade-1h.yml` と `auto-trade-30m.yml` の両方で:

1. `workflow_dispatch.inputs.currency.options` に追加
2. デフォルト配列 `currencies: '["USDJPY", ...]'` に追加

#### 4. このドキュメントの「対応通貨ペア」テーブルを更新

### 削除手順

1. `config/currencies/<SYMBOL>.json` を削除
2. 両ワークフローから `options` と デフォルト配列を削除
3. このドキュメントの「対応通貨ペア」テーブルから削除

## 関連ドキュメント（rules/）

| ファイル | 内容 |
|----------|------|
| `rules/trading-rules.md` | 運用ルール詳細（エントリー条件、フィルター、SL/TP等） |
| `rules/trading-logic-summary.md` | ロジックまとめ（概要版） |
| `rules/ai-response-spec.md` | AIレスポンス仕様（教育的フィードバック） |
| `rules/strategies/mean-reversion.md` | 平均回帰型戦略 |
| `rules/strategies/trend-following.md` | トレンドフォロー型戦略（設計中） |
| `rules/strategies/breakout.md` | ブレイクアウト型戦略（設計中） |
