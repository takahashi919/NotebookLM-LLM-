#!/usr/bin/env bash
# Cookie 有効性チェック。valid なら exit 0、無効なら exit 1（理由を stderr に）。
# チャット層・ワーカーが「スマホで Google ログインが要るか」を判断するのに使う。
#
# 使い方: bash scripts/nlm_auth_status.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "${REPO_ROOT}/.env" ] && set -a && . "${REPO_ROOT}/.env" && set +a

NLM_PROFILE="${NLM_PROFILE:-default}"
PROFILE_ARGS=()
[ "${NLM_PROFILE}" != "default" ] && PROFILE_ARGS=(--profile "${NLM_PROFILE}")

if ! command -v nlm >/dev/null 2>&1; then
  echo "[auth] INVALID: nlm コマンドが無い" >&2
  exit 1
fi

# pipefail+SIGPIPE 誤判定回避のため出力をキャプチャして判定（nlm_research.sh と同方式）
if OUT="$(nlm login --check "${PROFILE_ARGS[@]}" 2>&1)"; then RC=0; else RC=$?; fi
if [ "${RC}" -eq 0 ] && grep -q "Authentication valid" <<<"${OUT}"; then
  echo "[auth] VALID (profile: ${NLM_PROFILE})"
  exit 0
fi

echo "[auth] INVALID: Cookie 切れ/未注入。docs/REMOTE_BROWSER_LOGIN.md でスマホから更新して。" >&2
echo "${OUT}" | head -3 >&2
exit 1
