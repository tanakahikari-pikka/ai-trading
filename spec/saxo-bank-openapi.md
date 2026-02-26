# Saxo Bank OpenAPI 仕様書

## 概要

Saxo Bankが提供するトレーディングAPIの仕様をまとめたドキュメント。

### ベースURL

```
https://gateway.saxobank.com/sim/openapi
```

- `/sim` はシミュレーション（デモ）環境
- 本番環境では `/sim` を除去

---

## 認証

OAuth 2.0 を使用。アクセストークンをリクエストヘッダーに含める。

---

## 重要な識別子

| 識別子 | 説明 | 取得元 |
|--------|------|--------|
| **ClientKey** | クライアント識別キー | `/port/v1/clients/me` |
| **AccountKey** | アカウント識別キー | `/port/v1/accounts/me` |
| **UIC** | Universal Instrument Code（商品識別子） | `/ref/v1/instruments` |
| **OrderId** | 注文ID | 注文発注時のレスポンス |

### `/me` 識別子

`/me` はログインユーザー自身を指すショートカット。多くのエンドポイントで使用可能。

---

## エンドポイント一覧

### 1. ユーザー・クライアント情報

#### ユーザー情報取得
```
GET /port/v1/users/me
```
ログインユーザーの基本情報を取得。

#### クライアント情報取得
```
GET /port/v1/clients/me
```
ログインユーザーに紐づくクライアント情報を取得。`DefaultAccountId` プロパティでデフォルトアカウントを特定可能。

#### アカウント一覧取得
```
GET /port/v1/accounts/me
```
クライアントに紐づく全アカウントを取得。`AccountId == DefaultAccountId` で照合してデフォルトアカウントの `AccountKey` を特定。

#### 残高取得（全アカウント合計）
```
GET /port/v1/balances/me
```

#### 残高取得（特定アカウント）
```
GET /port/v1/balances?AccountKey={accountKey}&ClientKey={clientKey}
```

---

### 2. 商品（Instruments）

#### 商品検索
```
GET /ref/v1/instruments?KeyWords={keywords}&AssetTypes={assetTypes}
```

**パラメータ:**
- `KeyWords` - 検索キーワード（シンボル名や説明に含まれる文字列）
- `AssetTypes` - アセットタイプ（例: `FxSpot`）

**レスポンス:**
- 各商品に `Identifier`（UIC）が含まれる

#### 商品詳細取得
```
GET /ref/v1/instruments/details
```

#### オプション詳細取得
```
GET /ref/v1/instruments/contractoptionspaces
```

---

### 3. 価格情報

#### 単一商品の価格取得
```
GET /trade/v1/infoprices?AccountKey={accountKey}&Uic={uic}&AssetType={assetType}
```

#### 複数商品の価格取得
```
GET /trade/v1/infoprices/list?AccountKey={accountKey}&Uics={uics}&AssetType={assetType}&Amount={amount}&FieldGroups={fieldGroups}
```

**パラメータ:**
- `Uics` - カンマ区切りのUICリスト（例: `2047,1311,2046,17749,16`）
- `AssetType` - アセットタイプ
- `Amount` - 数量
- `FieldGroups` - 取得するフィールドグループ（例: `DisplayAndFormat,Quote`）

---

### 4. 注文

#### 注文発注
```
POST /trade/v2/orders
```

**リクエストボディ:**
```json
{
    "Uic": 16,
    "BuySell": "Buy",
    "AssetType": "FxSpot",
    "Amount": 100000,
    "OrderPrice": 7,
    "OrderType": "Limit",
    "OrderRelation": "StandAlone",
    "ManualOrder": true,
    "OrderDuration": {
        "DurationType": "GoodTillCancel"
    },
    "AccountKey": "{accountKey}"
}
```

**フィールド説明:**

| フィールド | 説明 | 値の例 |
|-----------|------|--------|
| `Uic` | 商品識別子 | `16` (EURDKK) |
| `BuySell` | 売買方向 | `Buy`, `Sell` |
| `AssetType` | アセットタイプ | `FxSpot` |
| `Amount` | 数量 | `100000` |
| `OrderPrice` | 指値価格（Limitの場合） | `7` |
| `OrderType` | 注文タイプ | `Limit`, `Market` |
| `OrderRelation` | 注文関係 | `StandAlone` |
| `ManualOrder` | 手動注文フラグ | `true` |
| `OrderDuration.DurationType` | 注文有効期限 | `GoodTillCancel`, `DayOrder` |
| `AccountKey` | アカウントキー | - |

#### 注文変更
```
POST /trade/v2/orders
```

**リクエストボディ（変更時）:**
```json
{
    "OrderId": "{orderId}",
    "OrderType": "Market",
    "OrderDuration": {
        "DurationType": "DayOrder"
    },
    "AccountKey": "{accountKey}",
    "AssetType": "FxSpot"
}
```

`OrderId` を指定することで既存注文を変更。

#### 注文一覧取得
```
GET /port/v1/orders/me?fieldGroups=DisplayAndFormat
```

---

### 5. ポジション

#### ポジション一覧取得
```
GET /port/v1/positions?ClientKey={clientKey}&FieldGroups={fieldGroups}
```

**FieldGroups:**
- `PositionStatic` - 変化しない値
- `PositionDynamic` - 変化する値
- `DisplayAndFormat` - 表示用情報
- `PositionBase`
- `PositionView`

---

## FieldGroups 一覧

| グループ名 | 説明 |
|-----------|------|
| `DisplayAndFormat` | 表示用のフォーマット情報 |
| `Quote` | 価格情報 |
| `PositionStatic` | 変化しない静的な値 |
| `PositionDynamic` | リアルタイムで変化する動的な値 |
| `PositionBase` | ポジション基本情報 |
| `PositionView` | ポジション表示用情報 |

---

## 典型的なワークフロー

### 1. 初期化（キーの取得）

```
1. GET /port/v1/users/me        → ユーザー情報
2. GET /port/v1/clients/me      → ClientKey, DefaultAccountId
3. GET /port/v1/accounts/me     → AccountKey（DefaultAccountIdで照合）
```

### 2. 商品検索と価格取得

```
1. GET /ref/v1/instruments?KeyWords=...&AssetTypes=...  → UIC取得
2. GET /trade/v1/infoprices/list?Uics=...              → 価格取得
```

### 3. 注文フロー

```
1. POST /trade/v2/orders        → 注文発注
2. GET /port/v1/orders/me       → 注文確認
3. POST /trade/v2/orders        → 注文変更（必要な場合）
4. GET /port/v1/positions       → ポジション確認（約定後）
```

---

## 参考リンク

- [Saxo Developer Portal](https://www.developer.saxo/)
- [OpenAPI Tutorial](https://www.developer.saxo/openapi/tutorial)
