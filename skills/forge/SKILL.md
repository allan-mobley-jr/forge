---
name: forge
description: >
  Forge orchestrator. Auto-invoke at the start of every session in a Forge
  project. Reads GitHub state to determine what to do next: plan if no issues
  exist, build if issues are open and ready, sync if resuming after a pause.
  Always run this skill first in any Forge-managed repository.
allowed-tools: Bash(gh *), Bash(git *), Read, Glob
---

# /forge — Master Orchestrator

You are the Forge orchestrator. You are the entry point for every Forge session. Your job is to read the current project state and route to the appropriate sub-skill.

CLAUDE.md describes the full system architecture, state machine, and conventions. Refer to it for how skills and sub-agents relate. If you are resuming a session and the user has not explicitly asked you to do something else, run `/forge` immediately — do not ask "what would you like to do?" — the `/sync` output tells you.

## On Every Invocation

### Step 1: Verify this is a Forge project

Check that the current directory has the markers of a Forge project:

```bash
ls PROMPT.md CLAUDE.md .claude/skills/forge/SKILL.md 2>/dev/null
```

If any are missing, inform the user this doesn't appear to be a Forge project and suggest running `forge init`.

### Step 1.5: Verify authentication

Check that GitHub authentication is valid before making API calls:

```bash
gh auth status 2>&1
```

If `gh auth status` fails, inform the user to run `gh auth refresh` and stop — do not proceed with the build loop.

This check catches expired tokens early, preventing cascading 401 errors that the agent might misinterpret as rate limits or transient failures.

### Step 2: Check API budget

Before making any API calls, check the remaining rate limit:

```bash
gh api rate_limit --jq '.resources.core | "GitHub API: \(.remaining)/\(.limit) requests remaining (resets \(.reset | todate))"'
```

- If **remaining < 200**, warn the user that the API budget is low and suggest waiting until the reset time. Do not start a build loop.
- If **remaining < 500**, inform the user the budget is getting low — the session may need to pause before completing all issues.
- Otherwise, proceed normally.

**Secondary rate limits:** GitHub enforces undocumented secondary limits (approximately 80 content-generating requests/minute, 500/hour) that are **not** exposed by `gh api rate_limit`. These trigger 403 responses with error text mentioning "secondary rate limit." If any `gh` command fails with a 403 error during the session:

1. Check the error output for `secondary rate limit` text
2. **If not present**, treat as a standard 403 (auth/permissions) — surface the error immediately and do not retry
3. **If present**, wait 60 seconds before retrying:
   ```bash
   sleep 60
   ```
4. Retry the failed command once
5. If it fails again, pause the build loop and inform the user that secondary rate limits have been hit

All sub-skills (`/build`, `/revise`, `/plan`) should follow this same pattern: only sleep/retry on confirmed secondary rate limit 403s; surface all other 403s immediately.

### Step 3: Sync state

Run `/sync` to read the current GitHub state. This produces a structured summary of:
- Closed issues (completed work)
- In-progress issues (stale or resuming)
- Issues awaiting merge (agent:done)
- Issues with PRs needing revision (agent:done with CHANGES_REQUESTED)
- Issues needing human input
- Backlog issues (no agent label)

### Step 3.5: Write status file

After `/sync` produces its summary, ensure the temp directory exists and write the issue counts so the PreCompact and Stop hooks can read them. Use the counts from the sync output:

```bash
mkdir -p .forge-temp
cat > .forge-temp/status.json <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "issues": {
    "total": TOTAL,
    "closed": CLOSED,
    "in_progress": IN_PROGRESS,
    "needs_human": NEEDS_HUMAN,
    "done_awaiting_merge": AWAITING,
    "revision_needed": REVISION,
    "backlog": BACKLOG
  }
}
EOF
```

Replace TOTAL, CLOSED, etc. with the actual counts from the `/sync` summary. REVISION is the count of `agent:done` issues whose PR has `CHANGES_REQUESTED` (reported by `/sync` step 3d). AWAITING is `agent:done` issues NOT needing revision. Define TOTAL as the sum of all tracked issue states: TOTAL = CLOSED + IN_PROGRESS + NEEDS_HUMAN + AWAITING + REVISION. Do not include backlog issues — they are unclaimed and including them would break the Stop hook's completion check (`closed == total`). This file is read by the PreCompact hook (for context recovery after compaction) and the Stop hook (for exit status detection by the `forge run` loop). All temp files live in `.forge-temp/` which is git-ignored.

### Step 3.7: Clean up merged branches

After syncing, clean up local branches for issues that have been closed (merged PRs). This prevents stale branches from accumulating:

```bash
# Delete local agent branches whose remote counterpart is gone (merged and auto-deleted)
git remote prune origin 2>/dev/null || true
git branch --format='%(refname:short)' --list 'agent/*' | while read -r branch; do
  if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
    git branch -d "$branch" 2>/dev/null || true
  fi
done
```

This is non-blocking — failures are silently ignored. Do not delete branches that still have a remote counterpart.

### Step 4: Route based on state

Evaluate the sync output and take the appropriate action. Find the lowest-numbered open issue and check its state:

#### Case A: `agent:needs-human` on any issue
At least one issue is blocked on a human decision. Surface these immediately.

```
Action: Display each needs-human issue with its question
Message: "The following issues need your input before work can continue:"
  - For each: show issue number, title, and the agent question comment
  - Ask the user to respond on GitHub or provide their answer here
Wait: Do not proceed to building until the user addresses these or explicitly says to skip them
```

If the user provides an answer in the chat:
1. Post their answer as a comment on the issue
2. Remove `agent:needs-human` label
3. Continue to next applicable case

#### Case B: `agent:done` on the current issue
Check the PR review state:

**If `CHANGES_REQUESTED`:** Route to `/revise`.

```
Action: Run /revise
Message: "Issue #{X} has review feedback on its PR. Starting revision..."
```

**Otherwise (awaiting review or approved):** Block. The sequential lifecycle requires merge before moving on.

Look up the PR for the done issue using the `/sync` Open PRs data, or resolve it directly:

```bash
gh pr list --state open --json number,url,headRefName,reviewDecision \
  --jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE}-\"))] | .[0]"
```

```
Action: Stop the loop. Display the resolved PR URL and review status.
Message: "Issue #{X} has an open PR awaiting merge:
  PR #{P}: {url} — review: {reviewDecision}

  Merge or close the PR before the next issue can be built."
```

Write `.forge-temp/exit-status` as `needs-human` and return — do not proceed to build new issues.

```bash
echo "needs-human" > .forge-temp/exit-status
```

#### Case C: `agent:in-progress` on an issue (crash recovery)
Check for an existing branch or PR:

```bash
REMOTE_BRANCH=$(git branch -r --list "origin/agent/issue-${ISSUE}-*" | head -1 | tr -d ' ')
```

If a branch exists, check whether the issue has an open PR with `CHANGES_REQUESTED` before routing. This handles the case where a `/revise` session crashed mid-revision:

```bash
PR_REVIEW=$(gh pr list --state open --json headRefName,reviewDecision \
  --jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE}-\")) | select(.reviewDecision == \"CHANGES_REQUESTED\")] | length")
```

- If `PR_REVIEW > 0`: route to `/revise` (the crash happened during a revision cycle)

```
Action: Run /revise
Message: "Issue #{X} was interrupted mid-revision. Resuming revision..."
```

- Otherwise: route to `/build` which will detect and resume from the existing branch.

```
Action: Run /build
Message: "Issue #{X} was interrupted mid-build. Resuming from existing branch..."
```

If no branch exists, the label is stale — `/sync` should have already cleaned it up, but if not, remove the label and continue to Case D.

#### Case D: No `agent:*` label on the next issue (backlog)
Issues are ready to be built. Pick the lowest-numbered open issue without an `agent:*` label.

```
Action: Run /build
Message: "Found {N} backlog issues. Starting with Issue #{X} — {title}"
```

#### Case E: No open issues
All filed issues have been closed. Re-invoke `/plan` — it will detect `graveyard/` and enter audit mode, comparing the original requirements against what was built and filing new issues for any gaps.

```
Action: Run /plan
Message: "All issues are closed. Running /plan to check for gaps..."
```

After `/plan` returns, check whether new agent workflow issues were created. Use `ai-generated` to match only issues filed by `/plan`, and `--limit` to avoid pagination:

```bash
gh issue list --state open --label "ai-generated" --limit 1000 --json number --jq 'length'
```

- **If new issues exist:** Continue the loop — re-invoke `/forge` to process them.
- **If no new issues:** The project is complete. Close any milestones that have no remaining open issues, then announce completion.

   ```bash
   REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   gh api "repos/$REPO/milestones" --jq '.[] | select(.open_issues == 0) | .number' | while read num; do
     gh api "repos/$REPO/milestones/$num" -X PATCH -f state="closed"
   done
   ```

   ```
   Action: Announce completion
   Message: "All issues are closed and no gaps found. The project plan is fully implemented."
   ```

   ```bash
   echo "complete" > .forge-temp/exit-status
   ```

### Step 5: Loop

After `/build` completes one issue (success or failure), **immediately re-invoke `/forge`** — do NOT wait for user input. This creates the autonomous build loop:

```
/forge → /sync → /build (issue #3) → /forge → /sync → /build (issue #4) → ...
```

The loop continues until:
- All issues are closed (Case E)
- An issue needs human input (Case A)
- A PR is awaiting merge (Case B)
- The user interrupts (Ctrl+C)

If `/build` returns without completing (no PR opened, no escalation posted), check the terminal output for infrastructure errors:
- `gh` authentication failures → inform the user to run `gh auth refresh`
- Network errors → inform the user and pause the loop
- Disk space errors → inform the user

Do not retry infrastructure errors automatically. Surface them and wait for the user.

### Step 6: Housekeeping PR after /plan

If `/plan` just ran **and** this is the first planning run, create a housekeeping PR for the PROMPT.md archive. Detect first run by checking whether `graveyard/` has uncommitted files (i.e., `/plan` just created it):

```bash
git status --porcelain graveyard/ | grep -q . && echo "first-run"
```

If `graveyard/` is already committed from a previous session, skip this step.

```bash
git checkout -b forge/archive-prompt
git add graveyard/ PROMPT.md SPECIFICATION.md .claude/settings.json
git commit -m "Archive original prompt after planning phase"
git push -u origin forge/archive-prompt
gh pr create --title "Archive original prompt" \
  --body "Housekeeping: archives PROMPT.md to graveyard/, generates SPECIFICATION.md, and locks both down after initial planning."
git checkout main
```

Do not wait for this PR to merge — continue to `/clear` and the build loop.
The archive PR is independent of feature work.

### Step 7: Context management

After `/plan` completes, run `/clear` before starting the build loop — `/sync` will re-establish all necessary context from GitHub.

**Between build cycles:** After each `/build` completes, increment a persistent build counter and check if it's time to clear context:

```bash
COUNT=$(cat .forge-temp/build-count 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > .forge-temp/build-count

if [ "$COUNT" -ge 3 ]; then
  echo "0" > .forge-temp/build-count
  # Run /clear before the next /forge invocation
fi
```

After every **3 completed builds**, run `/clear` before re-invoking `/forge`. This prevents context exhaustion during long sessions with many issues. The counter persists in `.forge-temp/build-count` so it survives context clearing. `/sync` will re-establish all necessary state from GitHub after clearing.

**Pre-emptive status file:** Write `.forge-temp/exit-status` as `needs-restart` at the start of every `/forge` invocation (before `/sync`). Update it to `complete` or `needs-human` only after `/sync` confirms the appropriate state. This ensures a valid exit status exists even if the session terminates abruptly due to context exhaustion:

```bash
mkdir -p .forge-temp
echo "needs-restart" > .forge-temp/exit-status
```

**If context compaction occurs** (PreCompact hook fires), the next action after compaction should be to re-run `/forge` — the PreCompact hook already prints recovery instructions. Do not attempt to continue a partially-completed `/build` after compaction; instead, let `/sync` detect the in-progress issue and handle it.

## Rules

- **Always sync first.** Never assume state — read it from GitHub.
- **Surface blockers immediately.** `agent:needs-human` issues take priority over everything.
- **Loop automatically.** Don't ask "should I continue?" — just keep building until something blocks you.
- **Be observable.** Print clear status messages so the human can follow along in the terminal.
- **Don't modify code directly.** The orchestrator routes to sub-skills. It doesn't write application code itself.
- **Handle 403 errors carefully.** Only treat a 403 as secondary rate limiting (sleep 60s + retry once) when the error output mentions `secondary rate limit`. All other 403s are auth/permission errors — surface them immediately instead of retrying.
- **Guard against context exhaustion.** Write `.forge-temp/exit-status` as `needs-restart` at the start of each invocation. Run `/clear` after every 3 builds. After compaction, re-run `/forge` to resync state and continue.
