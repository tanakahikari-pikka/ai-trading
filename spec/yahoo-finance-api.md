# Yahoo Finance API 仕様書

## 概要

Saxo Bank シミュレーション環境ではChart APIが利用不可のため、価格履歴データの取得にYahoo Finance APIを使用する。

**注意**: 本番環境への移行時は、Saxo Bank Chart APIへの置き換えを検討すること。

## エンドポイント

```
GET https://query1.finance.yahoo.com/v8/finance/chart/{symbol}
```

## パラメータ

| パラメータ | 説明 | 例 |
|-----------|------|-----|
| `symbol` | Yahoo Financeシンボル | `GC=F`, `EURUSD=X` |
| `interval` | ローソク足間隔 | `1m`, `5m`, `15m`, `30m`, `1h`, `1d`, `1wk`, `1mo` |
| `range` | データ範囲 | `1d`, `5d`, `10d`, `1mo`, `3mo`, `6mo`, `1y` |

## シンボルマッピング

| 銘柄 | Yahoo Finance | Saxo Bank UIC |
|------|---------------|---------------|
| Gold (先物) | `GC=F` | 8176 (XAUUSD) |
| Gold (スポット) | `XAUUSD=X` | 8176 |
| EUR/USD | `EURUSD=X` | 21 |
| USD/JPY | `USDJPY=X` | 31 |
| GBP/USD | `GBPUSD=X` | 39 |
| EUR/JPY | `EURJPY=X` | 18 |
| Dow Jones | `^DJI` | - |
| S&P 500 | `^GSPC` | - |

## レスポンス形式

```json
{
  "chart": {
    "result": [{
      "meta": {
        "symbol": "GC=F",
        "currency": "USD",
        "exchangeName": "CMX",
        "regularMarketPrice": 5200.0,
        "previousClose": 5180.0,
        "dataGranularity": "1h",
        "range": "10d"
      },
      "timestamp": [1234567890, ...],
      "indicators": {
        "quote": [{
          "open": [5180.0, ...],
          "high": [5210.0, ...],
          "low": [5170.0, ...],
          "close": [5200.0, ...],
          "volume": [1000, ...]
        }]
      }
    }]
  }
}
```

## 使用例

```bash
# Gold 1時間足 10日分
curl -s -A "Mozilla/5.0" \
  "https://query1.finance.yahoo.com/v8/finance/chart/GC=F?interval=1h&range=10d"

# EUR/USD 日足 1ヶ月分
curl -s -A "Mozilla/5.0" \
  "https://query1.finance.yahoo.com/v8/finance/chart/EURUSD=X?interval=1d&range=1mo"
```

## 注意事項

1. **User-Agent必須**: リクエストにUser-Agentヘッダーが必要
2. **レート制限**: 過度なリクエストは制限される可能性あり
3. **データ遅延**: リアルタイムではなく若干の遅延あり
4. **営業時間**: 市場休場時はデータが更新されない

## 関連スクリプト

- `scripts/yahoo-finance/get-chart.sh` - 価格履歴取得スクリプト
