---
name: NotebookLM リサーチ依頼
about: チャット層 or 手動から NotebookLM クエリを投げる。ワーカーが拾って docs/research/ に保存する。
title: "[nlm] <topic-slug>"
labels: nlm-request
---

<!-- ワーカー scripts/nlm_request_worker.sh がこの本文を機械的に読みます。
     行頭キー（notebook_id: / topic: など）と「## 質問」の箇条書きは消さず、値だけ埋めてください。 -->

notebook_id: <既存のnotebook_id / または NEW（自動でノート作成＆ソース収集）>
topic: <topic-slug 半角小文字ハイフン区切り 例: anomalocaris>

<!-- 以下は任意。notebook_id: NEW（自動作成）のときに使う。使う行だけ # を外して埋める -->
<!-- title: 作成するノートの名前（省略時は topic を使用） -->
<!-- seed: ソース探索用クエリ（省略時は topic を使用） -->
<!-- discover: true   ← notebook_id を空にして自動収集したい場合に true -->
<!-- 任意の追加ソースを足したい時は、行頭に sources: を書き、次行から URL/YouTube を改行区切りで:
sources:
  https://example.com/article
  https://youtu.be/xxxxxxxx
-->

## 質問
- ここに質問を1行ずつ書く
- 複数行OK（各行が個別クエリとして実行される）
