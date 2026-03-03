---
description: 取引履歴（Order Blotter）を取得してサマリを表示
allowed-tools: Bash(*), Read, AskUserQuestion
---

# Saxo Bank Trade Summary

このスキルは取引履歴を取得し、通貨ペアごとの損益サマリを表示する。

## 実行手順

### Step 1: 期間選択

AskUserQuestion で期間を確認：
- 過去1日
- 過去7日（デフォルト）
- 過去30日
- カスタム期間

### Step 2: 取引履歴取得

Order Blotter APIから取引履歴を取得：

```bash
./scripts/saxo/get-trade-history.sh <days_back>
```

### Step 3: 現在のポジション取得

オープンポジションも合わせて確認：

```bash
./scripts/saxo/get-positions.sh
```

### Step 4: 残高取得

口座残高を確認：

```bash
./scripts/saxo/get-balance.sh
```

### Step 5: サマリ表示

以下の形式で結果を表示：

```
============================================
        TRADE SUMMARY REPORT
============================================
期間: YYYY-MM-DD ~ YYYY-MM-DD
総取引回数: XX

【通貨ペア別 実現損益】
┌────────────┬────────┬────────┬──────────────┐
│ 通貨ペア   │ Buy    │ Sell   │ 実現P/L      │
├────────────┼────────┼────────┼──────────────┤
│ USDJPY     │ 70,000 │ 70,000 │ +43 USD      │
│ XAUUSD     │ 50     │ 50     │ +886 USD     │
│ EURUSD     │ 10,000 │ 0      │ (未決済)     │
└────────────┴────────┴────────┴──────────────┘

【オープンポジション（含み損益）】
┌────────────┬──────────┬────────────┬──────────────┐
│ 通貨ペア   │ 数量     │ エントリー │ 含みP/L      │
├────────────┼──────────┼────────────┼──────────────┤
│ EURUSD     │ 149,998  │ 1.182      │ -907 USD     │
└────────────┴──────────┴────────────┴──────────────┘

【口座残高】
  キャッシュ: 1,000,707.43 EUR
  実現損益合計: +XXX EUR
  含み損益合計: -XXX EUR
  ────────────────────
  純資産: X,XXX,XXX EUR
============================================
```

## UIC ↔ シンボル対応表

| UIC | シンボル | 説明 |
|-----|----------|------|
| 21 | EURUSD | ユーロ/米ドル |
| 31 | USDJPY | 米ドル/日本円 |
| 42 | USDJPY | 米ドル/日本円（別UIC） |
| 22 | GBPUSD | 英ポンド/米ドル |
| 47 | USDPLN | 米ドル/ポーランドズロチ |
| 1315 | EURJPY | ユーロ/日本円 |
| 8176 | XAUUSD | 金/米ドル |

## スクリプトの場所

- `scripts/saxo/get-trade-history.sh` - 取引履歴取得（Order Activities API）
- `scripts/saxo/get-positions.sh` - オープンポジション取得
- `scripts/saxo/get-balance.sh` - 残高取得
- `scripts/saxo/get-accounts.sh` - アカウント情報

## API エンドポイント

### Order Activities（取引履歴）
```
GET /cs/v1/audit/orderactivities?ClientKey={clientKey}&FromDateTime={from}&ToDateTime={to}
```

### Closed Positions（クローズ済みポジション）
```
GET /port/v1/closedpositions?ClientKey={clientKey}&FieldGroups=ClosedPosition,DisplayAndFormat
```

## 計算ロジック

### 実現損益（クローズ済み）

FIFO方式で計算：
```
P/L = (平均売却価格 - 平均購入価格) × 決済数量
```

USDJPYなど円建ての場合はUSD換算：
```
P/L (USD) = P/L (JPY) / 現在レート
```

### 含み損益（オープン）

ポジションAPIから直接取得：
- `ProfitLossOnTrade` - 取引通貨ベース
- `ProfitLossOnTradeInBaseCurrency` - 基軸通貨（EUR）ベース

## 注意事項

- シミュレーション環境では履歴保持期間が限られる場合あり
- 手数料・スワップは別途計算が必要
- 複数通貨の損益を合算する場合は為替レートに注意
