#!/usr/bin/env python3
"""Browserbase リモートブラウザでスマホから Google ログイン → Cookie を採取する。

設計: docs/nlm_auth_design.md §3 / 手順: docs/REMOTE_BROWSER_LOGIN.md 方式A
Free 枠は keepAlive 非対応のことがあるため、start→capture を分けず
**単一プロセスでセッションを保持**する:

  1. セッション作成 → ライブビュー URL を出力（スマホで開く）
  2. CDP 接続を張りっぱなしにしてセッションを生かす
  3. NotebookLM を開いた状態でユーザーの Google ログインを待つ
  4. ログイン検知（__Secure-1PSID 等）→ Cookie を 2 形式で書き出す
       <out>.header.txt   … "name=value; ..." 形式（nlm の手動貼付と同じ）
       <out>.netscape.txt … Netscape cookies.txt 形式
  5. どちらを使うかは呼び出し側(remote_login_helper.sh)が順に試す

依存: requests, playwright（connect_over_cdp なのでローカル Chromium 不要）
  uv pip install requests playwright   /   pip install requests playwright

env: BROWSERBASE_API_KEY, BROWSERBASE_PROJECT_ID

使い方:
  python scripts/browserbase_login.py <out_basepath> [--timeout 600] [--target https://notebooklm.google.com]
終了コード: 0=採取成功 / 1=失敗・タイムアウト / 2=設定不備
"""
from __future__ import annotations

import argparse
import os
import sys
import time

API_BASE = "https://api.browserbase.com/v1"
# Google ログイン成立の強い指標（いずれか存在すればログイン済みとみなす）
LOGIN_MARKERS = ("__Secure-1PSID", "__Secure-3PSID", "SID")


def _err(msg: str) -> None:
    print(f"[browserbase] {msg}", file=sys.stderr)


def create_session(api_key: str, project_id: str) -> dict:
    import requests

    resp = requests.post(
        f"{API_BASE}/sessions",
        headers={"X-BB-API-Key": api_key, "Content-Type": "application/json"},
        json={"projectId": project_id},
        timeout=30,
    )
    if resp.status_code >= 300:
        _err(f"セッション作成失敗 HTTP {resp.status_code}: {resp.text[:300]}")
        sys.exit(1)
    return resp.json()


def live_view_url(api_key: str, session_id: str) -> str:
    import requests

    resp = requests.get(
        f"{API_BASE}/sessions/{session_id}/debug",
        headers={"X-BB-API-Key": api_key},
        timeout=30,
    )
    if resp.status_code >= 300:
        _err(f"ライブビュー URL 取得失敗 HTTP {resp.status_code}: {resp.text[:200]}")
        return ""
    d = resp.json()
    return d.get("debuggerFullscreenUrl") or d.get("debuggerUrl") or ""


def is_google(domain: str) -> bool:
    d = domain.lstrip(".").lower()
    return d == "google.com" or d.endswith(".google.com")


def logged_in(cookies: list[dict]) -> bool:
    names = {c.get("name") for c in cookies if is_google(c.get("domain", ""))}
    return any(m in names for m in LOGIN_MARKERS)


def write_header_format(path: str, cookies: list[dict]) -> None:
    pairs = [
        f"{c['name']}={c['value']}"
        for c in cookies
        if is_google(c.get("domain", "")) and c.get("name") and c.get("value") is not None
    ]
    with open(path, "w", encoding="utf-8") as f:
        f.write("; ".join(pairs) + "\n")


def write_netscape_format(path: str, cookies: list[dict]) -> None:
    lines = ["# Netscape HTTP Cookie File"]
    for c in cookies:
        domain = c.get("domain", "")
        if not is_google(domain) or not c.get("name"):
            continue
        include_sub = "TRUE" if domain.startswith(".") else "FALSE"
        path_v = c.get("path", "/") or "/"
        secure = "TRUE" if c.get("secure") else "FALSE"
        expires = int(c.get("expires") or 0)
        if expires <= 0:
            expires = int(time.time()) + 60 * 60 * 24 * 30  # session cookie → 30日付与
        lines.append(
            "\t".join([domain, include_sub, path_v, secure, str(expires), c["name"], str(c.get("value", ""))])
        )
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out_base", help="出力ベースパス（<base>.header.txt / <base>.netscape.txt を書く）")
    ap.add_argument("--timeout", type=int, default=600, help="ログイン待ち上限(秒)。Free枠のセッション上限(15分=900s)未満に")
    ap.add_argument("--target", default="https://notebooklm.google.com", help="開くURL")
    args = ap.parse_args()

    api_key = os.environ.get("BROWSERBASE_API_KEY", "").strip()
    project_id = os.environ.get("BROWSERBASE_PROJECT_ID", "").strip()
    if not api_key or not project_id:
        _err("BROWSERBASE_API_KEY / BROWSERBASE_PROJECT_ID が未設定（.env を埋めて）。")
        return 2

    try:
        from playwright.sync_api import sync_playwright
    except Exception:
        _err("playwright が無い。 `pip install playwright requests`（connect_over_cdp なので browser install は不要）")
        return 2

    sess = create_session(api_key, project_id)
    sid = sess.get("id")
    connect_url = sess.get("connectUrl")
    if not connect_url:
        _err(f"connectUrl が応答に無い: {list(sess.keys())}")
        return 1

    view = live_view_url(api_key, sid)
    print("\n" + "=" * 64)
    print("📱 スマホでこの URL を開いて Google にログインしてください:")
    print(f"   {view or '(ライブビューURL取得失敗。Browserbaseダッシュボードのライブビューでも可)'}")
    print(f"   セッション: {sid}")
    print(f"   ログイン完了を最大 {args.timeout} 秒待ちます…")
    print("=" * 64 + "\n", flush=True)

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(connect_url)
        try:
            ctx = browser.contexts[0] if browser.contexts else browser.new_context()
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            try:
                page.goto(args.target, wait_until="domcontentloaded", timeout=30000)
            except Exception as e:
                _err(f"ページ遷移で警告（続行）: {e}")

            deadline = time.time() + args.timeout
            got = False
            while time.time() < deadline:
                cookies = ctx.cookies()
                if logged_in(cookies):
                    got = True
                    break
                remaining = int(deadline - time.time())
                print(f"[browserbase] ログイン待ち… 残り {remaining}s", file=sys.stderr, flush=True)
                time.sleep(5)

            cookies = ctx.cookies()
            if not got:
                _err("タイムアウト：Google ログインを検知できませんでした。")
                return 1

            write_header_format(args.out_base + ".header.txt", cookies)
            write_netscape_format(args.out_base + ".netscape.txt", cookies)
            n = sum(1 for c in cookies if is_google(c.get("domain", "")))
            print(f"[browserbase] ✅ ログイン検知。google Cookie {n} 件を書き出しました。", file=sys.stderr)
            return 0
        finally:
            try:
                browser.close()  # 接続を閉じる＝Free枠セッションを終了
            except Exception:
                pass


if __name__ == "__main__":
    sys.exit(main())
