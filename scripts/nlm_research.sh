#!/usr/bin/env bash
# 単発ヘルパー: 認証済み profile で NotebookLM を叩き、結果を
# docs/research/<topic>.md に確定テキストとして保存/追記する。
#
# 使い方:
#   bash scripts/nlm_research.sh <topic-slug> <notebook_id> "質問文"
#
# 前提:
#   - クラウド profile に有効な Cookie が注入済み（docs/REMOTE_BROWSER_LOGIN.md）
#   - 認証実体は git/クラウド env/チャットに絶対に載せない
#
# 移植元: takahashi919/- tools/hermes-core/scripts/nlm_research.sh
#   差分: NLM_PROFILE による profile 切替に対応（既定 default）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESEARCH_DIR="${REPO_ROOT}/docs/research"
TEMPLATE="${RESEARCH_DIR}/TEMPLATE.md"

# .env があれば読む（NLM_PROFILE 等）。コメント/空行は無視。
[ -f "${REPO_ROOT}/.env" ] && set -a && . "${REPO_ROOT}/.env" && set +a

NLM_PROFILE="${NLM_PROFILE:-default}"
PROFILE_ARGS=()
[ "${NLM_PROFILE}" != "default" ] && PROFILE_ARGS=(--profile "${NLM_PROFILE}")

if [ "$#" -lt 3 ]; then
  echo "usage: bash scripts/nlm_research.sh <topic-slug> <notebook_id> \"質問文\"" >&2
  exit 2
fi

TOPIC="$1"
NOTEBOOK_ID="$2"
QUESTION="$3"
OUT="${RESEARCH_DIR}/${TOPIC}.md"

if ! command -v nlm >/dev/null 2>&1; then
  echo "[nlm_research] ERROR: nlm コマンドが無い。'uv tool install notebooklm-mcp-cli==0.6.8' を。" >&2
  exit 1
fi

# nlm の出力を一度キャプチャしてから判定する。
# `nlm login --check | grep -q` 方式は、grep が最初の一致行でパイプを閉じ、
# その後も行を書き続ける nlm が SIGPIPE で異常終了するため、set -o pipefail 下で
# 「認証は有効なのに失敗」と誤判定していた。終了コードと文言の両方で判定する。
if NLM_CHECK_OUT="$(nlm login --check "${PROFILE_ARGS[@]}" 2>&1)"; then
  NLM_CHECK_RC=0
else
  NLM_CHECK_RC=$?
fi
if [ "${NLM_CHECK_RC}" -ne 0 ] || ! grep -q "Authentication valid" <<<"${NLM_CHECK_OUT}"; then
  echo "[nlm_research] ERROR: nlm 認証が無効。docs/REMOTE_BROWSER_LOGIN.md で Cookie を更新して。" >&2
  exit 1
fi

NLM_VER="$(nlm --version 2>&1 | head -1)"
NOW="$(date '+%Y-%m-%d %H:%M')"
TODAY="$(date '+%Y-%m-%d')"
HOST="$(hostname 2>/dev/null || echo unknown)"

echo "[nlm_research] querying notebook=${NOTEBOOK_ID} ..." >&2
# 索引化直後のノートは一時的に INVALID_ARGUMENT を返すことがある（特に Discover 由来）。
# エラー/空なら数回リトライする（成功時は即抜け）。
RAW=""
for attempt in 1 2 3 4 5; do
  RAW="$(nlm notebook query "${NOTEBOOK_ID}" "${QUESTION}" --json "${PROFILE_ARGS[@]}" 2>/dev/null || true)"
  if [ -n "${RAW}" ] && ! printf '%s' "${RAW}" | grep -q '"error"'; then
    break
  fi
  echo "[nlm_research] query 一時失敗（${attempt}/5）。待って再試行..." >&2
  sleep $((attempt * 5))
done

# --json 出力から回答本文を取り出す。スキーマ差異に備え、失敗したら生出力を残す。
ANSWER="$(printf '%s' "${RAW}" | python3 -c '
import sys, json
raw = sys.stdin.read().strip()
try:
    d = json.loads(raw)
except Exception:
    print(raw); sys.exit(0)
# nlm 0.6.8 は {"value": {"answer": ...}} 形式で返す。トップ階層と value 配下の
# 両方から本文キーを探す（将来のスキーマ差異にも備える）。
candidates = []
if isinstance(d, dict):
    candidates.append(d)
    if isinstance(d.get("value"), dict):
        candidates.append(d["value"])
for c in candidates:
    for k in ("answer", "response", "text", "output", "result"):
        v = c.get(k)
        if isinstance(v, str) and v.strip():
            print(v.strip()); sys.exit(0)
print(json.dumps(d, ensure_ascii=False, indent=2))
' 2>/dev/null || printf '%s' "${RAW}")"

if [ -z "${ANSWER}" ]; then
  echo "[nlm_research] WARNING: 空の回答。NotebookLM 側 / notebook_id を確認して。" >&2
fi

mkdir -p "${RESEARCH_DIR}"

if [ ! -f "${OUT}" ]; then
  sed \
    -e "s|<topic-slug>|${TOPIC}|g" \
    -e "s|<notebook_id>|${NOTEBOOK_ID}|g" \
    -e "s|<machine>|${HOST}|g" \
    -e "s|<YYYY-MM-DD>|${TODAY}|g" \
    -e "s|<トピック名>|${TOPIC}|g" \
    "${TEMPLATE}" > "${OUT}"
  echo "[nlm_research] created ${OUT}" >&2
fi

{
  printf '\n### Q. %s\n' "${QUESTION}"
  printf -- '- queried_at: %s\n' "${NOW}"
  printf -- '- queried_by: %s\n' "${HOST}"
  printf -- '- nlm: %s\n\n' "${NLM_VER}"
  printf '%s\n' "${ANSWER}"
  printf '\n---\n'
} >> "${OUT}"

# updated_at を更新
python3 - "$OUT" "$TODAY" <<'PY'
import sys, re
path, today = sys.argv[1], sys.argv[2]
s = open(path, encoding="utf-8").read()
s = re.sub(r'^updated_at:.*$', f'updated_at: {today}', s, count=1, flags=re.M)
open(path, "w", encoding="utf-8").write(s)
PY

echo "[nlm_research] appended → ${OUT}" >&2
echo "[nlm_research] 確認して問題なければ frontmatter を status: confirmed に上げて commit/push して。" >&2
