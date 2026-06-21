#!/usr/bin/env bash
# ワーカー: GitHub Issues のラベル nlm-request を拾い、NotebookLM を叩いて
# docs/research/<topic>.md に保存・push し、issue に結果を返信して close する。
# クラウドセッションで実行する想定（認証はオンデマンド注入。常駐機は不要）。
#
# 移植元: takahashi919/- tools/hermes-core/scripts/nlm_request_worker.sh
#   差分: ① 認証切れ時は hard exit せず nlm-auth-needed ラベル+依頼コメントを出して停止
#         ② HQ 固有の script-gate / 動画パイプライン連携を除去（Phase 1 はリサーチに集中）
#         ③ NLM_PROFILE 対応
#
# notebook_id の解釈:
#   - 実ID(UUID)         … 既存ノートにそのまま query
#   - NEW（大文字）       … ノートを自動作成し Discover Sources で収集してから query
#   - 空 + `discover: true` … 同上（明示オプトイン時のみ）
# 自動作成時の任意行: title:（ノート名）/ seed:（探索クエリ）/ sources:（URL/YouTube を改行で）
#
# 前提: gh 認証済み / クラウド profile に有効な Cookie / 作業ツリー内で実行
# 使い方: bash scripts/nlm_request_worker.sh   （開いている依頼を一巡処理して終了）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
[ -f "${REPO_ROOT}/.env" ] && set -a && . "${REPO_ROOT}/.env" && set +a

LABEL_REQ="nlm-request"
LABEL_DONE="nlm-done"
LABEL_AUTH="nlm-auth-needed"
BRANCH="${RESEARCH_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
RESEARCH_TIMEOUT="${RESEARCH_TIMEOUT:-300}"   # Deep research 完了待ちの上限(秒)
NLM_PROFILE="${NLM_PROFILE:-default}"
PROFILE_ARGS=()
[ "${NLM_PROFILE}" != "default" ] && PROFILE_ARGS=(--profile "${NLM_PROFILE}")

for c in gh nlm git python3 timeout; do
  command -v "$c" >/dev/null 2>&1 || { echo "[worker] ERROR: '$c' が無い" >&2; exit 1; }
done

gh label create "${LABEL_REQ}"  --color FFA500 --description "NotebookLM リサーチ依頼" >/dev/null 2>&1 || true
gh label create "${LABEL_DONE}" --color 0E8A16 --description "NotebookLM リサーチ完了"   >/dev/null 2>&1 || true
gh label create "${LABEL_AUTH}" --color B60205 --description "Cookie切れ：スマホでGoogleログイン要" >/dev/null 2>&1 || true

push_retry() {
  local n=0 delay=2
  until git push -u origin "${BRANCH}"; do
    n=$((n+1)); [ "$n" -ge 4 ] && return 1
    echo "[worker] push 失敗。${delay}s 後に再試行..." >&2; sleep "${delay}"; delay=$((delay*2))
  done
}

# Issue コメントに残した「作成済みノートID」マーカーを拾う（再入時に再利用＝多重作成防止）
get_recorded_notebook() {
  gh issue view "$1" --json comments --jq '.comments[].body' 2>/dev/null \
    | grep -oE 'AUTO_NOTEBOOK_ID: [0-9a-fA-F-]{36}' | head -1 | awk '{print $2}' || true
}

extract_uuid() { grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true; }

# 軽いクエリでノートが使える状態か判定（INVALID_ARGUMENT 等なら false）
notebook_queryable() {
  local out
  out="$(nlm notebook query "$1" "ready?" --json "${PROFILE_ARGS[@]}" 2>&1 || true)"
  if printf '%s' "$out" | grep -q '"error"'; then return 1; fi
  if printf '%s' "$out" | grep -qiE '"answer"|"value"'; then return 0; fi
  return 1
}

ISSUES_JSON="$(gh issue list --label "${LABEL_REQ}" --state open --json number,body --limit 50)"
COUNT="$(printf '%s' "${ISSUES_JSON}" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')"
echo "[worker] open requests: ${COUNT}"
[ "${COUNT}" = "0" ] && exit 0

# ===== 認証チェック（オンデマンド）=====
# 切れていたら hard exit せず、開いている依頼すべてに nlm-auth-needed を付けて停止。
# チャット層がこのラベルを検知して「スマホで Google ログインして」を通知する。
if ! bash scripts/nlm_auth_status.sh; then
  echo "[worker] 認証無効。nlm-auth-needed を付けて停止する。" >&2
  for i in $(seq 0 $((COUNT-1))); do
    NUM="$(printf '%s' "${ISSUES_JSON}" | python3 -c "import sys,json;print(json.load(sys.stdin)[$i]['number'])")"
    # 二重通知を避ける: 既に auth ラベルが付いていればコメントしない
    if ! gh issue view "${NUM}" --json labels --jq '.labels[].name' 2>/dev/null | grep -qx "${LABEL_AUTH}"; then
      gh issue edit "${NUM}" --add-label "${LABEL_AUTH}" >/dev/null 2>&1 || true
      gh issue comment "${NUM}" --body "🔑 NotebookLM の Cookie が切れています。スマホでリモートブラウザの Google ログインを通してください（手順: \`docs/REMOTE_BROWSER_LOGIN.md\`）。更新後にこの依頼を自動で再処理します。" || true
    fi
  done
  exit 0
fi

for i in $(seq 0 $((COUNT-1))); do
  NUM="$(printf '%s' "${ISSUES_JSON}"  | python3 -c "import sys,json;print(json.load(sys.stdin)[$i]['number'])")"
  BODY="$(printf '%s' "${ISSUES_JSON}" | python3 -c "import sys,json;print(json.load(sys.stdin)[$i]['body'])")"

  # 認証回復後の再入では auth ラベルを外す
  gh issue edit "${NUM}" --remove-label "${LABEL_AUTH}" >/dev/null 2>&1 || true

  # 任意フィールドは無いことがある。grep 不一致で set -e+pipefail に落ちないよう各行 || true。
  NOTEBOOK_ID="$(printf '%s' "${BODY}" | grep -iE '^notebook_id:' | head -1 | sed -E 's/^notebook_id:[[:space:]]*//' | tr -d '\r' || true)"
  TOPIC="$(printf '%s' "${BODY}"       | grep -iE '^topic:'       | head -1 | sed -E 's/^topic:[[:space:]]*//'       | tr -d '\r' || true)"
  TITLE="$(printf '%s' "${BODY}"       | grep -iE '^title:'       | head -1 | sed -E 's/^title:[[:space:]]*//'       | tr -d '\r' || true)"
  SEED="$(printf '%s' "${BODY}"        | grep -iE '^seed:'        | head -1 | sed -E 's/^seed:[[:space:]]*//'        | tr -d '\r' || true)"
  DISCOVER="$(printf '%s' "${BODY}"    | grep -iE '^discover:'    | head -1 | sed -E 's/^discover:[[:space:]]*//'    | tr -d '\r' | tr 'A-Z' 'a-z' || true)"
  mapfile -t SOURCE_URLS < <(printf '%s' "${BODY}" | sed -n '/^[Ss]ources:/,$p' | grep -oE 'https?://[^[:space:]]+' | tr -d '\r' || true)

  # topic は必須
  if [ -z "${TOPIC}" ] || printf '%s' "${TOPIC}" | grep -q '<'; then
    echo "[worker] #${NUM}: topic を読めない。スキップ。" >&2
    gh issue comment "${NUM}" --body "⚠️ topic を読み取れませんでした。テンプレの値を埋め直してください。" || true
    continue
  fi

  # 自動作成モード判定（明示オプトインのみ）
  AUTO_MODE=0
  if [ "${NOTEBOOK_ID}" = "NEW" ] || { [ -z "${NOTEBOOK_ID}" ] && [ "${DISCOVER}" = "true" ]; }; then
    AUTO_MODE=1
  fi
  if [ "${AUTO_MODE}" -eq 0 ]; then
    if [ -z "${NOTEBOOK_ID}" ] || printf '%s' "${NOTEBOOK_ID}" | grep -q '<'; then
      echo "[worker] #${NUM}: notebook_id を読めない。スキップ。" >&2
      gh issue comment "${NUM}" --body "⚠️ notebook_id を読み取れませんでした。自動作成したい場合は \`notebook_id: NEW\` にしてください。" || true
      continue
    fi
  fi

  # 質問収集。ASCII マーカー範囲を優先、無ければ「## 質問」見出し配下の箇条書き。
  mapfile -t QUESTIONS < <(
    printf '%s' "${BODY}" \
      | awk '
          /NLM_QUESTIONS_START/ { in_q=1; seen_marker=1; next }
          /NLM_QUESTIONS_END/ && seen_marker { exit }
          !seen_marker && /^##[ \t]*質問/ { in_q=1; next }
          !seen_marker && /^##[ \t]*/ && in_q { exit }
          in_q && /^ *- +/ {
            sub(/^ *- +/, "");
            print;
          }
        ' \
      | tr -d '\r'
  )
  if [ "${#QUESTIONS[@]}" -eq 0 ]; then
    echo "[worker] #${NUM}: 質問が空。スキップ。" >&2
    gh issue comment "${NUM}" --body "⚠️ 「## 質問」の下に箇条書きの質問が見つかりませんでした。" || true
    continue
  fi

  # ===== 自動作成モード: ノートを用意（作成→収集→取り込み）=====
  if [ "${AUTO_MODE}" -eq 1 ]; then
    NB_ID="$(get_recorded_notebook "${NUM}")"
    if [ -z "${NB_ID}" ]; then
      CREATE_TITLE="${TITLE:-${TOPIC}}"
      echo "[worker] #${NUM}: ノート自動作成 '${CREATE_TITLE}'"
      NB_ID="$(nlm notebook create "${CREATE_TITLE}" "${PROFILE_ARGS[@]}" 2>&1 | extract_uuid)"
      if [ -z "${NB_ID}" ]; then
        gh issue comment "${NUM}" --body "⚠️ ノート自動作成に失敗しました。ログを確認してください。" || true
        continue
      fi
      # 先に記録（research が長引いても再入で再利用できるように）
      gh issue comment "${NUM}" --body "🆕 新規ノート作成: ${NB_ID}（次回以降はこのIDを使えます）

AUTO_NOTEBOOK_ID: ${NB_ID}" || true
      # 明示 sources を先に追加
      if [ "${#SOURCE_URLS[@]}" -gt 0 ]; then
        URLFLAGS=(); for u in "${SOURCE_URLS[@]}"; do URLFLAGS+=(--url "$u"); done
        echo "[worker] #${NUM}: source add ${#SOURCE_URLS[@]} 件"
        nlm source add "${NB_ID}" "${URLFLAGS[@]}" --wait --wait-timeout 240 "${PROFILE_ARGS[@]}" || true
      fi
      # Discover Sources（Deep）。完了待ちにタイムアウト。
      DISC_SEED="${SEED:-${TOPIC}}"
      echo "[worker] #${NUM}: research start (deep) seed='${DISC_SEED}'"
      timeout "${RESEARCH_TIMEOUT}" nlm research start "${DISC_SEED}" -n "${NB_ID}" -m deep --auto-import "${PROFILE_ARGS[@]}" \
        || echo "[worker] #${NUM}: research start タイムアウト/未完（次サイクルで取り込み確認）"
    fi

    # 取り込み確認 → 未完なら import 試行 → 数回待って再判定
    if ! notebook_queryable "${NB_ID}"; then
      # --cited-only で取り込む（全件だと ~50超でノートが query 不能になりやすいため）
      nlm research import "${NB_ID}" --cited-only --timeout 200 "${PROFILE_ARGS[@]}" >/dev/null 2>&1 || true
      ready=0
      for _t in 1 2 3 4 5; do
        if notebook_queryable "${NB_ID}"; then ready=1; break; fi
        sleep 20
      done
      if [ "${ready}" -eq 0 ]; then
        echo "[worker] #${NUM}: 収集/索引化が未完。次サイクルで再開。"
        gh issue comment "${NUM}" --body "⏳ ソース収集中（ノート: ${NB_ID}）。次サイクルで再開します。" || true
        continue   # ラベルは nlm-request のまま＝次回再入（NB_ID は記録済みで再利用）
      fi
    fi
    NOTEBOOK_ID="${NB_ID}"   # 以降は既存フローと同じ
    echo "[worker] #${NUM}: ノート準備完了 ${NOTEBOOK_ID}"
  fi

  # ===== 質問処理 =====
  OUT="docs/research/${TOPIC}.md"
  BEFORE_LINES=0
  [ -f "${OUT}" ] && BEFORE_LINES="$(wc -l < "${OUT}")"

  echo "[worker] #${NUM}: topic=${TOPIC} notebook=${NOTEBOOK_ID} questions=${#QUESTIONS[@]}"
  for q in "${QUESTIONS[@]}"; do
    bash scripts/nlm_research.sh "${TOPIC}" "${NOTEBOOK_ID}" "${q}" || {
      gh issue comment "${NUM}" --body "❌ クエリ実行に失敗しました（\`${q}\`）。認証切れなら docs/REMOTE_BROWSER_LOGIN.md で更新してください。" || true
      continue 2
    }
  done

  APPENDED="$(tail -n +"$((BEFORE_LINES+1))" "${OUT}")"

  git add "${OUT}"
  git commit -m "research: ${TOPIC} (#${NUM})" || true
  if ! push_retry; then
    gh issue comment "${NUM}" --body "⚠️ \`${OUT}\` に保存しましたが push に失敗しました。手動 push してください。" || true
    continue
  fi

  gh issue comment "${NUM}" --body "$(cat <<EOF
✅ \`${OUT}\` に保存しました（branch: \`${BRANCH}\`, status: draft, notebook: \`${NOTEBOOK_ID}\`）。
事実確認のうえ \`status: confirmed\` に上げてください。

<details><summary>今回追記した回答</summary>

${APPENDED}

</details>
EOF
)" || true

  gh issue edit "${NUM}" --add-label "${LABEL_DONE}" --remove-label "${LABEL_REQ}" || true
  gh issue close "${NUM}" || true
  echo "[worker] #${NUM}: done"
done

echo "[worker] 一巡完了"
