# 引き継ぎ資料 — ローカル常駐ワーカー方針への切替（session: remote-login-helper）

対象ブランチ: `claude/remote-login-helper-7ev3r8`
作成日: 2026-06-21

元セッション（既存ワーカーの文脈を持つ側）に戻る前提の引き継ぎメモ。

---

## 1. このセッションで起きたこと（経緯）

1. `bash scripts/remote_login_helper.sh start`（Browserbase ライブビュー方式）を実行。
   - 1回目: ライブビュー URL は出たが、約5分後に
     `TargetClosedError: BrowserContext.cookies: Target page, context or browser has been closed`
     でセッションが落ち、Cookie 採取失敗（`browserbase_login.py:157`）。
   - 原因候補: スマホでのログイン未完了 / Browserbase Free 枠のセッション早期回収。
2. スマホのライブビュー（devtools screencast）で **ソフトキーボードが出ない**問題が発覚。
   - iOS Safari 等で起きる Browserbase 側の制約。タップ誘発・画面回転でも出ず。
3. 回避策を検討:
   - 自動入力（Playwright で email/password を流し込む）→ **却下**。
     パスワードをチャットに出す必要があり設計 §5 違反、かつ Google が DC IP の自動ログインを
     強くブロック（CAPTCHA/デバイス確認）するため非現実的。
   - 手動 Cookie 注入（方式C）→ HttpOnly Cookie が必要で、かつクラウドコンテナへ渡すには
     チャット貼り付けが必要になり、これも設計鉄則と衝突。
4. **方針決定: フルローカル（Surface 常駐）へ回帰**（`docs/nlm_auth_design.md` §0 の旧設計）。
   ユーザー選択 = 「現状の nlm_request_worker を使う方針」。

---

## 2. このブランチでの成果物（commit: d551a56）

| ファイル | 内容 |
|---|---|
| `scripts/nlm_worker_daemon.sh`（新規） | 既存 `nlm_request_worker.sh` をエンジンに、常駐ループ＋ローカル `nlm login` 認証確保を被せたラッパ。`--once` あり。 |
| `.env.example`（変更） | `POLL_INTERVAL` 追加。フルローカル時 `NLM_REMOTE_PROVIDER=none` の注記。 |
| `docs/LOCAL_WORKER.md`（新規） | Surface での起動・常駐化（Task Scheduler/nohup/WSL）手順。 |

`nlm_worker_daemon.sh` の挙動:
- 起動時に認証無効なら `nlm login`（対話・実ブラウザ）を実行。
- ループ: `POLL_INTERVAL`(既定120s) ごとに `nlm_auth_status.sh` 確認 → 既存ワーカー一巡。
  認証切れ時はブラウザを自動起動せず（無人乱立防止）、ログで手動 `nlm login` を促す。

---

## 3. ⚠️ 元セッションと要すり合わせ（重要）

- 本セッションで読んだ `scripts/nlm_request_worker.sh` は **単発実行型（一巡して終了）** で、
  5分おきのループは内蔵していなかった。
- ユーザー談「既存ワーカーは既に5分おきに承認通しに行く仕組みがある」が事実なら、それは
  **元セッション側の外部スケジューラ（cron / Task Scheduler）か別バージョン**で実現されている。
- → その場合、今回足した `nlm_worker_daemon.sh` の常駐ループは **既存の5分間隔機構と重複**する。
  戻ったら次を確認・決定すること:
  1. 既存の「5分おき承認/実行」はどこで定義されているか（cron? Task Scheduler? 別スクリプト?）。
  2. `nlm_worker_daemon.sh` のループを使うか、既存スケジューラ＋`--once` だけ使うか、片方に寄せる。
     - 既存スケジューラを生かすなら: 本デーモンは使わず、スケジューラから
       `bash scripts/nlm_worker_daemon.sh --once`（認証確保＋一巡）を5分間隔で叩く形が綺麗。
  3. 認証切れ通知の経路（既存はラベル `nlm-auth-needed`＋コメント）とローカル `nlm login` 前提の
     整合（フルローカルではリモートブラウザ手順の案内文が実態と合わない可能性）。

---

## 4. 未決・TODO

- [ ] 既存「5分おき」機構の所在を特定し、デーモン or `--once` のどちらに統一するか決定。
- [ ] フルローカル確定なら、ワーカー内の認証切れコメント文（現状リモートブラウザ手順を案内）を
      ローカル `nlm login` 案内へ寄せるか検討（既存ワーカーは今回未改変）。
- [ ] `NLM_REMOTE_PROVIDER` を実運用で `none` に。Browserbase 関連は当面フォールバック扱い。
- [ ] Surface での常駐化方式の確定（Task Scheduler ログオン起動が手軽）。

---

## 5. 関連ファイル早見

- 設計: `docs/nlm_auth_design.md` / リモート手順: `docs/REMOTE_BROWSER_LOGIN.md`
- ローカル運用: `docs/LOCAL_WORKER.md`（今回追加）
- エンジン: `scripts/nlm_request_worker.sh`（未改変）
- 認証確認: `scripts/nlm_auth_status.sh` / 単発クエリ: `scripts/nlm_research.sh`
- 常駐ラッパ: `scripts/nlm_worker_daemon.sh`（今回追加）
