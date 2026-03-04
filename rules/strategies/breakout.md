# Breakout Strategy

## Overview

ブレイクアウト型戦略は、重要なサポート/レジスタンスレベルのブレイクを狙った取引戦略です。

**Status: Not Implemented (未実装)**

## Strategy Logic (設計案)

### Buy Signal (買いシグナル)

**Breakout Conditions (ブレイクアウト条件):**
1. Price > BB Upper (ボリンジャーバンド上限突破)
2. Volume spike > 1.5x average (出来高急増)
3. ADX > 20 (最低限のトレンド強度)

**Confirmation:**
- Close above breakout level (ブレイクアウトレベル上でクローズ)
- No immediate rejection (即座の押し戻しなし)

### Sell Signal (売りシグナル)

**Breakout Conditions (ブレイクアウト条件):**
1. Price < BB Lower (ボリンジャーバンド下限突破)
2. Volume spike > 1.5x average (出来高急増)
3. ADX > 20 (最低限のトレンド強度)

**Confirmation:**
- Close below breakout level (ブレイクアウトレベル下でクローズ)
- No immediate rejection (即座の押し戻しなし)

## Risk Management

### Stop Loss
- ブレイクアウトレベルの反対側に設定
- ATR × 1.0 を最低距離として使用

### False Breakout Detection
- Volume confirmation 必須
- BB squeeze 後のブレイクアウトを優先
- 既存トレンドの方向へのブレイクアウトを優先

## Best Used For

- BB squeeze 後の相場
- 重要なサポート/レジスタンス付近
- ニュースイベント前後

## Avoid In

- 低出来高期間
- 既にトレンドが成熟している局面
- 明確なサポート/レジスタンスがない相場

## Implementation Plan

1. `scripts/strategies/breakout/analyze.sh` を作成
2. BB squeeze 検出ロジックを強化
3. ブレイクアウトレベル検出を実装
4. 通貨設定で `"strategy": "breakout"` を指定

## Files (予定)

- `scripts/strategies/breakout/analyze.sh`
- `scripts/strategies/breakout/config.json`
