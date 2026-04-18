---
name: agentic-impl-review-loop
description: 実装フェーズとレビューフェーズを custom agent で交互に回したいときに使う。ループを初期化し、メイン会話をオーケストレーターとして動かしながら、レビュー指摘が対応不要のみになるか最大イテレーション数に達するまで継続する。
user-invocable: true
disable-model-invocation: false
---

# Copilot Impl Review Loop

この Skill は実装とレビューの反復ワークフローを実施する。

## 目的

1. 最初の turn でループ状態ファイルを初期化する
2. メイン会話をオーケストレーターとして動かし、実装用 custom agent とレビュー用 custom agent を task tool で順番に起動する
3. sub-agent 完了時は plugin の `subagentStop` hook が次フェーズを自動で差し込む

## 使用する custom agent

- `agentic-loop-implementer`: 実装担当。
- `agentic-loop-reviewer`: レビュー担当。

## 初期化ルール

- scripts/start-loop.sh を使って状態ファイルを初期化する
- **1 イテレーション = impl フェーズ + review フェーズ の 1 サイクル**
 - `max_iterations` はこのサイクル数の上限を表す
- 状態ファイルは `.copilot/impl-review-loop-state.md` に作成、更新する
- `max-iterations=N` または `--max-iterations N` がプロンプトに含まれていればその値を使う
- 上記指定がなければ最大イテレーション数は `5`

## 状態ファイルのフォーマット

状態ファイルのフォーマットは以下。
```markdown
---
active: true
phase: impl
iteration: 1
max_iterations: 5
started_at: 2026-04-15T00:00:00Z
completed_at:
---

<task>
ここにタスク
</task>

<feedback>
</feedback>

<skipped-items>
</skipped-items>

<run-history>
</run-history>

<final-review>
</final-review>
```

- `<run-history>` には各イテレーションの impl / review の結果を追記し、完走後も参照できるようにする
- `<final-review>` には最後に実行された review の結果と終了理由を残す
- ループ完走時は state file を削除せず、`active: false` / `phase: done` / `completed_at` を設定して保存する

## 最初の turn の進め方

- 初期化後、メイン会話自身は実装しない
- `task` tool で `agentic-loop-implementer` custom agent を起動し、実装フェーズを委譲する
- 中間フェーズでは sub-agent の結果を自分で要約しない
- sub-agent 完了後は hook が次フェーズを自動で差し込むので、その指示に従って次の custom agent を起動する
- ループ終了条件を満たして hook が停止したときだけ、最後に短い完了報告を返して終了する
- 完走後の `.copilot/impl-review-loop-state.md` を見れば、各イテレーションの指摘、実装側の対応有無、最終 review 結果が追跡できる状態を維持する

## オーケストレーションのルール

- 実装フェーズでは必ず `agentic-loop-implementer` を使う
- レビューフェーズでは必ず `agentic-loop-reviewer` を使う
- 実装とレビューを同一 sub-agent に兼務させない
- レビュー結果に Must/Should が残る限り、hook が impl -> review -> impl を継続する
- review フェーズは最大イテレーション数に達している場合でも必ず実行する
- review 結果が `<no-action-needed/>` を含む場合、またはイテレーション N の review が完了した場合にループを終了する
  - 後者の場合、Must/Should が残っていても追加の impl は行わない


## 実装 sub-agent に期待する出力

- レビューフィードバックがある場合でも、すべてを対応する必要はない
- 重要でないと判断した項目は対応不要にしてよい
- レビューフィードバックがある場合は、各指摘について対応有無を末尾に必ず次の形式で含める

```xml
<review-resolution>
- 対応: 項目名 | どう対応したか
- 対応不要: 項目名 | 対応不要と判断した理由
</review-resolution>
```

- 対応不要とした項目がある場合は、応答の最後に必ず次の形式を含める

```xml
<skipped>
- 項目名: 対応不要と判断した理由
</skipped>
```

- 対応不要がなければ `<skipped>` は出力しない

## レビュー sub-agent に期待する出力

plugin の `subagentStop` hook は、レビュー結果に以下を期待している。

- 指摘 0 件、またはすべて `Don't` のみなら応答末尾に `<no-action-needed/>` を含める
- Must/Should がある場合は、以下の見出しから始める
- review の生出力は hook により `<run-history>` と `<final-review>` に保存される前提なので、最終判断が追えるよう簡潔に省略しすぎない

```markdown
## レビューフィードバック
```

- 以降は Must / Should ごとに問題、影響、対応案を書く
