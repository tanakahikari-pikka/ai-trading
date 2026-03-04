# Mean Reversion Strategy

## Overview

平均回帰型戦略は、価格が過買い・過売り状態から平均に回帰する性質を利用した取引戦略です。

## Strategy Logic

### Buy Signal (買いシグナル)

**Position Conditions (位置系条件) - いずれか1つでシグナル発火:**
1. RSI < RSI_BUY_THRESHOLD (動的閾値: 通常40, 高ボラ30)
2. %B < 30 (BB下限付近)

**Momentum Conditions (勢い系条件) - オプション:**
- MACD > Signal AND (フレッシュクロス5本以内 OR ヒストグラム3本連続増加)

### Sell Signal (売りシグナル)

**Position Conditions (位置系条件) - いずれか1つでシグナル発火:**
1. RSI > RSI_SELL_THRESHOLD (動的閾値: 通常60, 高ボラ70)
2. %B > 70 (BB上限付近)

**Momentum Conditions (勢い系条件) - オプション:**
- MACD < Signal AND (フレッシュクロス5本以内 OR ヒストグラム3本連続減少)

## Filters

### ATR Filter (ボラティリティフィルター)
- `atr_ratio < 0.7`: シグナル抑制 (低ボラ・レンジ相場)
- `atr_ratio > 3.0`: シグナル抑制 (極端なボラ・スプレッド/スリッページリスク)

### BB Squeeze Filter
- `band_width_pct < 2.0 AND atr_ratio 0.7-1.0`: シグナル抑制 (方向性不明確)

### MTF Filter (マルチタイムフレームフィルター)
- Buy: 4h SMA20 > 4h SMA50 (上昇トレンド) または横ばい
- Sell: 4h SMA20 < 4h SMA50 (下降トレンド) または横ばい

## Best Used For

- レンジ相場
- 明確なサポート/レジスタンスがある市場
- 低〜中程度のボラティリティ環境

## Avoid In

- 強いトレンド相場
- 高ボラティリティ・ニュースイベント時
- 低流動性期間

## Configuration

通貨設定で `"strategy": "mean-reversion"` を指定:

```json
{
  "symbol": "USDJPY",
  "strategy": "mean-reversion",
  ...
}
```

## Files

- `scripts/strategies/mean-reversion/analyze.sh` - 分析スクリプト
- `scripts/strategies/mean-reversion/config.json` - 戦略設定

## Related Documents

- `rules/trading-rules.md` - 運用ルール詳細
- `rules/trading-logic-summary.md` - ロジックまとめ
