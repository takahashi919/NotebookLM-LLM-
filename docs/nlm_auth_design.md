# NotebookLM 認証 — オンデマンド（クラウド＋スマホ承認）設計

`takahashi919/-` の `tools/hermes-core/docs/nlm_auth_design.md` を土台に、
**「常駐 Surface に認証を置く」→「必要時にユーザーへ依頼し、スマホでログイン承認」** へ作り替えた版。

---

## 0. 何を変えたか（旧 → 新）

| | 旧（hermes-core / HQ） | 新（本リポジトリ） |
|---|---|---|
| 認証の置き場 | Surface Pro 6 ローカルに常駐 | クラウド profile に**オンデマンド注入** |
| 実行者 | Surface 常駐ワーカー（cron・事前認証済み） | クラウドのワーカー（依頼時に起動） |
| 認証のきっかけ | 機の前で一度 `nlm login` | **Cookie 切れ検知 → スマホで Google ログイン承認** |
| 依頼経路 | 外出先 Issue 起票 | チャット（安価モデル）→ Issue / 承認ゲート |
| 弱点 | 常駐機が必要・外から認証し直せない | リモートブラウザ基盤が要る・DC IP ログインは追加確認が出やすい |

狙い: 常駐機を持たず、外出先のスマホだけで「依頼 → （稀に）認証 → 結果」を完結させる。

---

## 1. 技術的前提（notebooklm-mcp-cli 0.6.8 の事実）

- NotebookLM に公式 API は無い。認証 = **ブラウザ Cookie**。実体は
  `~/.notebooklm-mcp-cli/profiles/<name>/auth.json`（cookies / csrf / session_id / email）。
- ログイン方式は 2 本立て:
  - **自動モード** `nlm login` … ローカルの**表示できる**Chromium を起動してログイン。headless 不可。
  - **手動モード** `nlm login --manual --file cookies.txt` … 採取済み Cookie を**注入**。場所を選ばない。★
- Cookie は**数週間有効**（一部はリクエスト毎にローテート、csrf/session はクライアント初期化時に自動更新）。
- 一度有効な profile があれば、以後のクエリは**完全 headless で叩ける**。

> ★ クラウド headless で認証を成立させる現実的な唯一の入口が手動モード（注入）。
>   よって「スマホで本物の Google ログイン」はリモートブラウザ側で行い、
>   採取した Cookie をこの手動モードでクラウド profile に流し込む、が確実。

---

## 2. 二経路モデル

認証の「頻度」で経路を分ける。これが設計の核。

### 2-1. 頻繁な経路（毎回・認証不要）

```
スマホ チャット ──依頼──► 安価モデル(Sonnet) ──► nlm-request Issue
                                                      │
                              クラウド ワーカー ◄─────┘
                                │ profile が有効なら
                                └ nlm notebook query → docs/research/ → 結果返信 → close
```

profile が生きている限り、ユーザーは Google ログインを一切しない。

### 2-2. 稀な経路（Cookie 切れ時・数週間に一度）

```
ワーカーが認証チェックで「無効」を検知
   │  Issue に nlm-auth-needed ラベル + 依頼コメント（チャット層がスマホへ通知）
   ▼
ユーザー: スマホでリモートブラウザのライブビュー URL を開く
   │  本物の Google ログイン画面 → タップでログイン
   ▼
リモートブラウザの Cookie を採取 → クラウド profile に注入（remote_login_helper.sh）
   │  nlm login --manual --file で auth.json を更新
   ▼
ワーカー再開（nlm-auth-needed を外す）→ 保留中の依頼を処理
```

---

## 3. リモートブラウザ provider の選択（要決定）

「スマホで見える本物の Google ログイン画面」をどこに出すか。

| | A. ホスト型ライブビュー（Browserbase 等） | B. 自前 noVNC（小型 VPS + headful Chrome） |
|---|---|---|
| スマホ体感 | ◎ リンクを開くだけ・モバイル最適化 | △ 画面内ブラウザをピンチ操作 |
| 費用 | 月額小（従量） | VPS 代のみ |
| 第三者依存 | あり（一時的にセッションを預ける） | なし |
| 構築 | API/SDK 連携 | VNC/noVNC セットアップ |
| 推奨 | **電車内運用ならこちら** | コスト最小・自前主義ならこちら |

どちらでも出口は同じ（採取 Cookie → クラウド profile 注入）。`remote_login_helper.sh` は
`NLM_REMOTE_PROVIDER` で切り替えられる形にし、provider 確定までは**手動 Cookie 投入**でも動く。

### 注意（正直なリスク）

- **DC IP からの Google ログインは追加の本人確認（2FA / デバイス確認）を求められやすい**。
  初回や久々のログインで出やすい。一度通れば数週間は静か。
- リモートブラウザに一時的にでも Google セッションが乗る点は許容できる相手を選ぶこと。
- Cookie/auth.json は **git にもチャットにも絶対に載せない**（`.gitignore` 済み・`.env` も同様）。

---

## 4. 実装ファイル

| 役割 | ファイル | 状態 |
|---|---|---|
| 単発クエリ → research note | `scripts/nlm_research.sh` | 移植（認証チェック流用） |
| Issue を拾って実行（クラウド） | `scripts/nlm_request_worker.sh` | 移植＋認証切れ時シグナル化 |
| Cookie 有効性チェック | `scripts/nlm_auth_status.sh` | 新規 |
| リモート Cookie をクラウド profile に注入 | `scripts/remote_login_helper.sh` | 新規（provider 切替の骨子） |
| 依頼テンプレ | `.github/ISSUE_TEMPLATE/nlm-request.md` | 移植 |
| 確定テキストの器 | `docs/research/{README,TEMPLATE}.md` | 移植 |

---

## 5. セキュリティ鉄則（旧設計から継承）

- 認証実体（cookies/auth.json）は **git・env・チャットに一歩も出さない**。
- 「認証を base64 で書き出してどこかに貼れ」式の運び込みは**やらない**（旧設計で事故った）。
  本設計の手動注入は「リモートブラウザ → クラウド profile」への一過性の受け渡しに限定し、永続保存しない。
- Cookie 切れたら作り直す前提で運用（数週間に一度）。

---

## 6. 未決事項

1. リモートブラウザ provider（A ホスト型 / B 自前）の確定。
2. チャット層のホスト（Discord 流用 or 別チャネル）。`docs/ARCHITECTURE.md §チャット層`。
3. provider 確定後、`remote_login_helper.sh` の該当分岐を実装して疎通確認。
