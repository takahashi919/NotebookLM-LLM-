#!/usr/bin/env bash
# Surface 常駐ワーカー（フルローカル運用）。
# ローカルで NotebookLM 認証を保ちつつ、一定間隔で既存の
# scripts/nlm_request_worker.sh を回して GitHub Issue の依頼を処理する。
#
# 位置づけ（docs/nlm_auth_design.md §0 の「旧設計＝Surface ローカル常駐」へ回帰）:
#   - 認証は常駐機ローカルで `nlm login`（表示できる Chromium）。
#     residential IP なので DC IP の追加確認が出にくく、Cookie をどこにも持ち出さない。
#   - クラウド／リモートブラウザ（Browserbase 等）不要。
#   - エンジンは既存ワーカーそのまま。本スクリプトは「常駐ループ＋ローカル認証確保」だけを足す。
#
# 使い方:
#   bash scripts/nlm_worker_daemon.sh            # フォアグラウンドで常駐ループ（Ctrl-C で停止）
#   POLL_INTERVAL=300 bash scripts/nlm_worker_daemon.sh   # ポーリング間隔(秒)を変更
#   bash scripts/nlm_worker_daemon.sh --once     # 認証確保→1巡→終了（cron 等から叩く用）
#
# 常駐化（Surface=Windows）は docs/LOCAL_WORKER.md（Task Scheduler / nohup / WSL）。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
[ -f "${REPO_ROOT}/.env" ] && set -a && . "${REPO_ROOT}/.env" && set +a

POLL_INTERVAL="${POLL_INTERVAL:-120}"   # ワーカー一巡の間隔(秒)
NLM_PROFILE="${NLM_PROFILE:-default}"
PROFILE_ARGS=()
[ "${NLM_PROFILE}" != "default" ] && PROFILE_ARGS=(--profile "${NLM_PROFILE}")

ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

for c in nlm gh git bash; do
  command -v "$c" >/dev/null 2>&1 || { echo "[daemon] ERROR: '$c' が無い（${c} を入れて）" >&2; exit 1; }
done

log() { echo "[daemon $(date '+%H:%M:%S')] $*"; }

# 認証が無効ならローカルで対話ログイン（ブラウザが開く＝機の前にいる前提）。
# 起動時に一度だけ呼ぶ。戻り値: 0=有効 / 1=無効のまま。
ensure_auth_interactive() {
  if bash scripts/nlm_auth_status.sh; then return 0; fi
  log "認証が無効。ローカルで 'nlm login' を実行します（ブラウザが開くのでログインしてください）…"
  nlm login "${PROFILE_ARGS[@]}" || true
  if bash scripts/nlm_auth_status.sh; then
    log "✅ ローカルログイン成功。Cookie は数週間有効。"
    return 0
  fi
  log "❌ ログインに失敗。'nlm login' を手動で通してから再開してください。"
  return 1
}

log "起動。profile=${NLM_PROFILE} interval=${POLL_INTERVAL}s repo=${GITHUB_REPO:-(.envのGITHUB_REPO未設定)}"

# --once: 認証を確保して一巡だけ。
if [ "${ONCE}" -eq 1 ]; then
  ensure_auth_interactive || exit 1
  bash scripts/nlm_request_worker.sh
  exit $?
fi

# 起動時に一度ログインを確保（ユーザーが起動した直後＝対話可能なタイミング）。
ensure_auth_interactive || log "認証未確立のまま常駐します。各サイクルで再確認します。"

trap 'log "停止します。"; exit 0' INT TERM

while true; do
  # ループ内では対話ログインを自動起動しない（無人時にブラウザが乱立／ハングするため）。
  # 切れていたら指示だけ出してそのサイクルはスキップ。別端末で 'nlm login' すれば次巡で回復。
  if bash scripts/nlm_auth_status.sh >/dev/null 2>&1; then
    bash scripts/nlm_request_worker.sh || log "worker が非0終了（次サイクルで再試行）。"
  else
    log "認証切れ。別端末で 'nlm login ${PROFILE_ARGS[*]}' を通してください（次巡で自動再開）。"
  fi
  sleep "${POLL_INTERVAL}"
done
