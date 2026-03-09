---
name: revise
description: >
  Address PR review comments or CI failures on an existing branch. Reads
  reviewer feedback or CI failure logs, applies fixes, runs quality checks,
  and pushes to the same PR. Used by the Forge orchestrator when a human
  requests changes on a PR or when CI checks fail.
allowed-tools: Bash(gh *), Bash(git *), Bash(pnpm *), Read, Write, Edit, MultiEdit, Glob, Grep, Task, WebSearch, WebFetch
---

# /revise — Address PR Review Feedback

You are the Forge revision agent. Your job is to pick up the `agent:done` issue whose PR has failing CI checks or `CHANGES_REQUESTED`, diagnose and fix the problem, and push updates to the same PR. You handle exactly one issue per invocation — then return control to `/forge`.

## Revision Cycle

### Step 1: Find the issue needing revision

The `/forge` orchestrator routes here when an `agent:done` issue has failing CI checks, `CHANGES_REQUESTED`, or Copilot review comments on its PR. Find it by fetching all open PRs once and correlating locally. **CI failures take priority**, then human review, then Copilot comments.

```bash
# Get all agent:done issues and all open PRs in two calls
DONE_ISSUES=$(gh issue list --state open --label "agent:done" --json number,title,body,labels --jq 'sort_by(.number)')
OPEN_PRS=$(gh pr list --state open --json number,headRefName,reviewDecision,statusCheckRollup -L 200)

# Check for CI failures first (highest priority)
for ISSUE_NUM in $(echo "$DONE_ISSUES" | jq -r '.[].number'); do
  HAS_CI_FAILURE=$(echo "$OPEN_PRS" | jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE_NUM}-\"))] | .[0].statusCheckRollup // [] | [.[] | select(.conclusion == \"FAILURE\" or .conclusion == \"failure\")] | length > 0")
  if [ "$HAS_CI_FAILURE" = "true" ]; then
    ISSUE=$ISSUE_NUM
    CI_REPAIR_MODE=true
    break
  fi
done

# Then check for human CHANGES_REQUESTED
if [ -z "$ISSUE" ]; then
  for ISSUE_NUM in $(echo "$DONE_ISSUES" | jq -r '.[].number'); do
    if echo "$OPEN_PRS" | jq -e "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE_NUM}-\")) | select(.reviewDecision == \"CHANGES_REQUESTED\")] | .[0]" >/dev/null 2>&1; then
      ISSUE=$ISSUE_NUM
      break
    fi
  done
fi

# Then check for unresolved Copilot review threads (when /forge routes here for Copilot mode)
# Use GraphQL to check thread resolution status — the REST comments endpoint returns
# all comments regardless of resolution, which would cause infinite re-routing.
if [ -z "$ISSUE" ]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  OWNER=$(echo "$REPO" | cut -d/ -f1)
  REPO_NAME=$(echo "$REPO" | cut -d/ -f2)
  for ISSUE_NUM in $(echo "$DONE_ISSUES" | jq -r '.[].number'); do
    PR_NUM=$(echo "$OPEN_PRS" | jq -r "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE_NUM}-\"))] | .[0].number // empty" 2>/dev/null)
    if [ -n "$PR_NUM" ]; then
      UNRESOLVED_COPILOT=$(gh api graphql -f query="{ repository(owner: \"$OWNER\", name: \"$REPO_NAME\") { pullRequest(number: $PR_NUM) { reviewThreads(first: 100) { nodes { isResolved comments(first: 1) { nodes { author { login } } } } } } } }" \
        --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | select(.comments.nodes[0].author.login | test("copilot"; "i"))] | length' 2>/dev/null || echo "0")
      if [ "$UNRESOLVED_COPILOT" -gt 0 ] 2>/dev/null; then
        ISSUE=$ISSUE_NUM
        COPILOT_MODE=true
        break
      fi
    fi
  done
fi
```

If no issues have CI failures, `CHANGES_REQUESTED`, or Copilot comments, report this and return to `/forge`.

### Step 2: Find the linked PR

The PR branch follows the naming convention `agent/issue-{N}-*`. Find it:

```bash
PR_JSON=$(gh pr list --state open --json number,headRefName,url,reviewDecision,statusCheckRollup \
  --jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE}-\"))] | sort_by(.number) | .[0]")
```

If `PR_JSON` is empty or null, no open PR exists for this issue. Remove `agent:done` so the issue returns to backlog:

```bash
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')
```

If `PR_NUMBER` is empty, relabel and return. Otherwise, extract the remaining fields:

```bash
PR_BRANCH=$(echo "$PR_JSON" | jq -r '.headRefName')
PR_URL=$(echo "$PR_JSON" | jq -r '.url')
REVIEW_DECISION=$(echo "$PR_JSON" | jq -r '.reviewDecision')
```

If no open PR is found for this issue, remove the label so the issue returns to backlog:

```bash
gh issue edit $ISSUE --remove-label "agent:done"
```

Report this and return to `/forge`.

**Guard: If `reviewDecision` is `APPROVED` and this is NOT CI repair mode or Copilot mode**, the reviewer has approved despite any stale comment threads. Keep `agent:done` and return to `/forge` without making changes:

```bash
if [ "$REVIEW_DECISION" = "APPROVED" ] && [ "$CI_REPAIR_MODE" != "true" ] && [ "$COPILOT_MODE" != "true" ]; then
  # Return to /forge — reviewer approved, no revision needed
fi
```

An APPROVED PR can still have failing CI or unresolved Copilot threads — the approval covers human code quality, not CI status or Copilot feedback. CI repair and Copilot modes must bypass this guard.

### Step 2.5: Check revision count (review mode only)

**Skip this step in CI repair mode or Copilot mode** — CI repairs and Copilot review fixes are not revisions and should not be blocked by the revision limit.

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
  # Invoke /ask — it handles the comment format and label management
fi
```

Invoke `/ask` with type `revision-limit`, passing:
- `REVISION_COUNT` — number of prior revision attempts
- `MAX_REVISIONS` — the limit (3)
- `PR_NUMBER` — the PR number for reference

`/ask` handles the comment format and label management (`agent:done` → `agent:needs-human`). Return to `/forge` — do not attempt another revision.

### Step 3: Claim the issue

```bash
gh issue edit $ISSUE --remove-label "agent:done" --add-label "agent:in-progress"
mkdir -p .forge-temp
echo $ISSUE > .forge-temp/current-issue
```

### Step 3.5: Record revision start time

```bash
BUILD_START=$(date +%s)
BUILD_TIMEOUT=1800  # 30 minutes per revision
```

Before each subsequent major step (Steps 5, 6, 7, 8), check elapsed time:

```bash
ELAPSED=$(( $(date +%s) - BUILD_START ))
if [ "$ELAPSED" -ge "$BUILD_TIMEOUT" ]; then
  echo "Revision timeout reached (${ELAPSED}s >= ${BUILD_TIMEOUT}s)"
fi
```

If timeout is reached, commit WIP, push, keep `agent:in-progress`, and return to `/forge`:

```bash
git add <files modified so far>
git commit -m "wip: revision timeout on issue #${ISSUE}" || true
git push origin $PR_BRANCH 2>/dev/null || true
gh issue comment $ISSUE --body "Revision timed out after ${ELAPSED}s. WIP pushed. Next session will resume."
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
   ```

   Invoke `/ask` with type `merge-conflict`, passing:
   - `CONFLICTED_FILES` — the list of conflicted files (from `$REMAINING_CONFLICTS`, formatted as a bulleted list)
   - `PR_BRANCH` — the PR branch name
   - `ADDITIONAL_CONTEXT` — `"Some conflicts were too complex for automated resolution (both sides modified the same logic)."`

   `/ask` handles the comment format and label management (`agent:in-progress` → `agent:needs-human`). Return to `/forge` after escalating.

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

   **If any check fails after conflict resolution**, the resolution introduced a regression. Revert and escalate:
   ```bash
   if [ $? -ne 0 ] || echo "$QUALITY_ERROR" | grep -qiE '(error|failed|FAIL)'; then
     git revert HEAD --no-edit
     git push origin $PR_BRANCH
   fi
   ```

   Invoke `/ask` with type `merge-conflict`, passing:
   - `CONFLICTED_FILES` — the list of files that had conflicts (from Step 4.3)
   - `PR_BRANCH` — the PR branch name
   - `ADDITIONAL_CONTEXT` — the quality check error output (set to include "Auto-resolved merge conflicts, but quality checks failed after resolution. The merge resolution has been reverted." followed by the error)

   `/ask` handles the comment format and label management (`agent:in-progress` → `agent:needs-human`). Return to `/forge` after escalating.

   If all checks pass, proceed to Step 5.

### Step 5: Fetch failure context

**If CI repair mode** (`CI_REPAIR_MODE=true`): fetch CI failure logs instead of review comments.

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# Get the most recent failed workflow run on this branch
FAILED_RUN=$(gh run list --branch $PR_BRANCH --status failure --limit 1 --json databaseId,name,conclusion --jq '.[0]')
RUN_ID=$(echo "$FAILED_RUN" | jq -r '.databaseId // empty')

if [ -z "$RUN_ID" ]; then
  # No failed runs found — CI failure may have been resolved by a retry or re-run
  # Return to /forge without making changes
fi

# Fetch the failed job logs (shows only failed steps)
CI_LOGS=$(gh run view $RUN_ID --log-failed 2>&1 | tail -200)

# Also get the list of failed jobs for context
FAILED_JOBS=$(gh run view $RUN_ID --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name: .name, conclusion: .conclusion}')
```

Read the CI failure logs carefully. Identify which files need changes. Also read:
- `CLAUDE.md` — project conventions
- The failing source files — understand context before modifying
- `.github/workflows/` — understand the CI configuration to determine if the failure is in code or CI config

**Skip to Step 6** (Step 5.5 does not apply in CI repair mode — there are no review comments to evaluate).

---

**If Copilot mode** (`COPILOT_MODE=true`): fetch Copilot's review comments.

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# Copilot's COMMENTED review body (top-level summary)
gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
  --jq '[.[] | select(.user.login | test("copilot"; "i"))] | sort_by(.submitted_at) | last | {id: .id, body: .body, state: .state}'

# Copilot's line-level comments (specific code feedback)
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" \
  --jq '[.[] | select(.user.login | test("copilot"; "i"))] | .[] | {id: .id, path: .path, line: .original_line, diff_hunk: .diff_hunk, body: .body}'
```

Read and understand all Copilot comments. Group line-level comments by file path for efficient processing.

Also read:
- `CLAUDE.md` — project conventions
- The files referenced in comments — understand context before modifying

**Proceed to Step 5.5** — evaluate Copilot comments using the same evaluator as human reviews (APPLY/CHALLENGE/RESEARCH/ESCALATE). For Copilot comments, CHALLENGE verdicts should still be replied to with evidence (Copilot will not respond, but the thread serves as documentation).

---

**If review mode** (default): fetch review comments.

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
- `SPECIFICATION.md` — architectural decisions and rationale (if the reviewer questions a design choice, check whether SPECIFICATION.md explains the reasoning)
- The issue body — original requirements and acceptance criteria
- The files referenced in comments — understand context before modifying

### Step 5.5: Evaluate comments (review and Copilot modes)

Before applying any fixes, evaluate whether each review comment is correct. Spawn a **comment evaluator agent** via the Task tool. Read `.claude/skills/revise/references/comment-evaluator-agent.md` and spawn a Task with its contents as the prompt. Append all review comments, the project's CLAUDE.md, SPECIFICATION.md, the current code in referenced files, and the issue body as context.

The evaluator returns a verdict for each comment:

| Verdict | Action |
|---------|--------|
| APPLY | Comment is correct — apply the fix in Step 6 |
| CHALLENGE | Comment appears incorrect — reply on the PR thread with evidence, do NOT apply |
| RESEARCH | Comment needs verification — search the web, then re-categorize as APPLY or CHALLENGE |
| ESCALATE | Ambiguous or can't determine — collect for escalation in Step 11 |

**Handle RESEARCH verdicts:** For each RESEARCH comment, use WebSearch/WebFetch to look up the claim (e.g., API documentation, WCAG standards, deprecation notices). Based on the findings, re-categorize as APPLY or CHALLENGE.

**Handle CHALLENGE verdicts:** For each CHALLENGE comment, reply on the PR thread with the evaluator's evidence:

```bash
gh api "repos/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
  -f body="[Evidence-based pushback explaining why the current approach is correct]"
```

### Step 6: Apply fixes

**If CI repair mode:** Diagnose the CI failure from the logs fetched in Step 5 and fix the root cause. Common CI-only failures include:
- Platform-specific test failures (Linux CI vs macOS local)
- CI-only lint rules or stricter configurations
- Missing environment variables or dependencies in the CI environment
- Build output differences between local and CI

Fix the code to pass CI — do not modify the CI workflow configuration unless the issue specifically calls for it.

**If review mode:** Process only the comments categorized as APPLY (or re-categorized from RESEARCH to APPLY):

1. **Group line-level comments by file.** Open each file once, apply all relevant fixes, then move to the next file.
2. **Address top-level review body comments.** These may describe broader concerns that span multiple files.

**Do not skip comments.** Every comment must be either applied, challenged with evidence, or flagged for escalation.

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

**Atomic commits:** If your revision touches multiple independent concerns (e.g., fixing a naming issue in one file and adding error handling in another), split into separate commits — one per logical change.

```bash
# Stage only the files for one logical change at a time.
# Do NOT use git add -A or git add . — this can stage unintended files.
git add <files for concern 1>
git commit -m "fix: rename handler to match convention (#$ISSUE)"

git add <files for concern 2>
git commit -m "fix: add error boundary for fetch failures (#$ISSUE)"

# Push to the existing branch (the PR updates automatically)
git push origin $PR_BRANCH
```

### Step 9: Post summary, resolve threads, and re-request review

**If CI repair mode:** Post a CI repair summary:

```bash
gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## CI Repair Summary

**Failed checks:** [list of CI jobs that failed]
**Root cause:** [brief diagnosis of what caused the failure]
**Fix:** [brief description of changes made]

All quality checks pass (lint, typecheck, test, build).
EOF
)"
```

Skip thread resolution (no review threads to resolve) and skip re-requesting review. Proceed to Step 10.

---

**If Copilot mode:** Post a Copilot review summary (distinct header — does not count as a revision):

```bash
gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## Copilot Review Summary

### Applied
- **[file:line]** — [brief description of change made in response to Copilot comment]
- ...

### Challenged
- **[file:line]** — [brief summary of why the suggestion was not applied, with evidence]
- ...

[Or omit empty sections]

All quality checks pass (lint, typecheck, test, build).
EOF
)"
```

**Resolve ALL Copilot comment threads** (both APPLY and CHALLENGE) using the same GraphQL approach as review mode (Step 9 review mode). Unlike human reviews, Copilot threads must all be resolved because Copilot won't respond to challenges and `required_review_thread_resolution` would block merge on unresolved threads. The challenge reply in the thread serves as documentation.

**Do not re-request review** — Copilot reviews are advisory. Proceed to Step 10.

---

**If review mode:** Post a revision summary:

```bash
gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## Revision Summary

### Applied
- **[file:line]** — [brief description of change made in response to comment]
- ...

### Challenged
- **[file:line]** — [brief summary of why the suggestion was not applied, with evidence]
- ...

### Escalated
- **[file:line]** — [brief summary of what needs human input]
- ...

[Or omit empty sections]

All quality checks pass (lint, typecheck, test, build).
EOF
)"
```

**Resolve PR comment threads** for APPLY comments (signals "addressed"). Get thread IDs and resolve via GraphQL:

```bash
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") { pullRequest(number: PR_NUM) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { body } } } } } } }'
```

For each APPLY comment whose thread was found:

```bash
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "THREAD_ID"}) { thread { isResolved } } }'
```

Leave CHALLENGE and ESCALATE threads open — they need continued dialogue or human input.

Re-request review from the original reviewer(s):

```bash
# Get reviewers who requested changes
REVIEWERS=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --jq '[.[] | select(.state == "CHANGES_REQUESTED") | .user.login] | unique | join(",")')
gh pr edit $PR_NUMBER --add-reviewer "$REVIEWERS"
```

### Step 10: Update issue label

```bash
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:done"
```

### Step 11: On failure — escalate

If quality checks fail after 2 attempts (initial + debug-assisted retry), if review comments contain feedback the agent cannot address, or if CI failures cannot be diagnosed:

```bash
# Push what you have (so the human can see the attempt)
git add <specific files>
git commit -m "wip: partial review fixes (#$ISSUE)"
git push origin $PR_BRANCH

# Escalate
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:needs-human"
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
```

### Step 12: Return to orchestrator

After completing (success or failure), end with:

**Now invoke `/forge` to determine the next action.**

## Rules

- **One issue per invocation.** Never batch multiple revision issues.
- **No review or test sub-agents.** The human IS the reviewer. Tests already exist from the original `/build`. Only spawn the debug agent if quality checks fail.
- **Preserve existing tests.** Do not modify test files unless a review comment specifically asks for it. If your code changes cause test failures, fix the implementation to match the tests, not the other way around.
- **Don't exceed the issue's scope.** Only address what the reviewer asked for. Don't refactor surrounding code or add features. If you discover bugs or improvements outside scope, file a new issue (with `--label "ai-generated"`) instead of fixing inline.
- **Every comment must be resolved or escalated.** Don't silently skip feedback.
- **Always push before updating labels.** The branch must be updated on the remote before marking the issue done.
- **Write `.forge-temp/current-issue`** so the Stop hook knows which issue to comment on.
- **Respect the revision timeout.** Check elapsed time before Steps 5, 6, 7, and 8. If the 30-minute limit is reached, commit WIP and push — the next session resumes from the branch.
- **Commit message format:** `fix: {descriptive message} (#N)` — always use `fix:` prefix for revisions. Use a specific description per commit when splitting atomic commits (e.g., `fix: rename handler to match convention (#N)`).
- **CI repair does not count as a revision.** The `## CI Repair Summary` header is distinct from `## Revision Summary` and does not increment the revision count checked in Step 2.5.
- **Copilot review does not count as a revision.** The `## Copilot Review Summary` header is distinct from `## Revision Summary` and does not increment the revision count. No revision limit applies to Copilot review fixes.
- **Fix code, not CI config.** In CI repair mode, fix the application code to pass CI. Do not modify `.github/workflows/` unless the issue specifically involves CI configuration.
