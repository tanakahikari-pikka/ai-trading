---
description: Saxo Bank API で商品検索・価格確認・注文発注を対話的に実行
allowed-tools: Bash(*), Read, AskUserQuestion
---

# Saxo Bank Trading Assistant

このスキルは Saxo Bank OpenAPI を使用して、以下のフローを対話的に実行する：

1. アカウント情報の取得
2. 商品の検索
3. 価格の確認
4. 注文の発注

## 実行手順

### Step 1: アカウント情報取得

まず `scripts/saxo/get-accounts.sh` を実行してアカウント情報を取得する。
結果から ClientKey と AccountKey を確認し、ユーザーに表示する。

エラーが発生した場合は、`.env` ファイルの設定を確認するようユーザーに案内する。

### Step 2: 商品検索

AskUserQuestion を使用して以下を確認：
- 検索キーワード（例: USD, EURUSD, Gold）
- アセットタイプ（デフォルト: FxSpot）

`scripts/saxo/search-instruments.sh <keywords> [asset_type]` を実行して商品を検索。
結果の UIC、Symbol、Description をユーザーに表示する。

### Step 3: 商品選択

検索結果から AskUserQuestion で商品（UIC）を選択させる。
選択肢として上位4件程度を表示し、「その他」で手動入力も可能にする。

### Step 4: 価格確認

`scripts/saxo/get-prices.sh <account_key> <uic> [asset_type]` を実行。
Bid/Ask 価格をユーザーに表示する。

### Step 5: 注文内容の入力

AskUserQuestion を使用して以下を順番に確認：

1. 売買方向
   - Buy（買い）
   - Sell（売り）

2. 数量
   - ユーザーに入力させる

3. 注文タイプ
   - Market（成行）
   - Limit（指値）

4. 指値価格（Limit の場合のみ）
   - ユーザーに入力させる

### Step 6: 最終確認

注文内容のサマリーを表示：
- 商品: {Symbol} (UIC: {uic})
- 方向: {BuySell}
- 数量: {Amount}
- タイプ: {OrderType}
- 価格: {OrderPrice または "成行"}

AskUserQuestion で「発注しますか？」と確認。
- はい、発注する
- いいえ、キャンセル

### Step 7: 注文発注

「はい」の場合のみ `scripts/saxo/place-order.sh` を実行：
```
scripts/saxo/place-order.sh <account_key> <uic> <buy_sell> <amount> <order_type> [order_price] [asset_type]
```

結果をユーザーに表示する。

## 注意事項

- このスキルはシミュレーション環境（/sim）を使用する
- 実際の取引を行う前に、必ず .env の SAXO_BASE_URL を確認すること
- 認証トークンの有効期限が切れている場合はエラーになる

## スクリプトの場所

すべてのスクリプトは `scripts/saxo/` ディレクトリにある：
- auth.sh - 認証情報読み込み
- get-accounts.sh - アカウント情報取得
- search-instruments.sh - 商品検索
- get-prices.sh - 価格取得
- place-order.sh - 注文発注
