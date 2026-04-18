#!/bin/bash

extract_tag_block() {
  local file="$1"
  local tag="$2"

  awk -v open_tag="<${tag}>" -v close_tag="</${tag}>" '
    $0 == open_tag { flag = 1; next }
    $0 == close_tag { flag = 0 }
    flag { print }
  ' "$file"
}

parse_state() {
  local file="$1"
  local frontmatter

  frontmatter=$(awk '/^---$/{if(++n==2)exit; next} n==1{print}' "$file")

  ACTIVE=$(echo "$frontmatter" | grep '^active:' | sed 's/^active: *//' | tr -d '\r' || true)
  PHASE=$(echo "$frontmatter" | grep '^phase:' | sed 's/^phase: *//' | tr -d '\r' || true)
  ITERATION=$(echo "$frontmatter" | grep '^iteration:' | sed 's/^iteration: *//' | tr -d '\r' || true)
  MAX_ITERATIONS=$(echo "$frontmatter" | grep '^max_iterations:' | sed 's/^max_iterations: *//' | tr -d '\r' || true)
  STARTED_AT=$(echo "$frontmatter" | grep '^started_at:' | sed 's/^started_at: *//' | tr -d '\r' || true)
  COMPLETED_AT=$(echo "$frontmatter" | grep '^completed_at:' | sed 's/^completed_at: *//' | tr -d '\r' || true)

  TASK=$(extract_tag_block "$file" "task")
  FEEDBACK=$(extract_tag_block "$file" "feedback")
  SKIPPED_ITEMS=$(extract_tag_block "$file" "skipped-items")
  RUN_HISTORY=$(extract_tag_block "$file" "run-history")
  FINAL_REVIEW=$(extract_tag_block "$file" "final-review")
}

if [[ -n "${1:-}" ]]; then
  parse_state "$1"
fi
