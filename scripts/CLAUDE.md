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
| `config/currencies/` | 通貨ペア固有データ（symbol, saxo_uic, pip_size等） |
| `config/strategies/` | 戦略設定（thresholds, timeframes, sl_tp等） |
| `config/assignments.json` | 通貨→戦略マッピング |
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

### 設定構造

通貨データと戦略データは分離して管理:

```
config/
├── currencies/              # 通貨固有データのみ
│   ├── USDJPY.json          # symbol, saxo_uic, pip_size 等
│   └── ...
├── strategies/              # 戦略設定
│   ├── mean-reversion/
│   │   ├── defaults.json    # デフォルト設定（thresholds, timeframes, sl_tp）
│   │   └── overrides/       # 通貨別オーバーライド（任意）
│   │       └── XAUUSD.json  # 貴金属用カスタム設定など
│   └── trend-following/     # 将来の戦略
│       └── ...
└── assignments.json         # 通貨→戦略マッピング
```

### 戦略の指定方法

`config/assignments.json` で通貨→戦略マッピングを管理:

```json
{
  "USDJPY": ["mean-reversion"],
  "EURUSD": ["mean-reversion"],
  "XAUUSD": ["mean-reversion"]
}
```

配列形式で将来の複数戦略並行運用に対応。

### 戦略追加方法

1. `strategies/<strategy-name>/` ディレクトリを作成
2. `analyze.sh` スクリプトを実装（インターフェースは `base/strategy.sh` 参照）
3. `config/strategies/<strategy-name>/defaults.json` で戦略設定を定義
4. `rules/strategies/<strategy-name>.md` でドキュメント作成
5. `config/assignments.json` で通貨をマッピング

### 通貨別オーバーライド

特定通貨のパラメータをカスタマイズする場合:

```bash
# 例: 貴金属用のカスタム閾値
config/strategies/mean-reversion/overrides/XAUUSD.json
```

オーバーライドファイルには差分のみ記述（戦略デフォルトにマージされる）。

### 同一通貨で複数戦略を並行実行する場合

`assignments.json` で複数戦略を指定（将来対応）:
```json
{
  "USDJPY": ["mean-reversion", "trend-following"]
}
```

## メインスクリプト

`auto-trade.sh <SYMBOL> [--dry-run]` - マルチ通貨対応オーケストレーター

### 処理フロー

```
1. config/ → 設定読み込み（通貨 + 戦略デフォルト + オーバーライドをマージ）
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
- 設定: `config/strategies/<strategy>/defaults.json` の `sl_tp` フィールド

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
| 1 | `scripts/config/currencies/<SYMBOL>.json` | 通貨固有データ |
| 2 | `scripts/config/assignments.json` | 通貨→戦略マッピング |
| 3 | `.github/workflows/auto-trade-1h.yml` | 1時間足ワークフロー（選択肢 + デフォルト配列） |
| 4 | `.github/workflows/auto-trade-30m.yml` | 30分足ワークフロー（選択肢 + デフォルト配列） |
| 5 | `scripts/CLAUDE.md` | 対応通貨ペア一覧（このファイル） |

### 追加手順

#### 1. Saxo UIC を検索

```bash
./saxo/search-instruments.sh "GBPJPY"
```

#### 2. `config/currencies/` に JSON ファイルを追加（通貨固有データのみ）

```json
{
  "symbol": "GBPJPY",
  "yahoo_symbol": "GBPJPY=X",
  "saxo_uic": 99,
  "saxo_asset_type": "FxSpot",
  "display_name": "GBP/JPY",
  "description": "英ポンド/日本円",
  "pip_size": 0.01,
  "decimal_places": 3,
  "default_percentage": 10,
  "max_amount": 10000
}
```

#### 3. `config/assignments.json` に戦略マッピングを追加

```json
{
  "GBPJPY": ["mean-reversion"],
  ...
}
```

#### 4. ワークフローに追加

`auto-trade-1h.yml` と `auto-trade-30m.yml` の両方で:

1. `workflow_dispatch.inputs.currency.options` に追加
2. デフォルト配列 `currencies: '["USDJPY", ...]'` に追加

#### 5. このドキュメントの「対応通貨ペア」テーブルを更新

#### 6. （任意）通貨別オーバーライドが必要な場合

特定通貨でパラメータをカスタマイズする場合のみ:
```bash
config/strategies/mean-reversion/overrides/GBPJPY.json
```

### 削除手順

1. `config/currencies/<SYMBOL>.json` を削除
2. `config/assignments.json` からマッピングを削除
3. 両ワークフローから `options` と デフォルト配列を削除
4. このドキュメントの「対応通貨ペア」テーブルから削除

## 関連ドキュメント（rules/）

| ファイル | 内容 |
|----------|------|
| `rules/trading-rules.md` | 運用ルール詳細（エントリー条件、フィルター、SL/TP等） |
| `rules/trading-logic-summary.md` | ロジックまとめ（概要版） |
| `rules/ai-response-spec.md` | AIレスポンス仕様（教育的フィードバック） |
| `rules/strategies/mean-reversion.md` | 平均回帰型戦略 |
| `rules/strategies/trend-following.md` | トレンドフォロー型戦略（設計中） |
| `rules/strategies/breakout.md` | ブレイクアウト型戦略（設計中） |
