# Auto Trade Cloud 設計書 - Phase 0（最小構成）

## 概要

GitHub Actions + Claude Code Actions で `/saxo-auto-trade` を定期実行する最小構成。
トークンリフレッシュは行わず、アクセストークンを Secrets から直接取得する。

## 制約事項

- アクセストークンの有効期限（24時間）を超えると手動更新が必要
- 本番運用前の検証用途を想定

## 要件

| 項目 | 仕様 |
|------|------|
| 対象銘柄 | USD/JPY 固定 |
| 発注量 | 残高の 10% |
| 実行頻度 | 1時間ごと (cron) |
| 損切り | なし |
| ユーザー確認 | なし（AI判断で自動発注） |
| トークン管理 | 手動（Secrets 直接指定） |

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions (cron: 毎時0分)                              │
│                                                             │
│  1. Checkout                                                │
│  2. .env 作成（Secrets → SAXO_ACCESS_TOKEN）                │
│  3. Claude Code Actions 実行                                 │
│       ├─ データ取得 (Yahoo Finance)                         │
│       ├─ RSI 計算                                           │
│       ├─ リアルタイム価格取得 (Saxo)                         │
│       ├─ OpenAI API で AI分析（トレンド・リスク）            │
│       ├─ ルールベース + AI → go / not_order 判断            │
│       └─ go なら自動発注                                    │
└─────────────────────────────────────────────────────────────┘
```

## GitHub Actions Workflow

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
          echo "OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }}" >> .env

      - name: Run Auto Trade
        uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            /saxo-auto-trade --auto
            対象: USD/JPY
            発注量: 残高の10%
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

## Secrets

| Secret Name | 説明 |
|-------------|------|
| `OPENAI_API_KEY` | OpenAI API キー（ChatGPT） |
| `SAXO_ACCESS_TOKEN` | Saxo アクセストークン（手動更新） |

## スキル改修

**ファイル:** `.claude/skills/saxo-auto-trade.md`

`--auto` フラグ追加:
- AskUserQuestion をスキップ
- 判断結果を JSON 出力
- `go` なら自動発注

**判断結果:**
```json
{
  "decision": "go",
  "symbol": "USDJPY",
  "action": "Buy",
  "amount": 10000,
  "rsi": 28.5,
  "rule_signal": "Buy",
  "ai_analysis": {
    "trend": "下降トレンド終盤",
    "risk": "low",
    "comment": "反発の兆候あり"
  },
  "reason": "RSI=28.5 < 30, AI分析: 低リスク"
}
```

## 判断ロジック

### ルールベース（80%）

| RSI | 状態 | 判断 |
|-----|------|------|
| > 70 | 買われすぎ | Sell → `go` |
| < 30 | 売られすぎ | Buy → `go` |
| 30-70 | 中立 | `not_order` |

### AI分析（20%）

OpenAI API (ChatGPT) に以下を問い合わせ、総合判断に反映:

| 分析項目 | 内容 |
|----------|------|
| 価格トレンド | 直近の高値・安値の推移 |
| ボラティリティ | 価格変動の大きさ |
| 異常検出 | 急騰・急落等のリスク |

**判断フロー:**
```
1. RSI でルールベース判断
2. Claude API でトレンド・リスク分析
3. RSI が go でも、AI が高リスク検出 → not_order にオーバーライド可
4. 最終判断を出力
```

## 実装タスク

- [x] `.claude/commands/saxo-auto-trade.md` に `--auto` モード追加
- [x] `scripts/saxo/get-balance.sh` 作成（残高10%計算用）
- [x] `scripts/ai/analyze-trade.sh` 作成（OpenAI API）
- [x] `.github/workflows/auto-trade.yml` 作成
- [ ] GitHub Secrets 設定（OPENAI_API_KEY, SAXO_ACCESS_TOKEN）
- [ ] 手動実行でテスト（GitHub Actions）
- [ ] cron 有効化

## ファイル構成

```
bogota/
├── .github/
│   └── workflows/
│       └── auto-trade.yml
├── .claude/
│   └── commands/
│       └── saxo-auto-trade.md  # --auto 対応
├── scripts/
│   ├── ai/
│   │   └── analyze-trade.sh    # OpenAI API 呼び出し
│   └── saxo/
│       └── get-balance.sh      # 残高取得
└── spec/
    ├── auto-trade-cloud.md         # Phase 1 設計
    └── auto-trade-cloud-phase0.md  # この設計書
```

## トークン更新手順（手動）

1. Saxo Developer Portal にログイン
2. 24-hour Token を再取得
3. GitHub リポジトリ → Settings → Secrets and variables → Actions
4. `SAXO_ACCESS_TOKEN` を更新

## 次のフェーズへ

Phase 0 で動作確認後、Phase 1（リフレッシュトークン対応）へ移行:
- `refresh-token.sh` 追加
- Secrets に APP_KEY, APP_SECRET, REFRESH_TOKEN 追加
- ワークフロー冒頭でトークンリフレッシュ
