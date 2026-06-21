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

## 方式 A: ホスト型ライブビュー（推奨・スマホ最適）

例: Browserbase など「ライブビュー URL を返すリモートブラウザ」。

1. ローカル/クラウドで起動側を実行（`NLM_REMOTE_PROVIDER=browserbase` を `.env` に設定済み前提）:
   ```bash
   bash scripts/remote_login_helper.sh start
   # → スマホで開くライブビュー URL を出力する
   ```
2. **スマホでその URL を開く** → NotebookLM (https://notebooklm.google.com) を開く →
   本物の Google ログイン画面でログイン（必要なら 2FA）。
3. ログインできたら、起動側で Cookie を採取してクラウド profile に注入:
   ```bash
   bash scripts/remote_login_helper.sh capture
   # → nlm login --manual --file で auth.json を更新 → nlm login --check
   ```
4. ワーカーが `nlm-auth-needed` を外して保留依頼を再処理する（チャットに完了通知）。

> DC IP では Google が追加確認（デバイス確認・本人確認）を出すことがある。画面の指示に従えば通る。
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
