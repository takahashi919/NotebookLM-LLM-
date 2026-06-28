# 🛠 セットアップ手順（会社PC / 自宅PC / スマホ）

このVaultを **GitHub経由で複数端末から同期**して使うための手順です。
方針は **「まず全部無料（GitHub + Obsidian Git）で揃える」**。スマホも無料Gitで運用します。

---

## 0. 全体像

```
            GitHub リポジトリ (takahashi919/notebooklm-llm-)
                          ▲   ▼   （Obsidian Git が自動で push / pull）
        ┌─────────────────┼─────────────────┐
     会社PC             自宅PC             スマホ
   (Obsidian)         (Obsidian)        (Obsidian Mobile)
```

- 同期するのは **`vault/` フォルダの中身**（Markdown）。
- 端末ごとに違う設定（開いていたタブ等）は `.gitignore` で除外済みなので競合しません。

---

## 1. 各PC（会社PC・自宅PC 共通）

### 1-1. 用意するもの
- [Obsidian](https://obsidian.md/)（無料）
- [Git](https://git-scm.com/)（Obsidian Git プラグインが内部で使用）
- このリポジトリへのアクセス権（GitHubアカウント / PAT もしくは SSH 鍵）

### 1-2. リポジトリを clone
```bash
git clone https://github.com/takahashi919/notebooklm-llm-.git
```
> すでに clone 済みのフォルダがあればそれでOK。

### 1-3. Obsidian で Vault を開く
- Obsidian を起動 → **「フォルダを Vault として開く」**
- clone したフォルダの中の **`vault/`** を選ぶ（リポジトリのルートではない点に注意）

### 1-4. コミュニティプラグインを入れる
設定 → コミュニティプラグイン → 制限モードを**オフ** → 以下を検索してインストール＆有効化：

| プラグイン | 役割 |
|---|---|
| **Obsidian Git**       | GitHub と自動同期（必須） |
| **Calendar**           | サイドのカレンダー。日付クリックでデイリーノート |
| **Periodic Notes**     | 日次/週次ノートの自動生成 |
| **Tasks**              | `- [ ]` を期限・繰り返し付きで管理＆集計 |
| **Full Calendar**      | 予定をカレンダー表示・**祝日ICS取り込み**（→ §3） |

> デイリーノート / テンプレート（コア機能）は設定済みなので、上記を入れればすぐ使えます。

### 1-5. Obsidian Git の設定（おすすめ）
設定 → Obsidian Git：
- **Vault backup interval (minutes)**: `10`（10分ごとに自動 commit/push）
- **Pull updates on startup**: ✅ オン（起動時に最新を取得）
- **Commit message**: 既定のままでOK

これで「保存 → 自動でGitHubに上がる」「起動 → 自動で最新が落ちる」状態になります。

---

## 2. スマホ（無料Git運用）

> iPhone / Android どちらも **Obsidian Mobile + Obsidian Git** で無料同期できます。
> ※ メモが増えると同期が少し遅くなることがあります。重くなったら §4 を参照。

1. **Obsidian Mobile** アプリをインストール
2. リポジトリを clone した Vault を用意する：
   - 一番カンタンなのは、PCで一度 push したあと、スマホの Obsidian で
     **「Clone an existing remote vault」** ができる **Obsidian Git** の機能を使う方法。
   - 設定 → Obsidian Git → **Authentication**：
     - **Username**: GitHubユーザー名
     - **Password/Token**: GitHubの **Personal Access Token (PAT)**（パスワードではなくトークン）
       - GitHub → Settings → Developer settings → **Personal access tokens** で発行
       - 権限は対象リポジトリの **Contents: Read and write** があればOK
3. clone 後、Vault として `vault/` を開く
4. 同期は画面の **コマンドパレット → "Obsidian Git: Commit-and-sync"** で実行
   （自動バックアップもPCと同様に設定可能）

> 💡 スマホは「開いたら sync、閉じる前に sync」を手癖にすると安全です。

---

## 3. 日本の祝日カレンダー連携（Full Calendar）

予定や祝日をカレンダー表示したい場合：

1. **Full Calendar** プラグインの設定を開く
2. **Calendars → Add Calendar → Remote (.ics)** を選ぶ
3. ICS の URL を登録（例）：
   - Google の日本の祝日カレンダー（公開ICS URL）
     `https://calendar.google.com/calendar/ical/ja.japanese%23holiday%40group.v.calendar.google.com/public/basic.ics`
   - 自分のGoogleカレンダーの「公開URL（ICS形式）」を入れれば、自分の予定も表示できます
4. これで Obsidian 内のカレンダーに祝日・予定が出ます。日付からデイリーノートに飛んでメモが取れます。

> Google カレンダー自体の双方向編集はできません（読み取り表示）。
> 予定の「編集」までしたい場合は Full Calendar のローカルカレンダー機能を併用してください。

---

## 4. 困ったとき

| 症状 | 対処 |
|---|---|
| 別端末の変更が反映されない | 起動時 Pull がオンか確認。手動で "Obsidian Git: Pull" |
| 競合（conflict）が出た | 慌てず：片方で **Commit-and-sync** → もう片方で **Pull**。順番に同期する癖をつける |
| スマホで同期が重い | 添付（画像）を増やしすぎない。どうしても辛ければ携帯だけ公式 [Obsidian Sync](https://obsidian.md/sync)（有料）に切替も可 |
| プラグインが動かない | 制限モードがオフか、プラグインを有効化したか確認 |

---

## 補足：なぜ GitHub に置くのか

- Markdown の塊なので **そのままGitで管理でき、履歴も全部残る**（誤削除も復元可能）
- **無料**で会社PC・自宅PCはほぼ完璧に同期できる
- 将来このリポジトリの NotebookLM リサーチ結果（`docs/research/`）を
  この Vault に取り込む連携（Phase 2）にも発展させられる
