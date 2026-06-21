# ローカル常駐ワーカー（Surface 常駐運用） — 手順

`docs/nlm_auth_design.md` の二経路モデルのうち、**フルローカル**で回す版。
認証もワーカーも常駐機（Surface）で動かす。リモートブラウザ（Browserbase 等）は使わない。

なぜローカルか:
- 認証は `nlm login` 一発（residential IP・あなたがログイン済みの実ブラウザ）。
  DC IP の追加確認なし／ライブビューのキーボード問題なし／Cookie の受け渡しなし。
- Cookie / `auth.json` は端末から一歩も出ない（設計 §5 の鉄則を満たす）。

トレードオフ: **常時起動の Surface が必要**。機が寝ていると Issue は処理されない。
認証は数週間に一度、機の前で `nlm login` を通すだけ。

---

## 構成

```
GitHub Issue (nlm-request ラベル)
        ▲ 依頼（スマホからでも起票可）
        │
   ┌────┴───────────────────────────────────┐
   │ Surface（常駐）                          │
   │  nlm_worker_daemon.sh                    │
   │    ├ 起動時: nlm login（無効なら対話）    │
   │    └ ループ: 認証チェック → 既存ワーカー  │
   │         scripts/nlm_request_worker.sh    │
   │           └ nlm notebook query → push    │
   └──────────────────────────────────────────┘
```

エンジンは既存の `scripts/nlm_request_worker.sh` をそのまま使う。
`nlm_worker_daemon.sh` は「常駐ループ＋ローカル認証の確保」だけを足したラッパ。

---

## 事前準備（一度きり）

1. 依存を入れる: `pip install -r requirements.txt` と `nlm`（notebooklm-mcp-cli）。
2. `gh auth login` で GitHub CLI を認証。
3. `.env` を用意（`.env.example` をコピー）。最低限:
   ```
   GITHUB_REPO=takahashi919/NotebookLM-LLM-
   RESEARCH_BRANCH=<結果を push するブランチ>
   NLM_PROFILE=default
   POLL_INTERVAL=120
   NLM_REMOTE_PROVIDER=none   # フルローカルなのでリモートブラウザは使わない
   ```
4. 初回ログイン: `nlm login`（ブラウザが開く → Google ログイン → "Authentication valid"）。
   確認: `bash scripts/nlm_auth_status.sh`（VALID なら OK）。

---

## 起動

```bash
# フォアグラウンドで常駐（Ctrl-C で停止）
bash scripts/nlm_worker_daemon.sh

# 間隔を変える
POLL_INTERVAL=300 bash scripts/nlm_worker_daemon.sh

# 1巡だけ（cron / Task Scheduler から定期起動する場合）
bash scripts/nlm_worker_daemon.sh --once
```

挙動:
- **起動時**に認証が無効なら `nlm login` を対話実行（機の前にいる前提）。
- **ループ中**は認証を確認するだけ。切れていたらブラウザを自動で開かず、ログに
  「別端末で `nlm login` を通して」と出してそのサイクルをスキップ。別端末でログインすれば次巡で自動再開。
- 既存ワーカーが Issue を一巡処理 → `POLL_INTERVAL` 秒待って繰り返す。

---

## 常駐化（Surface = Windows）

Surface は Windows。以下のいずれかで常駐させる。

### A. Git Bash + nohup（手軽）

```bash
nohup bash scripts/nlm_worker_daemon.sh > daemon.log 2>&1 &
tail -f daemon.log
```

ログオフで止まる。常時運用ならログオン維持か下の方式へ。

### B. Windows タスクスケジューラ（ログオン時に自動起動・推奨）

1. タスクスケジューラ → 「タスクの作成」。
2. トリガー: 「ログオン時」。
3. 操作: プログラム `C:\Program Files\Git\bin\bash.exe`、
   引数 `-lc "cd /c/path/to/NotebookLM-LLM- && bash scripts/nlm_worker_daemon.sh"`。
4. 「最上位の特権で実行」は不要。電源設定でスリープを抑止しておくと取りこぼしが減る。

定期起動だけでよければ、`--once` を 5〜10 分間隔のトリガーで回す構成でも可。

### C. WSL（systemd / cron）

WSL を使うなら Linux と同様に systemd サービス化、または cron で `--once` を回す。

---

## 困ったとき

- `nlm_auth_status.sh` が VALID にならない → `nlm login` をやり直す（Cookie 期限切れ/採取ミス）。
- ワーカーが何もしない → `nlm-request` ラベルの open Issue があるか、`RESEARCH_BRANCH` が正しいか確認。
- `auth.json` の場所 → `~/.notebooklm-mcp-cli/profiles/<NLM_PROFILE>/auth.json`（既定 `default`）。
- スマホだけで認証し直したい（機に戻れない）→ リモートブラウザ方式（`docs/REMOTE_BROWSER_LOGIN.md`）に切替。
  フルローカルとは併用せず、どちらかに寄せる。
