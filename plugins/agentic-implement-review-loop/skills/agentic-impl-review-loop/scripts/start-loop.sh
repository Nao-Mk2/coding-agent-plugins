#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK=""
MAX_ITERATIONS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations)
      MAX_ITERATIONS="${2:?missing value for --max-iterations}"
      shift 2
      ;;
    *)
      if [[ -z "$TASK" ]]; then
        TASK="$1"
      else
        TASK="${TASK} $1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$TASK" ]]; then
  echo "usage: bash start-loop.sh \"task description\" [--max-iterations N]" >&2
  exit 1
fi

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$MAX_ITERATIONS" -lt 1 ]]; then
  echo "error: --max-iterations must be an integer greater than or equal to 1" >&2
  exit 1
fi

STATE_DIR=".copilot"
STATE_FILE="${STATE_DIR}/impl-review-loop-state.md"

if [[ -f "$STATE_FILE" ]]; then
  EXISTING_ACTIVE="$(grep '^active:' "$STATE_FILE" | sed 's/^active: *//' | tr -d '\r' || true)"

  if [[ "$EXISTING_ACTIVE" == "true" ]]; then
    echo "error: loop is already active: $STATE_FILE" >&2
    echo "cancel with: rm -f $STATE_FILE" >&2

  exit 1
fi

mkdir -p "$STATE_DIR"

STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "$STATE_FILE" <<STATE
---
active: true
phase: impl
iteration: 1
max_iterations: ${MAX_ITERATIONS}
started_at: ${STARTED_AT}
completed_at:
---

<task>
${TASK}
</task>

<feedback>
</feedback>

<skipped-items>
</skipped-items>

<run-history>
</run-history>

<final-review>
</final-review>
STATE

echo "impl-review-loop: initialized ${STATE_FILE}" >&2
echo "" >&2
