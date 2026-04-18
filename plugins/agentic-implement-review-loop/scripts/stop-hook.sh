#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/parse-state.sh"
source "$SCRIPT_DIR/lib/build-prompt.sh"

STATE_FILE=""

resolve_state_file() {
  local cwd="$1"

  if [[ -f "$cwd/.copilot/impl-review-loop-state.md" ]]; then
    printf '%s\n' "$cwd/.copilot/impl-review-loop-state.md"
    return 0
  fi

  if [[ -f "$cwd/.claude/impl-review-loop-state.md" ]]; then
    printf '%s\n' "$cwd/.claude/impl-review-loop-state.md"
    return 0
  fi

  return 1
}

extract_last_output_from_transcript() {
  local transcript_path="$1"

  if [[ -z "$transcript_path" ]] || [[ ! -f "$transcript_path" ]]; then
    return 0
  fi

  grep '"role":"assistant"' "$transcript_path" 2>/dev/null \
    | tail -n 100 \
    | jq -rs '[.[].message.content[]? | select(.type == "text") | .text] | add // ""' 2>/dev/null \
    || true
}

extract_tag_from_output() {
  local output="$1"
  local tag="$2"

  printf '%s' "$output" | perl -0777 -ne "while (/<${tag}>(.*?)<\/${tag}>/gs) { print \$1; }" 2>/dev/null || true
}

append_markdown_block() {
  local current="$1"
  local new_block="$2"

  if [[ -z "${new_block// /}" ]]; then
    printf '%s' "$current"
    return 0
  fi

  if [[ -z "${current// /}" ]]; then
    printf '%s' "$new_block"
    return 0
  fi

  printf '%s\n\n%s' "$current" "$new_block"
}

to_blockquote() {
  local text="$1"

  if [[ -z "${text// /}" ]]; then
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '> %s\n' "$line"
  done <<< "$text"
}

build_impl_history_entry() {
  local iteration="$1"
  local output="$2"
  local resolution="$3"
  local previous_feedback="$4"

  cat <<ENTRY
## iteration ${iteration} / impl
ENTRY

  if [[ -n "${previous_feedback// /}" ]]; then
    if [[ -n "${resolution// /}" ]]; then
      cat <<ENTRY

### review resolution
$(to_blockquote "$resolution")
ENTRY
    else
      cat <<'ENTRY'

### review resolution
> (not explicitly reported)
ENTRY
    fi
  fi

  if [[ -n "${output// /}" ]]; then
    cat <<ENTRY

### output
$(to_blockquote "$output")
ENTRY
  fi
}

build_review_history_entry() {
  local iteration="$1"
  local output="$2"
  local status="$3"

  cat <<ENTRY
## iteration ${iteration} / review

- status: ${status}
ENTRY

  if [[ -n "${output// /}" ]]; then
    cat <<ENTRY

### output
$(to_blockquote "$output")
ENTRY
  fi
}

build_final_review_block() {
  local iteration="$1"
  local status="$2"
  local completed_at_value="$3"
  local output="$4"

  cat <<ENTRY
- iteration: ${iteration}
- status: ${status}
- completed_at: ${completed_at_value}
ENTRY

  if [[ -n "${output// /}" ]]; then
    cat <<ENTRY

### output
$(to_blockquote "$output")
ENTRY
  fi
}

write_state() {
  local started_at_value="$1"
  local temp_file="${STATE_FILE}.tmp.$$"

  cat > "$temp_file" <<STATE
---
active: ${ACTIVE}
phase: ${PHASE}
iteration: ${ITERATION}
max_iterations: ${MAX_ITERATIONS}
started_at: ${started_at_value}
completed_at: ${COMPLETED_AT}
---

<task>
${TASK}
</task>

<feedback>
${FEEDBACK}
</feedback>

<skipped-items>
${SKIPPED_ITEMS}
</skipped-items>

<run-history>
${RUN_HISTORY}
</run-history>

<final-review>
${FINAL_REVIEW}
</final-review>
STATE

  mv "$temp_file" "$STATE_FILE"
}

finalize_state() {
  local started_at_value="$1"
  local final_status="$2"
  local final_output="$3"

  ACTIVE="false"
  PHASE="done"
  COMPLETED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  FINAL_REVIEW="$(build_final_review_block "$ITERATION" "$final_status" "$COMPLETED_AT" "$final_output")"

  write_state "$started_at_value"
}

HOOK_INPUT="$(cat)"
CWD="$(echo "$HOOK_INPUT" | jq -r '.cwd // "."')"
TRANSCRIPT_PATH="$(echo "$HOOK_INPUT" | jq -r '.transcript_path // .transcriptPath // ""')"
AGENT_NAME="$(echo "$HOOK_INPUT" | jq -r '.agent_name // .agentName // ""')"
LAST_OUTPUT="$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // .lastAssistantMessage // empty')"

if ! STATE_FILE="$(resolve_state_file "$CWD")"; then
  exit 0
fi

parse_state "$STATE_FILE"

ACTIVE="${ACTIVE:-true}"
COMPLETED_AT="${COMPLETED_AT:-}"
RUN_HISTORY="${RUN_HISTORY:-}"
FINAL_REVIEW="${FINAL_REVIEW:-}"

if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

if [[ "$AGENT_NAME" != "loop-implementer" ]] && [[ "$AGENT_NAME" != "loop-reviewer" ]]; then
  exit 0
fi

if [[ -z "${LAST_OUTPUT// /}" ]]; then
  LAST_OUTPUT="$(extract_last_output_from_transcript "$TRANSCRIPT_PATH")"
fi

STARTED_AT_VALUE="${STARTED_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

if [[ "$PHASE" == "impl" ]] && [[ "$AGENT_NAME" == "loop-implementer" ]]; then
  PREVIOUS_FEEDBACK="$FEEDBACK"
  NEW_SKIPPED="$(extract_tag_from_output "$LAST_OUTPUT" "skipped")"
  NEW_RESOLUTION="$(extract_tag_from_output "$LAST_OUTPUT" "review-resolution")"

  if [[ -n "${NEW_SKIPPED// /}" ]]; then
    if [[ -n "${SKIPPED_ITEMS// /}" ]]; then
      SKIPPED_ITEMS="${SKIPPED_ITEMS}
${NEW_SKIPPED}"
    else
      SKIPPED_ITEMS="$NEW_SKIPPED"
    fi
  fi

  RUN_HISTORY="$(append_markdown_block "$RUN_HISTORY" "$(build_impl_history_entry "$ITERATION" "$LAST_OUTPUT" "$NEW_RESOLUTION" "$PREVIOUS_FEEDBACK")")"

  ACTIVE="true"
  COMPLETED_AT=""
  FINAL_REVIEW=""
  PHASE="review"
  write_state "$STARTED_AT_VALUE"

  PROMPT="$(build_review_prompt "$ITERATION" "$MAX_ITERATIONS" "$TASK" "$SKIPPED_ITEMS")"

  jq -n --arg prompt "$PROMPT" '{decision: "block", reason: $prompt}'
  exit 0
fi

if [[ "$PHASE" == "review" ]] && [[ "$AGENT_NAME" == "loop-reviewer" ]]; then
  NEW_FEEDBACK=$(echo "$LAST_OUTPUT" | awk '/^## レビューフィードバック/{flag=1} flag{print}')
  if [[ -z "${NEW_FEEDBACK// /}" ]]; then
    NEW_FEEDBACK="$LAST_OUTPUT"
  fi

  FEEDBACK="$NEW_FEEDBACK"
  if echo "$LAST_OUTPUT" | grep -q '<no-action-needed/>'; then
    REVIEW_STATUS="no-action-needed"
  elif [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
    REVIEW_STATUS="max-iterations-reached"
  else
    REVIEW_STATUS="needs-action"
  fi

  RUN_HISTORY="$(append_markdown_block "$RUN_HISTORY" "$(build_review_history_entry "$ITERATION" "$LAST_OUTPUT" "$REVIEW_STATUS")")"

  if [[ "$REVIEW_STATUS" == "no-action-needed" ]]; then
    finalize_state "$STARTED_AT_VALUE" "$REVIEW_STATUS" "$LAST_OUTPUT"
    exit 0
  fi

  if [[ "$REVIEW_STATUS" == "max-iterations-reached" ]]; then
    finalize_state "$STARTED_AT_VALUE" "$REVIEW_STATUS" "$LAST_OUTPUT"
    exit 0
  fi

  ITERATION=$((ITERATION + 1))
  ACTIVE="true"
  COMPLETED_AT=""
  FINAL_REVIEW=""
  PHASE="impl"
  write_state "$STARTED_AT_VALUE"

  PROMPT="$(build_impl_prompt "$ITERATION" "$MAX_ITERATIONS" "$TASK" "$FEEDBACK" "$SKIPPED_ITEMS")"

  jq -n --arg prompt "$PROMPT" '{decision: "block", reason: $prompt}'
  exit 0
fi

exit 0
