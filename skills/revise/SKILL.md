---
name: revise
description: >
  Address PR review comments on an existing branch. Reads reviewer feedback,
  applies fixes, runs quality checks, and pushes to the same PR. Used by the
  Forge orchestrator when a human requests changes on a PR.
allowed-tools: Bash(gh *), Bash(git *), Bash(pnpm *), Read, Write, Edit, MultiEdit, Glob, Grep, Task
---

# /revise — Address PR Review Feedback

You are the Forge revision agent. Your job is to pick up one issue labeled `agent:revision-needed`, read the PR review comments left by the human reviewer, apply fixes on the existing branch, and push updates to the same PR. You handle exactly one issue per invocation — then return control to `/forge`.

## Revision Cycle

### Step 1: Find the next revision-needed issue

```bash
gh issue list --state open --label "agent:revision-needed" --json number,title,body,labels --jq 'sort_by(.number) | .[0]'
```

If no issues have the `agent:revision-needed` label, report this and return to `/forge`.

### Step 2: Find the linked PR

The PR branch follows the naming convention `agent/issue-{N}-*`. Find it:

```bash
ISSUE={number}
PR_JSON=$(gh pr list --state open --json number,headRefName,url,reviewDecision \
  --jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE}-\"))] | sort_by(.number) | .[0]")
```

If `PR_JSON` is empty or null, no open PR exists for this issue. The PR may have been closed. Relabel the issue back to `agent:ready` so `/build` can retry:

```bash
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')
```

If `PR_NUMBER` is empty, relabel and return. Otherwise, extract the remaining fields:

```bash
PR_BRANCH=$(echo "$PR_JSON" | jq -r '.headRefName')
PR_URL=$(echo "$PR_JSON" | jq -r '.url')
REVIEW_DECISION=$(echo "$PR_JSON" | jq -r '.reviewDecision')
```

If no open PR is found for this issue, the PR may have been closed. Relabel the issue back to `agent:ready` so `/build` can retry:

```bash
gh issue edit $ISSUE --remove-label "agent:revision-needed" --add-label "agent:ready"
sleep 1
```

Report this and return to `/forge`.

**Guard: If `reviewDecision` is `APPROVED`, the reviewer has approved despite any stale comment threads.** Remove `agent:revision-needed`, add `agent:done`, and return to `/forge` without making changes:

```bash
if [ "$REVIEW_DECISION" = "APPROVED" ]; then
  gh issue edit $ISSUE --remove-label "agent:revision-needed" --add-label "agent:done"
  sleep 1
  # Return to /forge — reviewer approved, no revision needed
fi
```

### Step 2.5: Check revision count

Count prior revision attempts by looking for "## Revision Summary" comments already posted by previous `/revise` runs:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
# gh pr comment posts to the issues API endpoint, so count there
REVISION_COUNT=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments" --paginate 2>/dev/null | jq -s 'add | map(select(.body | test("^## Revision Summary"))) | length' || echo 0)
MAX_REVISIONS=3
```

If the revision count has reached the limit, escalate instead of retrying:

```bash
if [ "$REVISION_COUNT" -ge "$MAX_REVISIONS" ]; then
  gh issue edit $ISSUE --remove-label "agent:revision-needed" --add-label "agent:needs-human"
  sleep 1
  gh issue comment $ISSUE --body "$(cat <<ESCALATE
## Revision Limit Reached

This issue has been revised **${REVISION_COUNT}** times (limit: ${MAX_REVISIONS}) without converging on an approved solution.

**Prior revision attempts are visible in PR #${PR_NUMBER} comments.**

Human review is needed to determine the next approach — the automated revision cycle is not converging.
ESCALATE
)"
  sleep 1
  # Return to /forge — do not attempt another revision
fi
```

### Step 3: Claim the issue

```bash
gh issue edit $ISSUE --remove-label "agent:revision-needed" --add-label "agent:in-progress"
sleep 1
echo $ISSUE > .forge-current-issue
```

### Step 4: Checkout the existing branch and sync with main

```bash
git fetch origin
git checkout $PR_BRANCH
git pull origin $PR_BRANCH
```

Merge main to pick up any changes that landed since the PR was opened:

```bash
git merge origin/main --no-edit
```

**If there are merge conflicts:**

1. **List conflicted files:**
   ```bash
   CONFLICTS=$(git diff --name-only --diff-filter=U)
   ```

2. **Classify each conflict.** Read the conflicted file and examine the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`). Categorize as:
   - **Simple** — non-overlapping changes (e.g., different imports added, adjacent but non-intersecting edits, formatting-only differences). Resolve by keeping both sides' intent.
   - **Complex** — both sides modified the same function body, rewrote the same logic block, or made semantically incompatible changes. These require human judgment.

3. **Resolve simple conflicts.** For each simple conflict, edit the file to combine both changes logically, remove all conflict markers, and stage the file:
   ```bash
   git add <resolved-file>
   ```

4. **If any complex conflicts remain**, abort the merge and escalate:
   ```bash
   REMAINING_CONFLICTS=$(git diff --name-only --diff-filter=U)
   git merge --abort
   gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:needs-human"
   sleep 1
   gh issue comment $ISSUE --body "$(cat <<COMMENT
   ## Merge Conflict — Human Review Needed

   While syncing PR branch \`${PR_BRANCH}\` with main, merge conflicts arose in files where both sides modified the same logic:

   **Conflicted files:**
   $(echo "$REMAINING_CONFLICTS" | sed 's/^/- /')

   Some conflicts were too complex for automated resolution (both sides modified the same logic).

   **Options:**
   1. Resolve conflicts manually on the branch
   2. Close the PR and re-build from current main

   COMMENT
   )"
   sleep 1
   ```
   Return to `/forge` after escalating.

5. **If all conflicts were resolved**, complete the merge and verify with quality checks:
   ```bash
   git commit --no-edit
   ```

   Run all four quality checks to catch regressions from the merge resolution, capturing any failures:
   ```bash
   QUALITY_ERROR=$(
     {
       pnpm lint &&
       pnpm tsc --noEmit &&
       pnpm test &&
       pnpm build
     } 2>&1
   ) || true
   ```

   **If any check fails after conflict resolution**, the resolution introduced a regression. Abort:
   ```bash
   if [ $? -ne 0 ] || echo "$QUALITY_ERROR" | grep -qiE '(error|failed|FAIL)'; then
     git reset --hard HEAD~1
     gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:needs-human"
     sleep 1
     gh issue comment $ISSUE --body "$(cat <<COMMENT
   ## Merge Conflict Resolution Failed Quality Checks

   Auto-resolved merge conflicts in \`${PR_BRANCH}\`, but quality checks failed after resolution:

   \`\`\`
   $QUALITY_ERROR
   \`\`\`

   The merge resolution has been reverted. Human review needed.
   COMMENT
     )"
     sleep 1
   fi
   ```
   Return to `/forge` after escalating.

   If all checks pass, proceed to Step 5.

### Step 5: Fetch and read all review comments

Retrieve review comments using the GitHub API. Get both line-level comments and top-level review bodies:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# Line-level review comments (specific code feedback)
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --jq '.[] | {id: .id, path: .path, line: .original_line, diff_hunk: .diff_hunk, body: .body, user: .user.login}'

# Top-level review bodies (summary feedback with CHANGES_REQUESTED state)
gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --jq '.[] | select(.state == "CHANGES_REQUESTED") | {id: .id, body: .body, user: .user.login}'
```

Read and understand all comments. Group line-level comments by file path for efficient processing.

Also read:
- `CLAUDE.md` — project conventions
- The issue body — original requirements and acceptance criteria
- The files referenced in comments — understand context before modifying

### Step 6: Address each comment

Process review feedback systematically:

1. **Group line-level comments by file.** Open each file once, apply all relevant fixes, then move to the next file.
2. **Address top-level review body comments.** These may describe broader concerns that span multiple files.
3. **For each comment, determine if it is actionable:**
   - Clear code change request (e.g., "rename this variable," "add error handling here," "use a different approach for X") — apply the fix.
   - Architectural question or ambiguous feedback — if you can reasonably infer the right approach from context (CLAUDE.md, issue body, existing code patterns), do so. If not, collect these for escalation in Step 11.

**Do not skip comments.** Every comment must be either addressed with a code change or flagged for escalation.

### Step 7: Quality checks

Run all four checks:

```bash
pnpm lint
pnpm tsc --noEmit
pnpm test
pnpm build
```

**If all pass:** proceed to Step 8.

**If any fail:** spawn the **debug agent**. Read `.claude/skills/build/references/debug-agent.md` and spawn a Task with its contents as the prompt. Append the full error output, the list of files changed during this revision, and the review comments for context. The debug agent returns a prioritized list of fixes — apply them in order, then re-run all four checks. You get **2 total attempts** (the initial run + one retry after the debug agent's fixes).

### Step 8: On success — commit and push

```bash
# Stage only the files you modified to address review feedback.
# Do NOT use git add -A or git add . — this can stage unintended files.
git add <specific files>

# Commit with conventional commit format referencing the issue
git commit -m "fix: address review feedback (#$ISSUE)"

# Push to the existing branch (the PR updates automatically)
git push origin $PR_BRANCH
```

### Step 9: Post summary and re-request review

Post a comment on the PR summarizing what was changed for each review comment:

```bash
gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## Revision Summary

Addressed review feedback:

- **[file:line]** — [brief description of change made in response to comment]
- **[file:line]** — [brief description of change made in response to comment]
- ...

All quality checks pass (lint, typecheck, test, build).
EOF
)"
sleep 1
```

Re-request review from the original reviewer(s):

```bash
# Get reviewers who requested changes
REVIEWERS=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --jq '[.[] | select(.state == "CHANGES_REQUESTED") | .user.login] | unique | join(",")')
gh pr edit $PR_NUMBER --add-reviewer "$REVIEWERS"
sleep 1
```

### Step 10: Update issue label

```bash
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:done"
sleep 1
```

### Step 11: On failure — escalate

If quality checks fail after 2 attempts (initial + debug-assisted retry), or if review comments contain feedback the agent cannot address:

```bash
# Push what you have (so the human can see the attempt)
git add <specific files>
git commit -m "wip: partial review fixes (#$ISSUE)"
git push origin $PR_BRANCH

# Escalate
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:needs-human"
sleep 1
gh issue comment $ISSUE --body "$(cat <<'COMMENT'
## Revision Failed

**Attempts:** 2/2

**Review comments addressed:** [N of M]

**Unaddressed comments:**
- [comment summary] — [reason it couldn't be addressed]

**Error (if quality checks failed):**
```
{error output}
```

**Debug agent diagnosis:**
[Summary of what the debug agent identified and what fixes were attempted]

**Branch:** `$PR_BRANCH` (pushed with current state)
COMMENT
)"
sleep 1
```

### Step 12: Return to orchestrator

After completing (success or failure), end with:

**Now invoke `/forge` to determine the next action.**

## Rules

- **One issue per invocation.** Never batch multiple revision issues.
- **No review or test sub-agents.** The human IS the reviewer. Tests already exist from the original `/build`. Only spawn the debug agent if quality checks fail.
- **Preserve existing tests.** Do not modify test files unless a review comment specifically asks for it. If your code changes cause test failures, fix the implementation to match the tests, not the other way around.
- **Don't exceed the issue's scope.** Only address what the reviewer asked for. Don't refactor surrounding code or add features.
- **Every comment must be resolved or escalated.** Don't silently skip feedback.
- **Always push before updating labels.** The branch must be updated on the remote before marking the issue done.
- **Write `.forge-current-issue`** so the Stop hook knows which issue to comment on.
- **Commit message format:** `fix: address review feedback (#N)` — always use `fix:` prefix for revisions.
