#!/usr/bin/env bash
# リモートブラウザでスマホから Google ログイン → 採取 Cookie をクラウド profile に注入する。
# Cookie 切れ時（数週間に一度）だけ使う。設計: docs/nlm_auth_design.md / 手順: docs/REMOTE_BROWSER_LOGIN.md
#
# 使い方:
#   bash scripts/remote_login_helper.sh start                  # provider に従いログイン採取→注入
#   bash scripts/remote_login_helper.sh login                  # start のエイリアス
#   bash scripts/remote_login_helper.sh manual <cookies.txt>   # フォールバック: 手動 Cookie 注入
#
# provider は .env の NLM_REMOTE_PROVIDER で切替: browserbase | novnc | manual
#   browserbase: scripts/browserbase_login.py を単一プロセスで実行。ライブビュー URL を出し、
#                スマホで Google ログイン → Cookie 採取 → header/netscape の順に注入を試行。
#
# ⚠️ Cookie/auth.json は git・チャット・env に絶対に載せない（一過性の受け渡しに限定）。

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
  nlm login --manual --file "${f}" "${PROFILE_ARGS[@]}" >/dev/null 2>&1 || true
  if bash "${REPO_ROOT}/scripts/nlm_auth_status.sh"; then
    echo "[login] ✅ 注入成功（${f##*.} 形式）。" >&2
    return 0
  fi
  return 1
}

# header → netscape の順に試す（nlm の --file がどちらの形式を受けるか不確実なため）。
inject_try_formats() {  # $1 = base path（browserbase_login.py が <base>.header.txt / <base>.netscape.txt を出す）
  local base="$1" ok=1
  for ext in header.txt netscape.txt; do
    if [ -f "${base}.${ext}" ]; then
      echo "[login] 注入を試行: ${base}.${ext}" >&2
      if inject_and_verify "${base}.${ext}"; then ok=0; break; fi
    fi
  done
  # 受け渡しファイルは必ず消す（認証実体を残さない）
  rm -f "${base}.header.txt" "${base}.netscape.txt"
  if [ "${ok}" -ne 0 ]; then
    echo "[login] ❌ どの形式でも注入後の認証が無効。ログイン採取をやり直して。" >&2
    return 1
  fi
  return 0
}

browserbase_flow() {
  command -v python3 >/dev/null 2>&1 || { echo "[login] ERROR: python3 が無い" >&2; return 1; }
  if [ -z "${BROWSERBASE_API_KEY:-}" ] || [ -z "${BROWSERBASE_PROJECT_ID:-}" ]; then
    echo "[login] ERROR: BROWSERBASE_API_KEY / BROWSERBASE_PROJECT_ID を .env に設定して。" >&2
    return 2
  fi
  local base; base="$(mktemp -u "${TMPDIR:-/tmp}/nlm_bb_cookies.XXXXXX")"
  # Free 枠の 15 分上限未満で待つ（既定 600s）。単一プロセスでセッションを保持。
  python3 "${REPO_ROOT}/scripts/browserbase_login.py" "${base}" --timeout "${BB_LOGIN_TIMEOUT:-600}" || {
    rm -f "${base}".*; echo "[login] ❌ Browserbase ログイン採取に失敗。" >&2; return 1; }
  inject_try_formats "${base}"
}

case "${ACTION}" in
  start|login)
    case "${NLM_REMOTE_PROVIDER}" in
      browserbase)
        browserbase_flow
        ;;
      novnc)
        echo "[login] noVNC を開いてください: ${NOVNC_URL:-<NOVNC_URL 未設定>}" >&2
        echo "[login] 画面内 Chrome で NotebookLM にログイン後、採取 cookies で manual 注入:" >&2
        echo "        bash scripts/remote_login_helper.sh manual <cookies.txt>" >&2
        ;;
      *)
        echo "[login] NLM_REMOTE_PROVIDER=${NLM_REMOTE_PROVIDER}。browserbase なら .env を埋めて再実行、" >&2
        echo "        または手動: bash scripts/remote_login_helper.sh manual <cookies.txt>  (docs/REMOTE_BROWSER_LOGIN.md 方式C)" >&2
        exit 2
        ;;
    esac
    ;;

  manual)
    FILE="${2:-}"
    [ -z "${FILE}" ] && { echo "usage: bash scripts/remote_login_helper.sh manual <cookies.txt>" >&2; exit 2; }
    inject_and_verify "${FILE}" && echo "[login] 受け渡しファイルを削除してください: rm ${FILE}" >&2
    ;;

  *)
    echo "usage: bash scripts/remote_login_helper.sh {start|login|manual <cookies.txt>}" >&2
    echo "  start/login : NLM_REMOTE_PROVIDER に従いリモートブラウザでログイン採取→profile 注入" >&2
    echo "  manual      : 採取済み cookies ファイルを注入（フォールバック）" >&2
    exit 2
    ;;
esac
