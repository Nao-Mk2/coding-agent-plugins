#!/usr/bin/env bash

set -euo pipefail

reviewer_login="copilot-pull-request-reviewer"
pull_request_number=""
dry_run=0

usage() {
  cat <<'EOF'
Usage: reply_and_resolve.sh [--pr NUMBER] [--reviewer LOGIN] [--dry-run]

Replies to unresolved review comments whose author matches the reviewer login,
using commit messages that reference the corresponding discussion_r URL, then
resolves the review thread if the reply succeeds.

Options:
  --pr NUMBER         Pull request number. If omitted, infer from current branch.
  --reviewer LOGIN    Review comment author login. Default: copilot-pull-request-reviewer
  --dry-run           Print planned actions without posting replies or resolving threads.
  --help              Show this help.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command not found: $1" >&2
    exit 1
  fi
}

resolve_pull_request_number() {
  if [[ -n "$pull_request_number" ]]; then
    printf '%s\n' "$pull_request_number"
    return
  fi

  gh pr view --json number --jq '.number'
}

resolve_repo() {
  gh repo view --json owner,name --jq '.owner.login + "/" + .name'
}

resolve_viewer_login() {
  gh api user --jq '.login'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      pull_request_number="${2:?missing pull request number}"
      shift 2
      ;;
    --reviewer)
      reviewer_login="${2:?missing reviewer login}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command gh
require_command git
require_command python3

repo_full_name="$(resolve_repo)"
owner="${repo_full_name%%/*}"
repo="${repo_full_name#*/}"
viewer_login="$(resolve_viewer_login)"

if ! pr_number="$(resolve_pull_request_number)"; then
  echo "failed to resolve pull request number from current branch; specify --pr" >&2
  exit 1
fi

tmp_json="$(mktemp)"
cleanup() {
  rm -f "$tmp_json"
}
trap cleanup EXIT

gh api graphql \
  -f query='query($owner: String!, $repo: String!, $pr: Int!) { repository(owner: $owner, name: $repo) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 100) { nodes { databaseId url body author { login } } } } } } } }' \
  -F owner="$owner" \
  -F repo="$repo" \
  -F pr="$pr_number" > "$tmp_json"

python3 - <<'PY' "$tmp_json" "$reviewer_login" "$viewer_login" "$owner" "$repo" "$pr_number" "$dry_run"
import json
import subprocess
import sys

json_path, reviewer_login, viewer_login, owner, repo, pr_number, dry_run = sys.argv[1:8]
dry_run = dry_run == "1"

with open(json_path, encoding="utf-8") as fh:
    payload = json.load(fh)

threads = payload["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]

processed = []
skipped = []
unmatched = []
resolve_failed = []


def run(cmd):
    return subprocess.run(cmd, check=True, text=True, capture_output=True)


for thread in threads:
    if thread["isResolved"]:
        continue

    comments = thread["comments"]["nodes"]
    targets = [comment for comment in comments if comment["author"] and comment["author"]["login"] == reviewer_login]
    if not targets:
        continue

    for comment in targets:
        url = comment["url"]
        if "#discussion_" not in url:
            skipped.append({"comment_id": comment["databaseId"], "reason": "discussion id not found in URL"})
            continue

        discussion_id = url.rsplit("#", 1)[1]

        try:
            commit_hash = run(["git", "log", f"--grep={discussion_id}", "-n", "1", "--format=%H"]).stdout.strip()
        except subprocess.CalledProcessError as exc:
            raise SystemExit(exc.stderr or exc.stdout)

        if not commit_hash:
            unmatched.append({"comment_id": comment["databaseId"], "url": url})
            continue

        commit_url = f"https://github.com/{owner}/{repo}/commit/{commit_hash}"
        reply_body = f"{commit_url} で対応"

        duplicate = False
        for existing_comment in comments:
          if existing_comment.get("body") == reply_body:
            duplicate = True
            break

        if duplicate:
            skipped.append({"comment_id": comment["databaseId"], "reason": "same reply already exists", "commit_hash": commit_hash})
            continue

        if dry_run:
            processed.append({
                "comment_id": comment["databaseId"],
                "thread_id": thread["id"],
                "commit_hash": commit_hash,
                "reply_body": reply_body,
                "resolved": False,
                "dry_run": True,
            })
            continue

        run([
            "gh", "api", "-X", "POST",
            f"repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment['databaseId']}/replies",
            "-f", f"body={reply_body}",
        ])

        resolved = True
        try:
            run([
                "gh", "api", "graphql",
                "-f", "query=mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } } }",
                "-F", f"threadId={thread['id']}",
            ])
        except subprocess.CalledProcessError:
            resolved = False
            resolve_failed.append({"comment_id": comment["databaseId"], "thread_id": thread["id"]})

        processed.append({
            "comment_id": comment["databaseId"],
            "thread_id": thread["id"],
            "commit_hash": commit_hash,
            "reply_body": reply_body,
            "resolved": resolved,
            "dry_run": False,
        })

result = {
    "pr_number": int(pr_number),
    "reviewer_login": reviewer_login,
    "viewer_login": viewer_login,
    "processed": processed,
    "skipped": skipped,
    "unmatched": unmatched,
    "resolve_failed": resolve_failed,
}

print(json.dumps(result, ensure_ascii=False, indent=2))
PY