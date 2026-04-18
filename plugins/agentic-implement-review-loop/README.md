# impl-review-loop plugin

GitHub Copilot CLI で、メイン会話をオーケストレーターにしながら、実装フェーズとレビューフェーズを custom agent で交互に回すためのローカルプラグインです。

## 含まれるもの

- `agents/agentic-loop-implementer.agent.md`: 実装担当 custom agent
- `agents/agentic-loop-reviewer.agent.md`: レビュー担当 custom agent
- `hooks.json`: `subagentStop` hook で次フェーズを自動注入
- `skills/agentic-impl-review-loop/SKILL.md`: ループ開始とオーケストレーション用の Skill

## 既定モデル

- 実装 agent: `Claude Sonnet 4.6`
- review agent: `GPT-5.4`

モデルを切り替えたい場合は plugin 内の `.agent.md` の `model:` を編集してください。

## インストール

```shell
# add marketplace if not already added
copilot plugin marketplace add Nao-Mk2/coding-agent-attachments

# install plugin
copilot plugin install agentic-implement-review-loop@coding-agent-attachments
```

## 使い方

以下のように Skill を呼び出してください。

```text
Use the /agentic-impl-review-loop skill to implement <やりたいこと>. max-iterations=3
```

- `max-iterations` は省略すると `5` になります。必要に応じて指定してください。
- 状態ファイルとして `.copilot/impl-review-loop-state.md` を作成し、タスクとレビュー結果をそこに保存しながらループを回します。
- 完走後も `.copilot/impl-review-loop-state.md` は削除されず、各イテレーションの履歴と最終 review 結果が保存されます


## 状態ファイル

デフォルトの状態ファイルは以下です。

```text
.copilot/impl-review-loop-state.md
```

状態ファイルには以下も保持されます。

- `<run-history>`: 各イテレーションの impl / review 出力
- `<final-review>`: 終了時の最終 review 結果と終了理由
- `completed_at`: 完走時刻

## 停止条件

以下のいずれかで自動停止します。

1. `max-iterations` に達した
2. レビュー結果が `Don't` のみ、または指摘 0 件だった

停止後は `active: false` / `phase: done` に更新され、状態ファイルがそのまま完走ログになります。

## キャンセル

```shell
rm -f .copilot/impl-review-loop-state.md
```

## アンインストール

```shell
# uninstall plugin
copilot plugin uninstall agentic-implement-review-loop@coding-agent-attachments

# remove marketplace if not needed
copilot plugin marketplace remove coding-agent-attachments
```