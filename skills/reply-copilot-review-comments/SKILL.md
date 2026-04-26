---
name: reply-copilot-review-comments
description: 'Use when reviewing GitHub pull requests, unresolved review comments, current branch PR detection, discussion_r links in commit messages, and posting "{commit URL} で対応" replies.'
license: MIT
---

# Reply Copilot Review Comments

## Deterministic Path
このスクリプトは以下を自動で行う。

- 現在ブランチに紐づく PR の自動取得
- unresolved かつ reviewer 一致の thread 抽出
- `discussion_r...` とコミットの突き合わせ
- 重複返信の回避
- reply 投稿
- reply 成功後の thread resolve

## 既定値

- owner / repo: 現在の GitHub repository から取得
- Pull Request 番号: 指定がなければ現在ブランチに紐づく PR から取得
- reviewer login: `copilot-pull-request-reviewer`
- 返信フォーマット: `{commit URL} で対応`
- resolve: reply 成功時に実行

ユーザーが既定値を崩していない限り、既定値で進めてよい。

## 推奨手順

### 1. まず deterministic script を使えるか確認する

まず [reply_and_resolve.sh](./scripts/reply_and_resolve.sh) の利用を検討する。

例:

```bash
./scripts/reply_and_resolve.sh --dry-run
./scripts/reply_and_resolve.sh --reviewer copilot-pull-request-reviewer
./scripts/reply_and_resolve.sh --pr 655
```

PR 番号未指定時は、現在ブランチに紐づく PR を `gh pr view --json number` で解決する。

### 2. 対象 PR の review thread を取得する

スクリプトを使わない場合は、GitHub GraphQL もしくは GitHub ツールで PR の review thread を取得し、以下の情報を集める。

- thread ID
- thread が unresolved か
- comment ID
- comment URL
- author login
- thread 内の既存 replies

最低限、以下の条件で対象コメントを抽出する。

- `isResolved == false`
- `author.login == reviewer login`

### 3. 重複返信を防ぐ

thread 内に、今回の返信フォーマットと一致する返信が既にあるか確認する。

以下のいずれかに当てはまる場合はスキップする。

- 自分がすでに同じ commit URL で返信している
- 自分以外でも、運用上十分と判断できる同趣旨の返信が既にある

スキップした場合は、どの comment をなぜスキップしたかを最後に報告する。

### 4. コメント URL から discussion ID を取り出す

各対象コメント URL から `discussion_r2930211027` のような discussion ID を取り出す。

例:

```text
https://github.com/tokyucorp/tokyuplus-web-backend/pull/655#discussion_r2930211027
```

この場合の探索キーは `discussion_r2930211027` である。

### 5. git log から対応コミットを特定する

`git log` の subject と body を対象に、discussion ID を含むコミットを検索する。

推奨方針:

- `git log --grep="discussion_r..." -n 1 --format=%H` を優先する
- 取れない場合のみ subject と body の全文検索に落とす
- 複数コミットがヒットした場合は、通常は最も新しいコミットを採用する

コメントごとに以下を決める。

- 対応コミットあり: reply + resolve 対象
- 対応コミットなし: 未対応として記録し、返信しない

### 6. 返信本文を組み立てる

コミットが見つかった場合は、以下の URL を生成する。

```text
https://github.com/{owner}/{repo}/commit/{commit_hash}
```

返信本文は既定で以下とする。

```text
{commit URL} で対応
```

余計な説明は足さない。ユーザーが明示的に求めた場合のみ補足を入れる。

### 7. PR コメントへ reply を投稿する

Pull Request comment reply 用の GitHub ツール、または deterministic script を使って、元 comment ID にぶら下がる返信を投稿する。

投稿対象は「元の Copilot コメント」であり、thread 全体への一般コメントではない。

### 8. reply 成功後に thread を resolve する

reply が成功した thread だけ resolve する。

失敗時の扱い:

- reply に失敗した場合: resolve しない
- reply は成功したが resolve に失敗した場合: 返信済みとして報告し、resolve 失敗を別途報告する

## 分岐ルール

### ケースA: 対象コメントが 0 件

- 返信も resolve も行わない
- 「unresolved かつ reviewer=COPILOT のコメントは存在しなかった」と報告する

### ケースB: コメントはあるが対応コミットがない

- 返信しない
- resolve しない
- 未対応一覧として comment URL を返す

### ケースC: すでに同じ返信がある

- 重複投稿しない
- 原則として resolve も新たに行わない
- 既存 reply を根拠にスキップしたと報告する

### ケースD: 複数コミットが同じ discussion ID を参照している

- 原則として最新コミットを採用する
- ただしユーザーが「最初に対応したコミットを出したい」と指定した場合はそれに従う

### ケースE: 現在ブランチに PR がない

- 自動取得できなかったことを明示する
- 必要なら PR 番号指定をユーザーに求める

## 品質基準

- unresolved の thread だけを対象にしている
- reviewer login の条件を満たすコメントだけを対象にしている
- PR 番号未指定時に現在ブランチの PR を正しく解決している
- 各返信が元コメントの discussion ID と対応するコミットに基づいている
- 同一内容の重複返信を避けている
- 指定された返信フォーマットを崩していない
- reply 成功後のみ resolve している

## 実行時の注意

- GraphQL クエリは review thread の `id`, `isResolved`, `comments.nodes` を取得できる形にする
- `gh` を使う場合、reply は REST API、resolve は GraphQL mutation の併用が扱いやすい
- コミット探索はローカルブランチの履歴を前提とするため、必要なら最新状態を確認する
- ユーザーが「Copilot 以外も対象」と言った場合は `reviewer login` を可変にする

## 完了時の返し方

最後に以下を簡潔に伝える。

- 自動解決した PR 番号
- 返信した件数
- resolve した件数
- comment ID と commit hash の対応
- スキップした件数と理由
- resolve 失敗があればその件数

## 例

### 例1

```text
/reply-copilot-review-comments 現在ブランチの PR に対して unresolved な Copilot コメントへ返信して resolve して
```

### 例2

```text
/reply-copilot-review-comments reviewer=copilot-pull-request-reviewer dry-run=true
```

### 例3

```text
/reply-copilot-review-comments pr=655 reviewer=copilot-pull-request-reviewer
```