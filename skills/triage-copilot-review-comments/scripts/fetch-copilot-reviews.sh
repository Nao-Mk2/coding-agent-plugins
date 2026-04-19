#!/usr/bin/env bash
set -euo pipefail

gh pr view --json headRepository,number 2>/dev/null || { echo "Pull Request not found." >&2; exit 1; }

gh api graphql \
  -F owner='tokyucorp' \
  -F name='{{repository_name}}' \
  -F pr={{pr_number}} \
  -f query='
    query($owner:String!, $name:String!, $pr:Int!) {
      repository(owner:$owner, name:$name) {
        pullRequest(number:$pr) {
          reviewThreads(first:100) {
            nodes {
              id
              isResolved
              comments(first:100) {
                nodes { author { login } body url }
              }
            }
          }
        }
      }
    }
  ' \
| jq '.data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved == false)
  | {id: .id, comments: (.comments.nodes[] | select(.author.login == "copilot-pull-request-reviewer") | {url: .url, body: .body})}'