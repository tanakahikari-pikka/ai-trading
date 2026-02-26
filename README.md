# Bogota - マルチ通貨自動トレードシステム

複数通貨ペア対応の自動トレードシステム。テクニカル指標 + AI分析で判断し、Saxo Bank API で発注。**教育的フィードバック機能付き**で、投資初心者の学習をサポートします。

## 特徴

- **マルチ通貨対応**: USD/JPY, EUR/USD, GBP/USD, EUR/JPY, Gold (XAU/USD)
- **マルチタイムフレーム分析**: 1時間足 + 日足
- **複合テクニカル指標**: RSI, SMA, EMA, MACD, ボリンジャーバンド, ATR
- **ハイブリッド判断**: ルールベース + AI確認
- **教育的フィードバック**: 毎回の分析で投資知識を学べる
- **Discord通知**: リアルタイムで結果を通知

## 対応通貨ペア

| シンボル | 名称 | 説明 |
|----------|------|------|
| USDJPY | USD/JPY | 米ドル/日本円 |
| EURUSD | EUR/USD | ユーロ/米ドル |
| GBPUSD | GBP/USD | 英ポンド/米ドル |
| EURJPY | EUR/JPY | ユーロ/日本円 |
| XAUUSD | XAU/USD | 金/米ドル (Gold) |

## クイックスタート

### 1. 環境変数の設定

`.env` ファイルを作成:

```bash
cp .env.example .env
```

必要な環境変数:

| 変数 | 説明 |
|------|------|
| `SAXO_ACCESS_TOKEN` | Saxo Bank API トークン（24h有効） |
| `OPENAI_API_KEY` | OpenAI API キー |
| `DISCORD_WEBHOOK_URL` | Discord Webhook URL |

### 2. 実行

```bash
# ヘルプ表示
./scripts/auto-trade.sh --help

# 利用可能な通貨一覧
./scripts/auto-trade.sh --list

# ドライラン（発注なし）
./scripts/auto-trade.sh USDJPY --dry-run
./scripts/auto-trade.sh EURUSD --dry-run
./scripts/auto-trade.sh XAUUSD --dry-run

# 本番実行
./scripts/auto-trade.sh USDJPY
```

## ディレクトリ構成

```
bogota/
├── scripts/
│   ├── auto-trade.sh           # メインスクリプト
│   ├── config/currencies/      # 通貨ペア設定
│   │   ├── USDJPY.json
│   │   ├── EURUSD.json
│   │   ├── GBPUSD.json
│   │   ├── EURJPY.json
│   │   └── XAUUSD.json
│   ├── lib/                    # 共通ライブラリ
│   │   ├── config.sh
│   │   ├── analysis.sh
│   │   └── trading.sh
│   ├── indicators/             # テクニカル指標
│   │   ├── rsi.sh
│   │   ├── sma.sh
│   │   ├── ema.sh
│   │   ├── macd.sh
│   │   ├── bollinger.sh
│   │   ├── atr.sh
│   │   └── analyze.sh
│   ├── ai/                     # AI分析
│   │   └── analyze-trade.sh
│   ├── saxo/                   # Saxo Bank API
│   ├── yahoo-finance/          # 価格データ取得
│   └── notify/                 # Discord通知
└── rules/                      # 運用ルール・仕様
    ├── trading-rules.md
    └── ai-response-spec.md
```

## 処理フロー

```
1. 通貨設定読み込み (config/currencies/)
2. 価格履歴取得 (Yahoo Finance - 1h + 1d)
3. テクニカル分析 (RSI, SMA, MACD, BB, ATR)
4. ルールベース判断 (2/4条件で発火)
5. Saxoリアルタイム価格・残高取得
6. AI分析 (教育的フィードバック付き)
7. 最終判断 (ルール + AI確認)
8. 発注 (go判定時のみ)
9. Discord通知
```

## ルールベース判断

### Buy条件（2/4以上で発火）
1. RSI < 40（売られ気味）
2. 価格 > SMA(20)（上昇トレンド）
3. MACD > シグナルライン（勢いあり）
4. 価格 < BB中央線（下半分）

### Sell条件（2/4以上で発火）
1. RSI > 60（買われ気味）
2. 価格 < SMA(20)（下降トレンド）
3. MACD < シグナルライン（勢い弱い）
4. 価格 > BB中央線（上半分）

## AI分析（教育的フィードバック）

AIは単なる売買判断だけでなく、以下の教育的フィードバックを提供:

- **判断理由**: なぜその判断になったか
- **一次データ**: 生のテクニカル指標値
- **今日の学び**: 毎回1つのトピックを解説
- **具体例**: 今回のデータを使った説明
- **次のアクション**: エントリー条件や注目ポイント

## 通貨追加方法

`scripts/config/currencies/` に JSON ファイルを追加:

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

Saxo UICは `scripts/saxo/search-instruments.sh "GBPJPY"` で検索できます。

## GitHub Actions（自動実行）

1時間ごとに自動実行するワークフローが設定されています。

## ドキュメント

- [運用ルール詳細](./rules/trading-rules.md)
- [AIレスポンス仕様](./rules/ai-response-spec.md)
- [スクリプト詳細](./scripts/CLAUDE.md)

## 注意事項

- **投資は自己責任**で行ってください
- **デモ環境**でのテストを推奨します
- Saxo Access Token は24時間で期限切れになります
- Gold (XAUUSD) はポジションサイズを5%に設定しています（リスク管理）

## ライセンス

Private
