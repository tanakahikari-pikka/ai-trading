# scripts/ - マルチ通貨自動トレードシステム

## 概要

複数通貨ペア対応の自動トレードシステム。テクニカル指標（RSI, MACD, ボリンジャーバンド, ATR）+ AI分析で判断し、Saxo Bank API で発注。教育的フィードバック機能付き。

## 対応通貨ペア

| シンボル | 名称 | 説明 |
|----------|------|------|
| USDJPY | USD/JPY | 米ドル/日本円 |
| EURUSD | EUR/USD | ユーロ/米ドル |
| GBPUSD | GBP/USD | 英ポンド/米ドル |
| EURJPY | EUR/JPY | ユーロ/日本円 |
| XAUUSD | XAU/USD | 金/米ドル (Gold) |

## ディレクトリ構成

| ディレクトリ | 責務 |
|--------------|------|
| `ai/` | AI分析（OpenAI API で教育的フィードバック付き判断） |
| `config/currencies/` | 通貨ペア設定ファイル（JSON） |
| `indicators/` | テクニカル指標計算（RSI, SMA, EMA, MACD, ボリンジャー, ATR） |
| `lib/` | 共通ライブラリ（config, analysis, trading） |
| `notify/` | 通知（Discord Webhook） |
| `saxo/` | Saxo Bank API クライアント（認証・価格・発注） |
| `yahoo-finance/` | 価格履歴取得（OHLC データ） |

## メインスクリプト

`auto-trade.sh <SYMBOL> [--dry-run]` - マルチ通貨対応オーケストレーター

### 処理フロー

```
1. config/currencies/ → 通貨設定読み込み
2. yahoo-finance → 価格履歴（1h + 1d マルチタイムフレーム）
3. indicators/analyze.sh → 全指標一括計算 + ルールベース判断
4. saxo → リアルタイム価格・残高
5. ai/analyze-trade.sh → AI分析（教育的フィードバック付き）
6. 最終判断（ルールベース + AI確認）
7. saxo/place-order → 発注（go判定時）
8. notify/discord → 結果通知
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

**Buy条件（2/4以上で発火）:**
1. RSI < 40
2. 価格 > SMA(20)
3. MACD > シグナルライン
4. 価格 < BB中央線

**Sell条件（2/4以上で発火）:**
1. RSI > 60
2. 価格 < SMA(20)
3. MACD < シグナルライン
4. 価格 > BB中央線

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

## 通貨追加方法

### 1. Saxo UIC を検索

```bash
./saxo/search-instruments.sh "GBPJPY"
```

### 2. `config/currencies/` に JSON ファイルを追加

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
  }
}
```

## 関連ドキュメント

- `../rules/trading-rules.md` - 運用ルール詳細
- `../rules/ai-response-spec.md` - AIレスポンス仕様（教育的フィードバック）
