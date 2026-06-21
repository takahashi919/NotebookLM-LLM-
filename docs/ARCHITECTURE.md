# アーキテクチャ — チャット層・ディスパッチ・4本柱

## 0. 設計原則

- **層を疎結合に**: 知識本体は常に git（`docs/research/`）に残し、どの層も差し替え・撤去できる。
  チャット層も「窓口とディスパッチ」に過ぎない状態を保つ（`takahashi919/-` の卒業可能性原則を継承）。
- **推論コストを最小化**: 重い思考は NotebookLM(Gemini 側) に寄せ、チャット層は安価モデルでルール処理に徹する。
- **認証はクラウドに常駐させない**: オンデマンド注入（`nlm_auth_design.md`）。

---

## 1. 三層

```
チャット層     安価モデル(Sonnet)：会話・依頼受付・Issue 起票・承認ゲート提示
   │ GitHub Issues（依頼票・承認・通知の SSOT）
実行層         クラウド ワーカー：scripts/nlm_request_worker.sh（nlm 実行・保存・close）
   │ git（docs/research/ の確定テキスト）
記憶層         docs/research/<topic>.md：以後のセッションは読むだけ
```

GitHub Issues を**唯一の連絡板**にすることで、チャット層・実行層・通知が疎結合になる
（チャット層を撤去しても Issue 手起票で同じ流れが回る＝卒業可能）。

---

## 2. チャット層（仕様 / 未実装）

> 既存 `takahashi919/-` の `tools/hermes-core/scripts/hermes_discord_bot.py`（Ruka）が同型の参考実装。
> あれは Discord + Gemini Flash で「会話・Issue 起票・close 検知通知」を担う。これを本リポジトリ向けに流用する。

### 役割（深い推論は不要）

1. **会話受付**: 「○○を調べて」を安価モデル(Sonnet)で解釈し、topic-slug と質問群に整形。
2. **Issue 起票**: `nlm-request` ラベルで依頼票を作る（テンプレ `.github/ISSUE_TEMPLATE/nlm-request.md` 準拠）。
3. **承認ゲート**: 破壊的・外向き・コスト発生の操作は実行前にスマホへ承認を出す（下記）。
4. **通知**: Issue が `nlm-done` で close されたら結果をチャットへ。`nlm-auth-needed` が付いたら
   「スマホで Google ログインして」をリモートブラウザ URL 付きで通知（`REMOTE_BROWSER_LOGIN.md`）。

### モデル方針

- 受け答え・ディスパッチ＝**Sonnet**（安価・十分）。深い推論や長文生成は持たせない。
- NotebookLM が返す回答自体は Gemini 側の生成なので、こちらのトークンを消費しない。

### 承認ゲートの対象（スマホで Yes/No）

| 操作 | 承認 |
|---|---|
| NotebookLM へのクエリ実行 | 既定は不要（読み取り中心・低コスト）。新規ノート自動作成や大量ソース収集は要承認 |
| Google ログイン（Cookie 更新） | 必須（スマホで本物のログイン操作） |
| 外向き発信（Phase 3 の X 投稿等） | 必須 |
| API コスト発生（Phase 4 の有料 API） | 既定で要承認（しきい値設定可） |

### ホスト（未決）

- 案1: Discord bot 流用（`hermes_discord_bot.py` を移植）。スマホアプリで承認が押せて実績あり。
- 案2: 別チャネル（LINE/Slack/Web）。要追加実装。
- → `nlm_auth_design.md §6` の未決事項として保留。まず Issue 手起票でも全フローが回ることを担保する。

---

## 3. 実行層（実装済みの移植スクリプト）

| ファイル | 役割 |
|---|---|
| `scripts/nlm_request_worker.sh` | `nlm-request` Issue を一巡処理。認証切れ時は `nlm-auth-needed` を出して停止（事故防止） |
| `scripts/nlm_research.sh` | 単発クエリ → `docs/research/<topic>.md` に追記 |
| `scripts/nlm_auth_status.sh` | Cookie 有効性チェック（valid:0 / invalid:1） |
| `scripts/remote_login_helper.sh` | リモートブラウザ Cookie をクラウド profile に注入（provider 切替） |

旧 hermes との差分は **認証前提のみ**（常駐 Surface → オンデマンド）。クエリ・保存・Issue 連携のロジックは流用。

---

## 4. 記憶層（確定テキスト）

`docs/research/<topic>.md`（`TEMPLATE.md` 準拠）。frontmatter の `status: draft → confirmed` を
人手の事実確認で上げる。**本番利用では NotebookLM を再度叩かず、この確定テキストを読む**（再現性）。

将来、Phase 2 で同じ Markdown を Obsidian Vault へ同期する（下記）。

---

## 5. 将来の柱（設計のみ・未実装）

### Phase 2: Obsidian 連携

- `docs/research/*.md` を Obsidian Vault に同期（双方向 or 片方向）。
- 候補: (a) Vault を本 repo のサブフォルダにして Obsidian Git で同期、(b) Obsidian Local REST API へ push。
- frontmatter（topic/status/notebook_id）をそのまま Obsidian のプロパティに使える設計。

### Phase 3: X(Twitter) ブックマーク → やりたいことリスト

- X API v2 の Bookmarks endpoint（要 OAuth2 ユーザーコンテキスト）でブックマークを取得。
- 取り込んだ各件を「やりたいことリスト」（Issue or `docs/todo/` or Obsidian）に追加。
- 外向き操作（投稿）は承認ゲート必須。読み取り（ブックマーク取得）は定期同期でよい。

### Phase 4: 各生成AI の API 連携

- Claude / Gemini / OpenAI 等を用途別に使い分け（安価モデルは会話、要約・整形は中位、画像は専用）。
- キーは `.env`（`.gitignore` 済み）。コスト発生呼び出しは承認ゲート/しきい値で制御。
- 既存 `takahashi919/-` の `scripts/env_keys.py` / `smoke_test_apis.py` が参考。

---

## 6. 連絡板スキーマ（Issue ラベル）

| ラベル | 意味 |
|---|---|
| `nlm-request` | リサーチ依頼（ワーカーが拾う） |
| `nlm-done` | リサーチ完了（close 済み） |
| `nlm-auth-needed` | Cookie 切れ。スマホで Google ログインが必要 |

ワーカーが起動時にラベルを自動作成する（`gh label create ... || true`）。
