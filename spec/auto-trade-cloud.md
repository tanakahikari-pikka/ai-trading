# Auto Trade Cloud 設計書

## 概要

現在ローカルで動作している `/saxo-auto-trade` スキルを GitHub Actions + Claude Code Actions でクラウド自動実行する。

## 要件

| 項目 | 仕様 |
|------|------|
| 対象銘柄 | USD/JPY 固定 |
| 発注量 | 残高の 10% |
| 実行頻度 | 1時間ごと (cron) |
| 損切り | なし（初期版） |
| ユーザー確認 | なし（AI判断で自動発注） |

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions (cron: 毎時0分)                              │
│                                                             │
│  1. Checkout                                                │
│  2. .env セットアップ（Secrets からトークン取得）             │
│  3. Claude Code Actions で自動トレード実行                    │
│       ├─ データ取得 (Yahoo Finance)                         │
│       ├─ RSI計算                                            │
│       ├─ リアルタイム価格取得 (Saxo)                         │
│       ├─ AI判断 → go / not_order                           │
│       └─ go なら自動発注                                    │
│  4. 結果をログ出力（将来的にSlack通知）                       │
└─────────────────────────────────────────────────────────────┘
```

## コンポーネント

### 1. GitHub Actions Workflow

**ファイル:** `.github/workflows/auto-trade.yml`

```yaml
name: Auto Trade USD/JPY

on:
  schedule:
    - cron: '0 * * * *'  # 毎時0分 (UTC)
  workflow_dispatch:      # 手動実行

jobs:
  trade:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .env
        run: |
          echo "SAXO_ACCESS_TOKEN=${{ secrets.SAXO_ACCESS_TOKEN }}" >> .env
          echo "SAXO_BASE_URL=https://gateway.saxobank.com/sim/openapi" >> .env

      - name: Run Auto Trade
        uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            /saxo-auto-trade --auto
            対象: USD/JPY
            発注量: 残高の10%
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 2. トークン管理（暫定）

**方式:** GitHub Secrets から直接アクセストークンを取得

**注意事項:**
- アクセストークンは有効期限あり（通常24時間）
- 期限切れ時は手動で Secrets を更新する必要あり
- 将来的にはリフレッシュトークン方式に移行予定

**トークン更新手順（手動）:**
1. Saxo Developer Portal でトークンを再取得
2. GitHub リポジトリ → Settings → Secrets → `SAXO_ACCESS_TOKEN` を更新

### 3. 自動トレードスキル（改修）

**ファイル:** `.claude/skills/saxo-auto-trade.md`

**変更点:**
- `--auto` フラグ追加
- `--auto` 時は AskUserQuestion をスキップ
- AI判断結果を JSON で出力

**判断結果フォーマット:**
```json
{
  "decision": "go",          // "go" or "not_order"
  "symbol": "USDJPY",
  "action": "Buy",           // "Buy" or "Sell"
  "amount": 10000,           // 計算された発注量
  "reason": "RSI=28.5 < 30, 売られすぎシグナル",
  "rsi": 28.5,
  "price": {
    "bid": 156.335,
    "ask": 156.355
  }
}
```

### 4. 残高取得スクリプト（新規）

**ファイル:** `scripts/saxo/get-balance.sh`

**機能:**
- アカウントの現金残高を取得
- 10% を計算して発注可能額を返す

**Saxo API エンドポイント:**
```
GET /port/v1/balances?AccountKey=<ACCOUNT_KEY>&ClientKey=<CLIENT_KEY>
```

## シークレット管理

GitHub Secrets に以下を登録:

| Secret Name | 説明 | 備考 |
|-------------|------|------|
| `ANTHROPIC_API_KEY` | Claude API キー | |
| `SAXO_ACCESS_TOKEN` | Saxo アクセストークン | 期限切れ時は手動更新 |

**将来追加予定（リフレッシュトークン方式移行時）:**
| Secret Name | 説明 |
|-------------|------|
| `SAXO_APP_KEY` | Saxo アプリケーションキー |
| `SAXO_APP_SECRET` | Saxo アプリケーションシークレット |
| `SAXO_REFRESH_TOKEN` | Saxo リフレッシュトークン |

## 判断ロジック

### ルールベース（80%）

| RSI | 状態 | 判断 |
|-----|------|------|
| > 70 | 買われすぎ | Sell → `go` |
| < 30 | 売られすぎ | Buy → `go` |
| 30-70 | 中立 | `not_order` |

### AI補正（20%）

- トレンド分析
- ボラティリティ確認
- 異常値検出

最終判断は RSI ルールを基本とし、AI が明確なリスクを検出した場合のみ `not_order` にオーバーライド可能。

## 発注量計算

```
発注量 = 残高 × 10% ÷ 現在価格
```

例: 残高 100万円、USD/JPY = 156.35 の場合
```
発注量 = 1,000,000 × 0.1 ÷ 156.35 ≈ 639 USD
```

## ファイル構成（実装後）

```
bogota/
├── .github/
│   └── workflows/
│       └── auto-trade.yml        # GitHub Actions ワークフロー
├── .claude/
│   └── skills/
│       └── saxo-auto-trade.md    # 改修版スキル
├── scripts/
│   ├── saxo/
│   │   ├── auth.sh               # 既存
│   │   ├── get-accounts.sh       # 既存
│   │   ├── get-prices.sh         # 既存
│   │   ├── place-order.sh        # 既存
│   │   └── get-balance.sh        # 新規: 残高取得
│   ├── yahoo-finance/
│   │   └── get-chart.sh          # 既存
│   └── indicators/
│       └── rsi.sh                # 既存
└── spec/
    └── auto-trade-cloud.md       # この設計書
```

## 実装タスク

### Phase 1: 暫定版（トークン直接指定）

- [ ] `scripts/saxo/get-balance.sh` 作成
- [ ] `.claude/skills/saxo-auto-trade.md` に `--auto` モード追加
- [ ] `.github/workflows/auto-trade.yml` 作成
- [ ] GitHub Secrets 設定（ANTHROPIC_API_KEY, SAXO_ACCESS_TOKEN）
- [ ] ローカルでのテスト
- [ ] GitHub Actions でのテスト（手動実行）
- [ ] cron 有効化

### Phase 2: 将来（リフレッシュトークン対応）

- [ ] `scripts/saxo/refresh-token.sh` 作成
- [ ] GitHub Secrets 追加（APP_KEY, APP_SECRET, REFRESH_TOKEN）
- [ ] ワークフローにリフレッシュステップ追加

## 将来的な拡張

1. **リフレッシュトークン対応** - トークン自動更新（Phase 2）
2. **Slack/Discord 通知** - 発注結果を通知
3. **複数銘柄対応** - Gold, EUR/USD 等
4. **損切り/利確設定** - 自動クローズ
5. **バックテスト** - 過去データでの検証
6. **ダッシュボード** - 取引履歴の可視化

## リスク・注意事項

- シミュレーション環境（/sim）で十分テストしてから本番へ
- **アクセストークンの有効期限管理**（暫定版では手動更新が必要）
- API レート制限への対応
- 市場クローズ時の挙動確認
- トークン期限切れ時は Actions が失敗する → 通知設定推奨
