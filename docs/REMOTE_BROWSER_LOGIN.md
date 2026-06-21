# スマホで Google ログイン（リモートブラウザ） — 手順

Cookie が切れたとき（数週間に一度）だけ行う。電車内・スマホからでも完結することを目指す。
背景・設計は [`nlm_auth_design.md`](nlm_auth_design.md)。

> ⚠️ Cookie / `auth.json` は **git・チャット・env に絶対に貼らない**。ここで扱うのは一過性の受け渡し。

---

## いつやるか

ワーカーが認証チェックで Cookie 無効を検知すると、対象 Issue に
**`nlm-auth-needed`** ラベルと依頼コメントが付く（チャット層がスマホへ通知）。これが合図。

`scripts/nlm_auth_status.sh` を直接叩いても確認できる:

```bash
bash scripts/nlm_auth_status.sh        # valid なら exit 0、無効なら exit 1 + 理由
```

---

## 方式 A: Browserbase ライブビュー（推奨・スマホ最適）

Free 枠で運用。`scripts/browserbase_login.py` が**単一プロセス**でセッションを保持するので、
コマンドは 1 つ。途中でブラウザを閉じない（接続が切れるとセッションが終わる）。

### 事前準備（一度きり）

1. [browserbase.com](https://www.browserbase.com) で無料登録 → API キーと Project ID を取得。
2. `.env` を設定:
   ```
   NLM_REMOTE_PROVIDER=browserbase
   BROWSERBASE_API_KEY=bb_...
   BROWSERBASE_PROJECT_ID=...
   ```
3. 依存を入れる: `pip install -r requirements.txt`（`connect_over_cdp` なので `playwright install` は不要）。

### 毎回（Cookie 切れ時のみ・数週間に一度）

```bash
bash scripts/remote_login_helper.sh start
```

1. 実行するとターミナルに **ライブビュー URL** が出る。
2. **スマホでその URL を開く** → 表示された NotebookLM/Google の画面で本物の Google ログイン（必要なら 2FA）。
3. ログインが検知されると自動で Cookie を採取 → クラウド profile に注入 →
   `header` 形式 → 失敗時 `netscape` 形式の順で試し、`nlm login --check` まで通す。
4. ワーカーが `nlm-auth-needed` を外して保留依頼を再処理（チャットに完了通知）。

待ち時間の上限は既定 600 秒（Free 枠の 1 セッション 15 分=900 秒未満）。`.env` の `BB_LOGIN_TIMEOUT` で調整可。

> ⚠️ DC IP では Google が追加確認（デバイス確認・本人確認）を出すことがある。画面の指示に従えば通る。
> 15 分で終わらず何度もコケるなら Developer プラン($20/月・6時間セッション)に上げる。
> 一度通れば数週間は再ログイン不要。

---

## 方式 B: 自前 noVNC（VPS + headful Chrome）

1. VPS で headful Chrome を起動し noVNC で公開（一度きりの構築。別途手順）。
2. スマホで noVNC URL を開く → 画面内 Chrome で NotebookLM にログイン。
3. その Chrome の Cookie を採取 → クラウド profile に注入（A の `capture` と同じ出口）。

スマホでは画面内ブラウザのピンチ操作がやや手間。コスト最小・第三者非依存が利点。

---

## 方式 C: 手動 Cookie 投入（provider 確定前のフォールバック）

リモートブラウザ基盤を用意する前でも動かせる最小手段。

1. **PC かスマホのブラウザ**で NotebookLM にログイン（普段使いのブラウザでよい）。
2. DevTools / 拡張で `batchexecute` リクエストの Cookie を採取し `cookies.txt`（Netscape 形式）に保存。
3. クラウド profile に注入:
   ```bash
   nlm login --manual --file /path/to/cookies.txt
   nlm login --check        # "Authentication valid" を確認
   rm /path/to/cookies.txt  # 受け渡しファイルは残さない
   ```

「本物の Google ログインをタップ」ではなく Cookie 受け渡し作業になる点が方式 A/B との違い。

---

## 困ったとき

- `nlm login --check` が valid にならない → ログインし直す（Cookie 期限切れ / 採取ミス）。
- Google が確認を繰り返す → 同一 provider/IP で再試行、必要なら一度 PC ブラウザで通してから Cookie を移す。
- `auth.json` がどこにあるか → `~/.notebooklm-mcp-cli/profiles/<NLM_PROFILE>/auth.json`（既定 profile 名は `default`）。
