# docs/research — 確定テキストの器

NotebookLM の出力を `<topic>.md`（[`TEMPLATE.md`](TEMPLATE.md) 準拠）として残す場所。
チャット依頼でも手動でも、出力先はここに統一する（消費側は経路を意識しない）。

## 規約

- 1 トピック = 1 ファイル `<topic-slug>.md`（半角小文字・ハイフン区切り。例: `anomalocaris.md`）。
- 質問を追記するたびに `## Q&A ログ` に Q ブロックを足し、`updated_at` を更新する。
  （`scripts/nlm_research.sh` が自動でやる）
- frontmatter:
  - `status: draft` … NotebookLM が返したまま（未確認）。
  - `status: confirmed` … **人手で事実確認済み**。本番利用はこれを基準にする。
- 本番セッションでは NotebookLM を再度叩かず、ここの確定テキストを**読むだけ**にする（再現性）。

## 生成方法

```bash
# 単発（手動）
bash scripts/nlm_research.sh <topic-slug> <notebook_id> "質問文"

# Issue 経由（チャット層 or 手起票 → ワーカーが拾う）
# .github/ISSUE_TEMPLATE/nlm-request.md を埋めて nlm-request ラベルで起票
```

## Phase 2 予告

ここの Markdown は将来 Obsidian Vault に同期する（`docs/ARCHITECTURE.md §Phase 2`）。
frontmatter はそのまま Obsidian のプロパティとして使える形にしてある。
