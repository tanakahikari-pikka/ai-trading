# Trend Following Strategy

## Overview

トレンドフォロー型戦略は、確立されたトレンドの方向に沿って取引を行う戦略です。

**Status: Not Implemented (未実装)**

## Strategy Logic (設計案)

### Buy Signal (買いシグナル)

**Trend Conditions (トレンド条件):**
1. Price > SMA20 > SMA50 (上昇トレンド確認)
2. EMA12 > EMA26 (短期トレンド確認)
3. ADX > 25 (トレンド強度確認)

**Entry Conditions (エントリー条件):**
- 押し目: Price touches SMA20 from above
- MACD histogram increasing (勢い回復)

### Sell Signal (売りシグナル)

**Trend Conditions (トレンド条件):**
1. Price < SMA20 < SMA50 (下降トレンド確認)
2. EMA12 < EMA26 (短期トレンド確認)
3. ADX > 25 (トレンド強度確認)

**Entry Conditions (エントリー条件):**
- 戻り: Price touches SMA20 from below
- MACD histogram decreasing (勢い減少)

## Best Used For

- 明確なトレンドがある市場
- 中〜高ボラティリティ環境
- 経済指標発表後のトレンド継続局面

## Avoid In

- レンジ相場
- トレンド転換局面
- 低ボラティリティ期間

## Implementation Plan

1. `scripts/strategies/trend-following/analyze.sh` を作成
2. ADX インディケーターを追加
3. トレンドフィルターを実装
4. 通貨設定で `"strategy": "trend-following"` を指定

## Files (予定)

- `scripts/strategies/trend-following/analyze.sh`
- `scripts/strategies/trend-following/config.json`
- `scripts/indicators/adx.sh` (新規)
