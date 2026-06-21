#!/bin/bash
# Claude Code on the web のセッション開始時に NotebookLM-LLM の依存を整え、認証状態を知らせる。
# 設計: docs/ARCHITECTURE.md / docs/nlm_auth_design.md
#   - クラウドでワーカー(nlm_request_worker.sh)を回すため、nlm / playwright / requests を用意する。
#   - 認証(Cookie)はクラウド profile に入っている必要がある。無ければスマホ Google ログインを促す。
# 冪等・非対話。失敗しても極力セッションは止めない（WARN を出して続行）。
set -uo pipefail

# クラウド(Claude Code on the web)でのみ実行。ローカルは各自の環境を尊重する。
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

echo "[session-start] NotebookLM-LLM 依存をセットアップします…"

# 1. uv（nlm のインストーラ）。既にあればスキップ。
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  echo "[session-start] uv を導入…"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || echo "[session-start] WARN: uv 導入に失敗"
  export PATH="$HOME/.local/bin:$PATH"
fi
# 後続のツール(nlm)にも PATH を通す
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

# 2. nlm (notebooklm-mcp-cli)。冪等。
if ! command -v nlm >/dev/null 2>&1; then
  echo "[session-start] notebooklm-mcp-cli==0.6.8 を導入…"
  uv tool install "notebooklm-mcp-cli==0.6.8" >/dev/null 2>&1 \
    || echo "[session-start] WARN: nlm 導入に失敗（後で 'uv tool install notebooklm-mcp-cli==0.6.8'）"
fi

# 3. Python 依存（Browserbase ログイン採取用）。connect_over_cdp なので playwright のブラウザDLは不要。
if [ -f requirements.txt ]; then
  echo "[session-start] python 依存(requests/playwright)を導入…"
  python3 -m pip install --quiet -r requirements.txt 2>/dev/null \
    || echo "[session-start] WARN: pip 導入に失敗（後で 'python3 -m pip install -r requirements.txt'）"
fi

# 4. NotebookLM 認証状態のチェック（セッションは止めない）。
echo "[session-start] NotebookLM 認証チェック:"
if bash scripts/nlm_auth_status.sh; then
  echo "[session-start] ✅ NotebookLM 認証は有効。リサーチ依頼を処理できます。"
else
  echo "[session-start] 🔑 NotebookLM 未認証です。リサーチ前にスマホで Google ログインしてください:"
  echo "[session-start]    1) bash scripts/remote_login_helper.sh start"
  echo "[session-start]    2) 表示されるライブビュー URL をスマホで開いて Google ログイン"
  echo "[session-start]    （Browserbase キーは環境シークレットに設定: docs/REMOTE_BROWSER_LOGIN.md）"
fi

echo "[session-start] セットアップ完了。"
