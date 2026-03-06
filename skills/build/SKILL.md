---
name: build
description: >
  Claim the next available GitHub Issue, implement it on a feature branch,
  and open a pull request. Used by the Forge orchestrator to drive the build
  loop. Invoke manually with /build to trigger a single work cycle.
allowed-tools: Bash(gh *), Bash(git *), Bash(pnpm *), Read, Write, Edit, MultiEdit, Glob, Grep, Task
---

# /build — Issue to Branch to PR

You are the Forge build agent. Your job is to claim one issue, implement it on a feature branch, and open a pull request. You handle exactly one issue per invocation — then return control to `/forge`.

## Build Cycle

### Step 1: Find the next issue

```bash
gh issue list --state open --label "agent:ready" --json number,title,body,labels --jq 'sort_by(.number) | .[0]'
```

If no issues are ready, report this and return to `/forge`.

### Step 2: Check for existing PR

Before starting work, check if a PR already exists for this issue (e.g., created manually or by a previous crashed session):

```bash
EXISTING_PR=$(gh pr list --state open --json number,headRefName,url \
  --jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE}-\"))] | .[0]")
```

If a PR already exists, skip this issue — it's already being handled. Report the existing PR and try the next ready issue.

### Step 2b: Verify dependencies

Read the issue body and find the "Dependencies" section. For each dependency `#N`:

```bash
gh issue view N --json state -q .state
```

If any dependency is still `OPEN`, skip this issue and try the next ready one. If no issues have met dependencies, report the situation and return to `/forge`.

### Step 3: Claim the issue

```bash
ISSUE={number}
gh issue edit $ISSUE --remove-label "agent:ready" --add-label "agent:in-progress"
sleep 1
echo $ISSUE > .forge-current-issue
```

### Step 3.5: Record build start time

```bash
BUILD_START=$(date +%s)
BUILD_TIMEOUT=1800  # 30 minutes per build
```

Before each subsequent major step (Steps 6, 6b, 6c, 7, and 8), check elapsed time:

```bash
ELAPSED=$(( $(date +%s) - BUILD_START ))
if [ "$ELAPSED" -ge "$BUILD_TIMEOUT" ]; then
  echo "Build timeout reached (${ELAPSED}s >= ${BUILD_TIMEOUT}s)"
  # Fall through to timeout handling below
fi
```

If the timeout is reached mid-build, commit work-in-progress and escalate:

```bash
git add <files modified so far>
git commit -m "wip: timeout after ${ELAPSED}s on issue #${ISSUE}" || true
git push -u origin HEAD 2>/dev/null || true
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:needs-human"
sleep 1
gh issue comment $ISSUE --body "$(cat <<TIMEOUT
## Build Timeout

This build exceeded the per-build timeout of ${BUILD_TIMEOUT}s (elapsed: ${ELAPSED}s).

Work-in-progress has been pushed to the branch if possible. A human should either:
1. Continue the build manually
2. Re-scope the issue into smaller pieces
3. Increase the timeout for complex issues
TIMEOUT
)"
sleep 1
```

Return to `/forge` so other ready issues can proceed.

### Step 4: Prepare the branch

```bash
git checkout main
git pull origin main
gh issue develop $ISSUE --name agent/issue-{N}-{slug} --checkout
```

This creates a branch linked to the issue in GitHub's "Development" sidebar. If `gh issue develop` fails (e.g., insufficient permissions or network error), fall back to local branch creation:

```bash
git checkout -b agent/issue-{N}-{slug}
```

Generate the slug from the issue title: lowercase, replace spaces and special characters with hyphens, remove consecutive hyphens, truncate to 40 characters. Example: `agent/issue-3-setup-tailwind-config`

### Step 5: Read the implementation brief

Read the full issue body carefully. Pay attention to:
- **Implementation Notes** — specific files to create/modify, packages to install, patterns to follow
- **Acceptance Criteria** — what must be true when you're done
- **Dependencies** — what's already been built (reference those PRs/issues for context)

Also read:
- `CLAUDE.md` — project conventions
- `PROMPT.md` — original requirements
- Existing source code — understand what's already built before adding to it

### Step 6: Implement

This is where you write code. Follow these principles:

1. **Read before writing.** Understand existing code before modifying it.
2. **Follow existing patterns.** Match the style, naming conventions, and architecture of what's already there.
3. **Install packages when needed.** `pnpm add {package}` for dependencies specified in the issue.
4. **Use the Task tool for complex research.** If you need to understand an API or library, spawn a research sub-agent rather than guessing.
5. **Work incrementally.** Make small, logical changes. Don't try to implement everything in one giant edit.
6. **Test as you go.** Run the dev server (`pnpm dev`) to verify changes work when practical.

### Step 6b: Review and test (sub-agents)

After implementation is complete, spawn two sub-agents **in parallel** via the Task tool:

1. **Review agent** — Read `.claude/skills/build/references/review-agent.md` and spawn a Task with its contents as the prompt. Append the issue body, the list of files changed (with contents), and the project's CLAUDE.md as context.

2. **Test agent** — Read `.claude/skills/build/references/test-agent.md` and spawn a Task the same way. Include the issue labels so it can determine whether to skip (e.g., `type:config`).

**Sub-agent invocation pattern:** Read the reference file → use its full text as the Task prompt → append input data as a context section at the end → spawn the Task. Both agents are read-only advisors — they return structured text output. They do not write files, run commands, or modify the project. You (the build agent) interpret their output and act on it.

### Step 6c: Apply review feedback and write tests

Process the sub-agent outputs:

1. **Review: must-fix items** — Apply each must-fix change. These are blocking. If the review agent returned "None," skip this step.
2. **Review: suggestions** — Save the suggestions list for the PR body. Do not apply them now.
3. **Test: test files** — Write each test file to disk at the path specified by the test agent. If the test agent returned "Skipped," no test files are needed.
4. **Run tests** — If test files were written:
   ```bash
   pnpm test
   ```
   If tests fail, read the output and fix the implementation (not the tests — the tests describe correct behavior). Re-run once.

### Step 7: Quality checks

Run all four checks:

```bash
pnpm lint
pnpm tsc --noEmit
pnpm test
pnpm build
```

**If all pass:** proceed to Step 8.

**If any fail:** spawn the **debug agent**. Read `.claude/skills/build/references/debug-agent.md` and spawn a Task with its contents as the prompt. Append the full error output, the list of files changed, and the issue body. The debug agent returns a prioritized list of fixes — apply them in order, then re-run all four checks. You get **2 total attempts** (the initial run + one retry after the debug agent's fixes).

### Step 7b: Rate limit checkpoint

Before pushing and creating a PR, verify the API budget is sufficient:

```bash
gh api rate_limit --jq '.resources.core | .remaining'
```

If fewer than 50 requests remain, commit locally but do not push or create the PR. Inform the user that the rate limit is nearly exhausted and the work is saved on the local branch. Return to `/forge` which will pause the loop.

### Step 8: On success — commit and open PR

```bash
# Stage only the files you created or modified for this issue.
# Do NOT use git add -A or git add . — this can stage unintended files.
git add <specific files>

# Commit with conventional commit format
git commit -m "feat: {issue title} (closes #{N})"

# Push the branch
git push -u origin agent/issue-{N}-{slug}
```

Open the pull request:

```bash
gh pr create \
  --title "feat: {issue title}" \
  --body "$(cat <<'EOF'
Closes #{N}

## Changes

[2-5 bullet points summarizing what was implemented]

## Acceptance Criteria

[Copy the acceptance criteria from the issue, checking off completed items]

## Tests

[Summary from test agent: number of test files, number of test cases, key scenarios covered.
Or: "Tests skipped — [reason from test agent]"]

## Review Notes

[List any non-blocking suggestions from the review agent here.
Or: "No additional suggestions."]

---

> Preview deploy will appear below. Check it before approving.
EOF
)" \
  --label "ai-generated"
```

Update the issue:

```bash
PR_URL=$(gh pr view --json url -q .url)
gh issue comment $ISSUE --body "PR opened: $PR_URL"
sleep 1
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:done"
sleep 1
```

### Step 9: On failure — escalate

If quality checks fail after 2 attempts (initial + debug-assisted retry):

```bash
# Capture the error
ERROR_OUTPUT="[paste the actual error output here]"

# Push what you have (so the human can see it)
git add -A
git commit -m "wip: {issue title} (needs help on #{N})"
git push -u origin agent/issue-{N}-{slug}

# Escalate
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:needs-human"
sleep 1
gh issue comment $ISSUE --body "$(cat <<'EOF'
## Build Failed

**Attempts:** 2/2

**Error:**
\`\`\`
{error output}
\`\`\`

**Debug agent diagnosis:**
[Summary of what the debug agent identified and what fixes were attempted]

**Branch:** `agent/issue-{N}-{slug}` (pushed with current state)
EOF
)"
sleep 1
```

### Step 10: Return to orchestrator

After completing (success or failure), end with:

**Now invoke `/forge` to determine the next action.**

## Rules

- **One issue per invocation.** Never batch multiple issues.
- **Always start from an up-to-date main.** Pull before branching.
- **Always push before opening a PR.** The branch must exist on the remote.
- **Commit message format:** `feat: {title} (closes #{N})` for features, `fix:` for bugfixes, `chore:` for config.
- **PR body must reference the issue** with `Closes #{N}`.
- **Write `.forge-current-issue`** so the Stop hook knows which issue to comment on.
- **Don't modify files outside the issue's scope.** Stay focused on what the issue asks for.
- **Don't skip quality checks.** Even if you're confident, always run lint + typecheck + test + build.
- **Don't skip sub-agents.** Always spawn review and test agents after implementation, even for small changes. The review agent catches issues the linter can't, and the test agent ensures coverage.
- **Respect the build timeout.** Check elapsed time before Steps 6, 6b, 6c, 7, and 8. If the 30-minute limit is reached, commit WIP and escalate rather than continuing.
