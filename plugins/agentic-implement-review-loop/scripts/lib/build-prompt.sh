#!/bin/bash

build_impl_agent_prompt() {
  local iteration="$1"
  local max_iterations="$2"
  local task="$3"
  local feedback="$4"
  local skipped_items="$5"

  cat <<PROMPT
あなたは impl-review-loop の実装担当 custom agent です。

## 実装フェーズ
${iteration}/${max_iterations}

## タスク
${task}
PROMPT

  if [[ -n "${feedback// /}" ]]; then
    cat <<PROMPT

## 前回のレビューフィードバック
${feedback}

上記フィードバックを踏まえて実装を修正・改善してください。
すべての指摘に対応する必要はありません。重要でないと判断した項目は対応不要として構いません。

前回レビューの各指摘に対する対応有無を履歴化するため、応答末尾に必ず次の形式を含めてください。

<review-resolution>
- 対応: 項目名 | どう対応したか
- 対応不要: 項目名 | 対応不要と判断した理由
</review-resolution>

対応不要とした項目がある場合は、応答の最後に必ず次の形式を含めてください。

<skipped>
- 項目名: 対応不要と判断した理由
</skipped>
PROMPT
  fi

  if [[ -n "${skipped_items// /}" ]]; then
    cat <<PROMPT

## 既に対応不要と判断済みの項目
以下は過去イテレーションで対応不要とした項目です。再対応や再説明は不要です。
${skipped_items}
PROMPT
  fi

  cat <<PROMPT

## 実施ルール
- 必要なコード変更を実装する
- 必要ならテスト、lint、build などの確認を行う
- レビューはしない
- 前回レビューがある場合は、各指摘について「対応」または「対応不要」を 'review-resolution' に記録する
- 応答末尾に変更内容と検証結果を簡潔にまとめる
PROMPT
}

build_impl_prompt() {
  local iteration="$1"
  local max_iterations="$2"
  local task="$3"
  local feedback="$4"
  local skipped_items="$5"
  local agent_prompt

  agent_prompt="$(build_impl_agent_prompt "$iteration" "$max_iterations" "$task" "$feedback" "$skipped_items")"

  cat <<PROMPT
impl-review-loop: 実装フェーズ (${iteration}/${max_iterations}) です。

'agentic-loop-implementer' custom agent を task tool で起動してください。
sub-agent に渡す指示は以下をそのまま使ってください。

<subagent-prompt>
${agent_prompt}
</subagent-prompt>

sub-agent 完了後は hook が次フェーズを差し込むため、この turn では結果を要約したり別の review を始めたりせず、そのまま次の指示を待ってください。
PROMPT
}

build_review_agent_prompt() {
  local iteration="$1"
  local max_iterations="$2"
  local task="$3"
  local skipped_items="$4"

  cat <<PROMPT
あなたは impl-review-loop のレビュー担当 custom agent です。

## レビューフェーズ
${iteration}/${max_iterations}

## タスク
${task}
PROMPT

  if [[ -n "${skipped_items// /}" ]]; then
    cat <<PROMPT

## 対応不要と決定済みの項目
以下の項目は実装フェーズで対応不要と判断済みです。これらは再指摘しないでください。
${skipped_items}
PROMPT
  fi

  cat <<PROMPT

'git diff' または 'git diff HEAD~1' で今回の変更を確認し、以下の観点でコードレビューしてください。

## レビュー観点
1. バグになりそうな点
2. 失敗時の後片付け漏れ
3. データ不整合や再実行時の破綻
4. 並行処理まわりの不具合
5. 運用上つらい点
6. テスト不足

## 判定分類
- Must: 必ず対応すべき問題
- Should: 余裕があれば対応すべき問題
- Don't: 対応不要

## 出力ルール
- 指摘が 0 件、または 'Don't' のみなら応答末尾に必ず '<no-action-needed/>' を出力する
- Must / Should がある場合は必ず次の形式で出力する

## レビューフィードバック

### [Must/Should] タイトル
- 問題: 何が問題か
- 影響: どう困るか
- 対応案: どう直すか

- レビューだけを行い、ファイル変更はしない
PROMPT
}

build_review_prompt() {
  local iteration="$1"
  local max_iterations="$2"
  local task="$3"
  local skipped_items="$4"
  local agent_prompt

  agent_prompt="$(build_review_agent_prompt "$iteration" "$max_iterations" "$task" "$skipped_items")"

  cat <<PROMPT
impl-review-loop: レビューフェーズ (${iteration}/${max_iterations}) です。

'agentic-loop-reviewer' custom agent を task tool で起動してください。
sub-agent に渡す指示は以下をそのまま使ってください。

<subagent-prompt>
${agent_prompt}
</subagent-prompt>

sub-agent 完了後は hook が次フェーズを差し込むため、この turn では結果を要約したり自分で修正を始めたりせず、そのまま次の指示を待ってください。
PROMPT
}