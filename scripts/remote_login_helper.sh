#!/usr/bin/env bash
# リモートブラウザでスマホから Google ログイン → 採取 Cookie をクラウド profile に注入する。
# Cookie 切れ時（数週間に一度）だけ使う。設計: docs/nlm_auth_design.md / 手順: docs/REMOTE_BROWSER_LOGIN.md
#
# 使い方:
#   bash scripts/remote_login_helper.sh start     # スマホで開くライブビュー URL を出す
#   bash scripts/remote_login_helper.sh capture    # ログイン後、Cookie を profile に注入
#   bash scripts/remote_login_helper.sh manual <cookies.txt>   # フォールバック: 手動 Cookie 注入
#
# provider は .env の NLM_REMOTE_PROVIDER で切替: manual | browserbase | novnc
#
# ⚠️ Cookie/auth.json は git・チャット・env に絶対に載せない（一過性の受け渡しに限定）。
#
# 状態: browserbase / novnc 分岐は provider 確定後に実装する骨子。manual は今すぐ使える。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${REPO_ROOT}/.env" ] && set -a && . "${REPO_ROOT}/.env" && set +a

NLM_PROFILE="${NLM_PROFILE:-default}"
NLM_REMOTE_PROVIDER="${NLM_REMOTE_PROVIDER:-manual}"
PROFILE_ARGS=()
[ "${NLM_PROFILE}" != "default" ] && PROFILE_ARGS=(--profile "${NLM_PROFILE}")

ACTION="${1:-}"

command -v nlm >/dev/null 2>&1 || { echo "[login] ERROR: nlm が無い" >&2; exit 1; }

inject_and_verify() {  # $1 = cookies file
  local f="$1"
  [ -f "${f}" ] || { echo "[login] ERROR: cookies ファイルが無い: ${f}" >&2; return 1; }
  nlm login --manual --file "${f}" "${PROFILE_ARGS[@]}"
  if bash "${REPO_ROOT}/scripts/nlm_auth_status.sh"; then
    echo "[login] ✅ 注入成功。受け渡しファイルを削除してください: rm ${f}" >&2
    return 0
  fi
  echo "[login] ❌ 注入後も無効。Cookie の採取をやり直して。" >&2
  return 1
}

case "${ACTION}" in
  start)
    case "${NLM_REMOTE_PROVIDER}" in
      browserbase)
        # TODO(provider確定後): Browserbase セッションを作りライブビュー URL を出力する。
        #   BROWSERBASE_API_KEY / BROWSERBASE_PROJECT_ID を使用。
        #   出した URL をスマホで開き、NotebookLM(https://notebooklm.google.com) にログイン。
        echo "[login] browserbase 分岐は未実装。.env を埋めたうえで実装してください（docs/nlm_auth_design.md §3）。" >&2
        echo "[login] 暫定: manual モードを使ってください → bash scripts/remote_login_helper.sh manual <cookies.txt>" >&2
        exit 2
        ;;
      novnc)
        echo "[login] noVNC を開いてください: ${NOVNC_URL:-<NOVNC_URL 未設定>}" >&2
        echo "[login] 画面内 Chrome で NotebookLM にログイン後、capture を実行: bash scripts/remote_login_helper.sh capture" >&2
        ;;
      *)
        echo "[login] NLM_REMOTE_PROVIDER=${NLM_REMOTE_PROVIDER}。manual フォールバックを使ってください:" >&2
        echo "        bash scripts/remote_login_helper.sh manual <cookies.txt>  (docs/REMOTE_BROWSER_LOGIN.md 方式C)" >&2
        ;;
    esac
    ;;

  capture)
    # リモートブラウザから採取した Cookie を一時ファイル経由で注入する。
    # provider 連携が実装されるまでは、採取済み cookies.txt のパスを CAPTURED_COOKIES で渡す。
    CAP="${CAPTURED_COOKIES:-}"
    if [ -z "${CAP}" ]; then
      echo "[login] capture: CAPTURED_COOKIES=<cookies.txt> を指定するか、manual サブコマンドを使ってください。" >&2
      exit 2
    fi
    inject_and_verify "${CAP}"
    ;;

  manual)
    FILE="${2:-}"
    [ -z "${FILE}" ] && { echo "usage: bash scripts/remote_login_helper.sh manual <cookies.txt>" >&2; exit 2; }
    inject_and_verify "${FILE}"
    ;;

  *)
    echo "usage: bash scripts/remote_login_helper.sh {start|capture|manual <cookies.txt>}" >&2
    exit 2
    ;;
esac
