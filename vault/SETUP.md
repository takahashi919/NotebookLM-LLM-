# 🛠 セットアップ手順書（専用リポジトリ版）

このフォルダ（Vault）を **専用の GitHub リポジトリ**に置き、
**会社PC・自宅PC・スマホ**から同期して使うための手順です。全部無料でできます。

> このフォルダがそのまま Vault（＝リポジトリのルート）です。
> だから Obsidian Git は**特別な設定なし**で、PCもスマホもそのまま動きます。

---

## 全体像

```
        専用 GitHub リポジトリ（例: あなたの my-obsidian）
                      ▲   ▼   （Obsidian Git が自動で push / pull）
   ┌──────────────────┼──────────────────┐
 会社PC             自宅PC              スマホ
(Obsidian)        (Obsidian)        (Obsidian Mobile)
```

---

## STEP 1. 専用リポジトリを作る（PCでもスマホでも / 1回だけ・数十秒）

1. GitHub を開く → 右上「＋」→ **New repository**
2. **Repository name**: `my-obsidian`（好きな名前でOK）
3. **Private** を選ぶ（メモは非公開推奨）
4. 「Add a README」などは**チェックしない**（空のままが楽）
5. **Create repository** → 表示される URL を控える
   （例: `https://github.com/あなたのID/my-obsidian.git`）

---

## STEP 2. このVaultを新リポジトリへ最初に上げる（最初のPCで1回だけ）

配布された Vault フォルダ（このフォルダ）を、PCの好きな場所に置いてから：

**Windows（PowerShell）/ Mac（ターミナル）共通:**
```bash
cd <Vaultフォルダのある場所>      # 例: cd ~/Documents/my-obsidian
git init
git add -A
git commit -m "Initial Obsidian vault"
git branch -M main
git remote add origin https://github.com/あなたのID/my-obsidian.git
git push -u origin main
```
> これで GitHub にVaultがアップされればSTEP2は完了。以降は Obsidian が自動で同期します。

---

## STEP 3. Obsidian で Vault として開く（各PC共通）

1. [Obsidian](https://obsidian.md/) をインストール（無料）
2. 起動 → **「Open folder as vault（フォルダを Vault として開く）」**
3. **このフォルダ**を選ぶ（中に `00_Inbox` や `90_Templates` がある階層）
4. 「Trust author and enable plugins?」と出たら **Trust** を押す

> 2台目以降のPCは、STEP2の代わりに
> `git clone https://github.com/あなたのID/my-obsidian.git` で落として、
> そのフォルダを Obsidian で開くだけ。

---

## STEP 4. プラグインを入れる（各PC共通・1回）

設定（左下の⚙️）→ **コミュニティプラグイン** → 「制限モード」を**オフ** → 検索して入れる：

| プラグイン | 役割 |
|---|---|
| **Obsidian Git**   | GitHub と自動同期（必須） |
| **Calendar**       | サイドのカレンダー。日付クリックでデイリーノート |
| **Periodic Notes** | 日次/週次ノートの自動生成 |
| **Tasks**          | `- [ ]` を期限・繰り返し付きで管理＆集計 |
| **Full Calendar**  | 予定をカレンダー表示・**祝日ICS取り込み**（→ STEP6） |

> デイリーノート / テンプレート（コア機能）は設定済みなので、上記を入れればすぐ使えます。

---

## STEP 5. Obsidian Git を設定（おすすめ）

設定 → **Obsidian Git**：
- **Vault backup interval (minutes)**: `10`（10分ごとに自動 commit/push）
- **Pull updates on startup**: ✅ オン（起動時に最新取得）
- **Pull changes before push**: ✅ オン（競合しにくくなる）

認証（初回 push/pull 時に聞かれたら）：
- **Username**: GitHubユーザー名
- **Password**: GitHubの **Personal Access Token (PAT)**（パスワードではない）
  - GitHub → Settings → Developer settings → **Personal access tokens (Fine-grained)**
  - 対象リポジトリに **Contents: Read and write** 権限を付ける

---

## STEP 6. スマホ（Obsidian Mobile・無料同期）

1. **Obsidian** アプリをインストール
2. 「Create new vault」ではなく、**Obsidian Git の "Clone existing remote vault"** を使う：
   - まず空のVaultを1つ作って開く → Obsidian Git を入れる →
     コマンドパレット（画面長押し or 設定）→ **"Obsidian Git: Clone an existing remote repository"**
   - リポジトリURL（`https://github.com/あなたのID/my-obsidian.git`）と PAT を入力
3. 以後は **"Obsidian Git: Commit-and-sync"** で同期（自動バックアップ設定も可）

> 💡 スマホは「開いたら sync、閉じる前に sync」を手癖にすると安全。
> 専用リポ（Vault=ルート）なのでモバイルでも素直に動きます。

---

## STEP 7. 日本の祝日カレンダー連携（Full Calendar）

1. **Full Calendar** の設定 → **Add Calendar → Remote (.ics)**
2. ICS の URL を登録（例：日本の祝日）：
   ```
   https://calendar.google.com/calendar/ical/ja.japanese%23holiday%40group.v.calendar.google.com/public/basic.ics
   ```
3. 自分のGoogleカレンダーの「公開ICS URL」を足せば、自分の予定も表示できます
4. Obsidian内のカレンダーに祝日・予定が出て、日付からデイリーノートに飛べます

> Googleカレンダーの双方向編集はできません（読み取り表示）。
> 予定を編集までしたい場合は Full Calendar のローカルカレンダー機能を併用。

---

## 困ったとき

| 症状 | 対処 |
|---|---|
| 別端末の変更が出ない | 起動時 Pull がオンか確認 → 手動で "Obsidian Git: Pull" |
| 競合（conflict） | 片方で **Commit-and-sync** → もう片方で **Pull**。順番に同期する癖を |
| スマホで重い | 添付画像を増やしすぎない。どうしても辛ければ携帯だけ [Obsidian Sync](https://obsidian.md/sync)（有料）に切替も可 |
| プラグインが動かない | 制限モードがオフか、有効化したか確認 |
| push で認証エラー | パスワードではなく **PAT** を使う（STEP5） |
