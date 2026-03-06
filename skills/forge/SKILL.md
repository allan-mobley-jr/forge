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
- In-progress issues
- Ready-to-build issues
- Revision-needed issues (PRs with review feedback)
- Blocked issues
- Issues needing human input
- Open PRs

### Step 3.5: Write status file

After `/sync` produces its summary, write the issue counts to `.forge-status.json` so the PreCompact and Stop hooks can read them. Use the counts from the sync output:

```bash
cat > .forge-status.json <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "issues": {
    "total": TOTAL,
    "closed": CLOSED,
    "ready": READY,
    "in_progress": IN_PROGRESS,
    "blocked": BLOCKED,
    "needs_human": NEEDS_HUMAN,
    "revision_needed": REVISION,
    "done_awaiting_merge": AWAITING
  }
}
EOF
```

Replace TOTAL, CLOSED, READY, etc. with the actual counts from the `/sync` summary. Define TOTAL as the sum of labeled issue buckets only: TOTAL = CLOSED + READY + IN_PROGRESS + BLOCKED + NEEDS_HUMAN + REVISION + AWAITING. Do not include unlabeled or triage issues — they are outside the agent workflow and including them would break the Stop hook's completion check (`closed == total`). This file is read by the PreCompact hook (for context recovery after compaction) and the Stop hook (for exit status detection by the `forge run` loop).

### Step 3.7: Clean up merged branches

After syncing, clean up local branches for issues that have been closed (merged PRs). This prevents stale branches from accumulating:

```bash
# Delete local agent branches whose remote counterpart is gone (merged and auto-deleted)
git remote prune origin
git branch --list 'agent/*' | while read branch; do
  if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
    git branch -d "$branch" 2>/dev/null || true
  fi
done
```

This is non-blocking — failures are silently ignored. Do not delete branches that still have a remote counterpart.

### Step 4: Route based on state

Evaluate the sync output and take the appropriate action:

#### Case A: Zero issues exist
The project has no issues filed yet. This means planning hasn't happened.

```
Action: Run /plan
Message: "No issues found. Starting the planning phase..."
```

#### Case B: Issues exist with `agent:needs-human` label
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
2. Remove `agent:needs-human` label, add `agent:ready`
3. Continue to Case C

#### Case B2: Unlabeled issues exist (non-blocking)
The sync summary shows issues in the "Unlabeled" row — open issues with no `agent:*` or `triage` label.

```
Action: Surface them to the user, then continue to Case C/D/E
Message: "These issues are not in the agent workflow: #X, #Y.
  Add the `triage` label to include them, or close them if they're not needed."
```

Do not block on this — inform the user and proceed to the next applicable case.

#### Case B3: Issues with `agent:revision-needed` label
A PR has review comments that need to be addressed. This takes priority over building new issues because revising existing work gets PRs closer to merge.

```
Action: Run /revise
Message: "Found {N} issues needing PR revision. Starting with Issue #{X} — {title}"
```

#### Case B4: Issues with `agent:done` label (PR awaiting merge)
An issue has an open PR that hasn't been merged yet. The sequential lifecycle requires merge before moving on.

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

Write `.forge-exit-status` as `needs-human` and return — do not proceed to build new issues.

```bash
echo "needs-human" > .forge-exit-status
```

#### Case C: Open issues with `agent:ready` label
Issues are ready to be built.

```
Action: Run /build
Message: "Found {N} issues ready to build. Starting with Issue #{X} — {title}"
```

#### Case D: Open issues but none are `agent:ready`
All remaining issues are either blocked or in-progress. Check why:

- If issues are `agent:blocked`: Check if their dependencies have been met since last sync. If so, relabel them `agent:ready` and proceed to Case C.
- If issues are `agent:in-progress`: A previous session may have been interrupted. Check if there's an open PR for the issue:
  ```bash
  gh pr list --state open --json number,headRefName --jq '.[] | select(.headRefName | startswith("agent/issue-{N}-"))'
  ```
  If a PR exists, inform the user. If no PR or branch exists, relabel as `agent:ready` and proceed.
- If it's a genuine deadlock (circular dependencies or all blocked on unresolved issues): Alert the user and suggest reordering.

```
Message: "All {N} remaining issues are blocked. Here's the dependency situation: ..."
```

#### Case E: All issues are closed
The project is complete (or this phase of it is). Before announcing, check for audit instructions.

1. Read the archived original prompt in `graveyard/` (the original `PROMPT.md` is archived there by `/plan`) and check for audit instructions (e.g., a section describing what to verify after all issues are implemented, gaps to check for, or standards to validate against). Also review the closed issues to understand what was built.

2. **If audit instructions are present:** Follow them — review the codebase against the original requirements, file `triage`-labeled issues for any gaps or missing functionality discovered, then re-invoke `/forge` to process them.

   ```bash
   gh issue create --title "{gap title}" --label "triage" --body-file - <<'EOF'
   {description}
   EOF
   ```

3. **If no audit instructions are present** (or audit is complete with no gaps found): Announce completion and write the exit status.

   ```
   Action: Announce completion
   Message: "All {N} issues are closed. The project plan is fully implemented."
   ```

   ```bash
   echo "complete" > .forge-exit-status
   ```

### Step 5: Loop

After `/build` completes one issue (success or failure), **immediately re-invoke `/forge`** — do NOT wait for user input. This creates the autonomous build loop:

```
/forge → /sync → /build (issue #3) → /forge → /sync → /build (issue #4) → ...
```

The loop continues until:
- All issues are closed (Case E)
- An issue needs human input (Case B)
- A PR is awaiting merge (Case B4)
- A deadlock is detected (Case D)
- The user interrupts (Ctrl+C)

If `/build` returns without completing (no PR opened, no escalation posted), check the terminal output for infrastructure errors:
- `gh` authentication failures → inform the user to run `gh auth refresh`
- Network errors → inform the user and pause the loop
- Disk space errors → inform the user

Do not retry infrastructure errors automatically. Surface them and wait for the user.

### Step 6: Housekeeping PR after /plan

If `/plan` just ran, create a housekeeping PR for the PROMPT.md archive:

```bash
git checkout -b forge/archive-prompt
git add graveyard/ PROMPT.md .claude/settings.json
git commit -m "Archive original prompt after planning phase"
git push -u origin forge/archive-prompt
gh pr create --title "Archive original prompt" \
  --body "Housekeeping: archives PROMPT.md to graveyard/ and locks it down after initial planning."
git checkout main
```

Do not wait for this PR to merge — continue to `/clear` and the build loop.
The archive PR is independent of feature work.

### Step 7: Context management

After `/plan` completes, run `/clear` before starting the build loop — `/sync` will re-establish all necessary context from GitHub.

**Between build cycles:** After each `/build` completes, increment a persistent build counter and check if it's time to clear context. Note: `.forge-build-count` must be in the repository's `.gitignore` to prevent accidental commits.

```bash
COUNT=$(cat .forge-build-count 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > .forge-build-count

if [ "$COUNT" -ge 3 ]; then
  echo "0" > .forge-build-count
  # Run /clear before the next /forge invocation
fi
```

After every **3 completed builds**, run `/clear` before re-invoking `/forge`. This prevents context exhaustion during long sessions with many issues. The counter persists in `.forge-build-count` so it survives context clearing. `/sync` will re-establish all necessary state from GitHub after clearing.

**Pre-emptive status file:** Write `.forge-exit-status` as `needs-restart` at the start of every `/forge` invocation (before `/sync`). Update it to `complete` or `needs-human` only after `/sync` confirms the appropriate state. This ensures a valid exit status exists even if the session terminates abruptly due to context exhaustion:

```bash
echo "needs-restart" > .forge-exit-status
```

**If context compaction occurs** (PreCompact hook fires), the next action after compaction should be to re-run `/forge` — the PreCompact hook already prints recovery instructions. Do not attempt to continue a partially-completed `/build` after compaction; instead, let `/sync` detect the in-progress issue and handle it.

## Rules

- **Always sync first.** Never assume state — read it from GitHub.
- **Surface blockers immediately.** `agent:needs-human` issues take priority over everything.
- **Loop automatically.** Don't ask "should I continue?" — just keep building until something blocks you.
- **Be observable.** Print clear status messages so the human can follow along in the terminal.
- **Don't modify code directly.** The orchestrator routes to sub-skills. It doesn't write application code itself.
- **Handle 403 errors carefully.** Only treat a 403 as secondary rate limiting (sleep 60s + retry once) when the error output mentions `secondary rate limit`. All other 403s are auth/permission errors — surface them immediately instead of retrying.
- **Guard against context exhaustion.** Write `.forge-exit-status` as `needs-restart` at the start of each invocation. Run `/clear` after every 3 builds. After compaction, re-run `/forge` to resync state and continue.
