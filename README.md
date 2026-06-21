# NotebookLM-LLM — リサーチ・ナレッジ基盤

NotebookLM を「情報収集と質問応答のエンジン」として使い、**重い推論をクラウドの高価なモデルに任せず**に
セッションを回すための基盤。チャットから依頼を投げ、安価なモデル（Sonnet）が会話・Issue 起票・承認ゲートを
さばき、実際の NotebookLM クエリはワーカーが実行して確定テキストとして repo に残す。

> 既存リポ `takahashi919/-`（リサーチ会社HQ）の `tools/hermes-core` にある NotebookLM 連携を
> **流用移植**し、認証だけ「常駐 Surface 前提」→「オンデマンド（スマホ承認）」に作り替えたもの。

## やりたいこと（4本柱）

| # | 柱 | 状態 |
|---|---|---|
| 1 | **NotebookLM での情報収集 & 質問**（推論コスト削減） | 🚧 Phase 1（本リポジトリの現在地） |
| 2 | 調査内容・ナレッジの **Obsidian 連携** | 🔜 Phase 2（設計のみ） |
| 3 | **X(Twitter) ブックマーク** → やりたいことリスト追加 | 🔜 Phase 3（設計のみ） |
| 4 | 各生成AI の **API 連携** | 🔜 Phase 4（設計のみ） |

詳細・将来柱の設計は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## なぜ推論コストが下がるのか

- NotebookLM 自体が「グラウンディング済みの要約・引用つき回答」を返す（Gemini 側で実行＝こちらのトークン消費ではない）。
- チャットの受け答え・ディスパッチは**安価モデル（Sonnet）**で足りる（深い推論不要なルール処理が中心）。
- リサーチ結果は `docs/research/<topic>.md` に**確定テキスト**として残るので、以後のセッションは
  「NotebookLM を再度叩く」のではなく「ファイルを読むだけ」で済む（再現性も担保）。

## 全体フロー（Phase 1）

```
スマホ/Web のチャット
  │  「○○について調べて」
  ▼
チャット層（安価モデル Sonnet：会話・ディスパッチのみ）
  │  nlm-request Issue を起票 / 承認ゲートを提示
  ▼
GitHub Issues  ──ラベル nlm-request──►  ワーカー（クラウドで実行）
  │                                       scripts/nlm_request_worker.sh
  │                                         ├ 認証チェック
  │                                         │   ├ 有効 → nlm notebook query
  │                                         │   └ 切れ → 「要認証」シグナルを Issue に出す ┐
  │                                         ├ docs/research/<topic>.md に保存 → push      │
  │                                         └ Issue に結果コメント + nlm-done で close     │
  ▼                                                                                        │
docs/research/ の確定テキスト ──► 以後のセッションは読むだけ（NotebookLM 不要）            │
                                                                                           │
   ┌───────────────────────────────────────────────────────────────────────────────────┘
   ▼ 稀（Cookie は数週間有効）
スマホでリモートブラウザの Google ログイン（docs/REMOTE_BROWSER_LOGIN.md）
  → Cookie をクラウド profile に注入 → ワーカー再開
```

## 認証モデル（重要）

NotebookLM に公式 API は無く、認証は **ブラウザ Cookie**。クラウドの headless 環境で
「スマホからその場で Google ログイン承認」を成立させるため、本リポジトリは次を採る：

- **頻繁な依頼・承認**はチャット → Issue でクラウド内完結（認証不要）。
- **Cookie 更新（数週間に一度）**だけ、スマホでリモートブラウザの本物の Google ログインを通し、
  採取した Cookie をクラウド profile に注入する。

設計の全文は [`docs/nlm_auth_design.md`](docs/nlm_auth_design.md)、
手順は [`docs/REMOTE_BROWSER_LOGIN.md`](docs/REMOTE_BROWSER_LOGIN.md)。

## ディレクトリ

```
.github/ISSUE_TEMPLATE/nlm-request.md   ← リサーチ依頼テンプレ（チャット層／手動どちらからでも）
docs/
  ARCHITECTURE.md                       ← 全体設計・チャット層・4本柱
  nlm_auth_design.md                    ← オンデマンド認証（クラウド＋スマホ）の設計
  REMOTE_BROWSER_LOGIN.md               ← スマホで Google ログインする手順
  research/
    README.md / TEMPLATE.md             ← 確定テキストの器・規約
    <topic>.md                          ← リサーチ結果（自動生成）
scripts/
  nlm_research.sh                       ← 単発クエリ→ research note 保存（移植）
  nlm_request_worker.sh                 ← Issue を拾って実行（移植＋オンデマンド認証化）
  nlm_auth_status.sh                    ← Cookie 有効性チェック（新規）
  remote_login_helper.sh                ← リモートブラウザ Cookie をクラウド profile に注入（新規）
.env.example                            ← 環境変数のひな型
```

## セットアップ

1. `.env.example` を `.env` にコピーして埋める（`GITHUB_REPO` 等）。
2. `nlm` を入れる: `uv tool install "notebooklm-mcp-cli==0.6.8"`（`~/.local/bin` を PATH に）。
3. 初回 Cookie 投入: [`docs/REMOTE_BROWSER_LOGIN.md`](docs/REMOTE_BROWSER_LOGIN.md) に従う。
4. 疎通: `bash scripts/nlm_research.sh test <notebook_id> "テスト質問"` → `docs/research/test.md` を確認。

## 現状の到達点

- [x] Phase 1 土台（移植スクリプト・Issue テンプレ・認証設計・チャット層仕様）
- [ ] チャット層 bot の実装（仕様は `docs/ARCHITECTURE.md`。Discord/その他は要選定）
- [ ] リモートブラウザ provider の選定（ホスト型ライブビュー or 自前 noVNC）
- [ ] Phase 2〜4（Obsidian / X / 各AI API）
