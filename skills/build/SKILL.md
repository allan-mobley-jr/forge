---
name: build
description: >
  Claim the next available GitHub Issue, implement it on a feature branch,
  and open a pull request. Used by the Forge orchestrator to drive the build
  loop. Invoke manually with /build to trigger a single work cycle.
allowed-tools: Bash(gh *), Bash(git *), Bash(pnpm *), Read, Write, Edit, MultiEdit, Glob, Grep, Task, WebSearch, WebFetch
---

# /build — Issue to Branch to PR

You are the Forge build agent. Your job is to claim one issue, implement it on a feature branch, and open a pull request. You handle exactly one issue per invocation — then return control to `/forge`.

## Build Cycle

### Step 1: Find the next issue

Find the lowest-numbered open issue with no `agent:*` label (i.e., unclaimed backlog):

```bash
ISSUE_JSON=$(gh issue list --state open --json number,title,body,labels -L 200 \
  --jq '[.[] | select(.labels | map(.name) | map(select(startswith("agent:"))) | length == 0)] | sort_by(.number) | .[0]')
```

If no issues are available, report this and return to `/forge`.

Extract the issue number and title:

```bash
ISSUE=$(echo "$ISSUE_JSON" | jq -r '.number')
TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
```

### Step 2: Check for existing PR

Before starting work, check if a PR already exists for this issue (e.g., created manually or by a previous crashed session):

```bash
EXISTING_PR=$(gh pr list --state open --json number,headRefName,url \
  --jq "[.[] | select(.headRefName | startswith(\"agent/issue-${ISSUE}-\"))] | .[0]")
```

If a PR already exists, skip this issue — it's already being handled. Report the existing PR and return to `/forge`.

### Step 3: Claim the issue

```bash
gh issue edit $ISSUE --add-label "agent:in-progress"
mkdir -p .forge-temp
echo $ISSUE > .forge-temp/current-issue
```

### Step 3.5: Record build start time

```bash
BUILD_START=$(date +%s)
BUILD_TIMEOUT=1800  # 30 minutes per build
PRE_IMPL_TIMEOUT=600  # 10 minutes for pre-implementation steps (3a-3d)
```

Before each subsequent major step (Steps 6, 6b, 6c, 7, and 8), check elapsed time:

```bash
ELAPSED=$(( $(date +%s) - BUILD_START ))
if [ "$ELAPSED" -ge "$BUILD_TIMEOUT" ]; then
  echo "Build timeout reached (${ELAPSED}s >= ${BUILD_TIMEOUT}s)"
  # Fall through to timeout handling below
fi
```

If the timeout is reached mid-build, commit work-in-progress and push the branch. Keep `agent:in-progress` so the next session can resume:

```bash
git add <files modified so far>
git commit -m "wip: timeout after ${ELAPSED}s on issue #${ISSUE}" || true
git push -u origin HEAD 2>/dev/null || true
gh issue comment $ISSUE --body "$(cat <<TIMEOUT
## Build Timeout

This build exceeded the per-build timeout of ${BUILD_TIMEOUT}s (elapsed: ${ELAPSED}s).

Work-in-progress has been pushed to the branch. The next session will resume from the existing branch.

If the issue is too large, a human should:
1. Continue the build manually
2. Re-scope the issue into smaller pieces
3. Increase the timeout for complex issues
TIMEOUT
)"
```

Return to `/forge` so the next session can resume from the WIP branch.

### Step 3a: Triage (human-filed issues only)

Skip this step if the issue has the `ai-generated` label — agent-filed issues were already vetted by `/plan`.

For human-filed issues, spawn a **triage agent** via the Task tool. Read `.claude/skills/build/references/triage-agent.md` and spawn a Task with its contents as the prompt. Append the issue body, the project's SPECIFICATION.md, a list of open issues (titles and numbers), and the project's CLAUDE.md as context.

Handle the triage verdict:

| Verdict | Action |
|---------|--------|
| PROCEED | Wait for research agent (already running in parallel), then continue to Step 3c |
| NEEDS_CLARIFICATION | Escalate via `/ask` with the triage agent's questions. Remove `agent:in-progress`. Discard research output. Return to `/forge`. |
| TOO_BROAD | File decomposed sub-issues (with `--label "ai-generated"`). Close the original issue with a comment linking to the sub-issues. Remove `agent:in-progress`. Discard research output. Return to `/forge`. |
| REJECT | Add `agent:needs-human` label. Post a comment with the rejection rationale. Discard research output. Return to `/forge`. |

### Step 3b: Research (all issues)

Before each pre-implementation step, check the pre-implementation timeout:

```bash
PRE_ELAPSED=$(( $(date +%s) - BUILD_START ))
if [ "$PRE_ELAPSED" -ge "$PRE_IMPL_TIMEOUT" ]; then
  echo "Pre-implementation timeout (${PRE_ELAPSED}s >= ${PRE_IMPL_TIMEOUT}s) — skipping to implementation"
  # Skip remaining pre-implementation steps, proceed to Step 4
fi
```

Spawn a **research agent** via the Task tool. Read `.claude/skills/build/references/research-agent.md` and spawn a Task with its contents as the prompt. Append the issue body, the project's SPECIFICATION.md, and the project's CLAUDE.md as context.

**Parallelism with triage:** For human-filed issues, spawn the research agent at the same time as the triage agent in Step 3a — do not wait for triage to complete before starting research. Both agents have independent inputs. After both return, evaluate the triage verdict (Step 3a table) before proceeding. For agent-filed issues, the research agent runs immediately after Step 3.5 (triage is skipped).

The research agent explores the codebase for relevant files, patterns, and dependencies. When the issue involves domain-specific knowledge (API integrations, accessibility standards, payment processing, etc.), it also searches the web for authoritative sources.

### Step 3c: Plan (all issues)

Check the pre-implementation timeout. If exceeded, skip to Step 4.

Sequential after research — depends on the research agent's output.

Spawn a **plan agent** via the Task tool. Read `.claude/skills/build/references/plan-agent.md` and spawn a Task with its contents as the prompt. Append the issue body, the research agent's report, the project's SPECIFICATION.md, and the project's CLAUDE.md as context.

The plan agent returns an ordered change list, design decisions, risk assessment, complexity rating, and single-PR feasibility evaluation.

### Step 3d: Devil's Advocate (all issues)

Check the pre-implementation timeout. If exceeded, skip to Step 4.

Sequential after plan — depends on the plan agent's output.

Spawn an **advocate agent** via the Task tool. Read `.claude/skills/build/references/advocate-agent.md` and spawn a Task with its contents as the prompt. Append the issue body, the research agent's report, the plan agent's plan, the project's SPECIFICATION.md, and the project's CLAUDE.md as context.

Handle the advocate verdict:

| Verdict | Action |
|---------|--------|
| PROCEED | Continue to Step 4 with the plan agent's output as the implementation guide |
| REVISE_PLAN | Re-spawn the plan agent once with the advocate's feedback appended. Proceed with the revised plan — no second advocate review. |
| ESCALATE | Escalate via `/ask` with the advocate's concerns. Remove `agent:in-progress`. Return to `/forge`. |

### Step 4: Prepare the branch

First, fetch and check for an existing WIP branch from a previous timeout or crash:

```bash
git fetch origin --prune 2>/dev/null || true
EXISTING_BRANCH=$(git branch -r --list "origin/agent/issue-${ISSUE}-*" | head -1 | tr -d ' ')
```

If an existing branch is found, check it out and resume:

```bash
if [ -n "$EXISTING_BRANCH" ]; then
  BRANCH_NAME=${EXISTING_BRANCH#origin/}
  git checkout main && git pull origin main
  git checkout -b "$BRANCH_NAME" "$EXISTING_BRANCH" 2>/dev/null || git checkout "$BRANCH_NAME"
  git pull origin "$BRANCH_NAME"
  git merge origin/main --no-edit
else
  git checkout main
  git pull origin main
  gh issue develop $ISSUE --name agent/issue-{N}-{slug} --checkout
fi
```

If `gh issue develop` fails (e.g., insufficient permissions or network error), fall back to local branch creation:

```bash
git checkout -b agent/issue-{N}-{slug}
```

Generate the slug from the issue title: lowercase, replace spaces and special characters with hyphens, remove consecutive hyphens, truncate to 40 characters. Example: `agent/issue-3-setup-tailwind-config`

### Step 5: Read the implementation brief

Read the full issue body carefully. Pay attention to:
- **Implementation Notes** — specific files to create/modify, packages to install, patterns to follow
- **Acceptance Criteria** — what must be true when you're done
- **Dependencies** — what's already been built (reference those PRs/issues for context)

If the plan agent produced output (Steps 3b-3d completed), use it as the primary implementation guide. The plan agent's change list, design decisions, and risk areas should inform your approach. The issue body's Implementation Notes remain authoritative for what to build — the plan refines how to build it.

If resuming from a WIP branch (Step 4 found an existing branch), also read the most recent "Build Timeout" comment on the issue for context on what was already done.

Also read:
- `CLAUDE.md` — project conventions
- `SPECIFICATION.md` — architectural decisions, stack rationale, design system, and constraints (prefer this over PROMPT.md for understanding WHY things are built a certain way)
- `PROMPT.md` — original requirements (pre-planning) or audit instructions (post-planning)
- Existing source code — understand what's already built before adding to it

### Step 6: Implement

This is where you write code. Follow these principles:

1. **Read before writing.** Understand existing code before modifying it.
2. **Follow existing patterns.** Match the style, naming conventions, and architecture of what's already there.
3. **Install packages when needed.** `pnpm add {package}` for dependencies specified in the issue.
4. **Use the Task tool for complex research.** If you need to understand an API or library, spawn a research sub-agent rather than guessing.
5. **Work incrementally.** Make small, logical changes. Don't try to implement everything in one giant edit.
6. **Test as you go.** Run the dev server (`pnpm dev`) to verify changes work when practical.
7. **File new issues for out-of-scope discoveries.** If you find bugs, missing error handling, or improvement opportunities outside the current issue's scope, file a new issue (with `--label "ai-generated"`) for each one rather than fixing it inline. Stay focused on the current issue.

### Step 6a: Preview deployment (when available)

If `.vercel/project.json` exists, attempt a preview deployment:

```bash
PREVIEW_URL=$(vercel deploy 2>/dev/null | tail -1)
```

If deployment succeeds, save the preview URL for inclusion in the PR body.
If it fails, note the failure but do not block — local quality checks are the gate.

### Step 6b: Review, test, and visual check (sub-agents)

After implementation is complete, spawn sub-agents **in parallel** via the Task tool:

1. **Review agent** — Read `.claude/skills/build/references/review-agent.md` and spawn a Task with its contents as the prompt. Append the issue body, the list of files changed (with contents), and the project's CLAUDE.md as context.

2. **Test agent** — Read `.claude/skills/build/references/test-agent.md` and spawn a Task the same way. Include the issue body so it can determine whether to skip.

3. **Visual check agent** (conditional) — Only spawn if ALL of these are true:
   - The issue delivers visible UI changes (not API routes, config, or utilities)
   - The `agent-browser` vendor skill is available (check `.claude/skills/` for its directory)

   If spawning, the visual check agent should:
   - Start the dev server (`pnpm dev`)
   - Navigate to affected pages (from the issue's implementation notes)
   - Take screenshots at 1280x720 (desktop) and 375x812 (mobile)
   - Compare against baselines in `.forge-temp/screenshots/` if they exist
   - Return a structured report of visual differences

   Prompt the agent with: "You are a visual QA agent. Start the dev server, navigate to the specified pages, take screenshots at desktop (1280x720) and mobile (375x812) viewports, compare against any existing baselines in .forge-temp/screenshots/, and report visual differences."

**Sub-agent invocation pattern:** Read the reference file → use its full text as the Task prompt → append input data as a context section at the end → spawn the Task. The review and test agents are read-only advisors — they return structured text output and do not write files or run commands. The visual check agent is an exception: it runs commands (dev server, browser) to capture screenshots, but does not modify source code. You (the build agent) interpret all sub-agent output and act on it.

### Step 6c: Apply review feedback, write tests, and process visual output

Process the sub-agent outputs:

1. **Review: must-fix items** — Apply each must-fix change. These are blocking. If the review agent returned "None," skip this step.
2. **Review: suggestions** — Save the suggestions list for the PR body. Do not apply them now.
3. **Test: test files** — Write each test file to disk at the path specified by the test agent. If the test agent returned "Skipped," no test files are needed.
4. **Visual: regression check** — If the visual check agent was spawned, evaluate its output:
   - **Intentional changes** — expected visual differences from the implemented feature. Update baselines by saving new screenshots to `.forge-temp/screenshots/`.
   - **Unintentional regressions** — unexpected visual differences. Fix the implementation to resolve them.
   - Save the visual check summary for the PR body.
5. **Run tests** — If test files were written:
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

**Atomic commits:** Split your work into one commit per logical change. Each commit should be describable in a single short sentence without "and." For example, if you added a component, installed a package, and updated a config file for unrelated reasons, that's three commits.

```bash
# Stage only the files for one logical change at a time.
# Do NOT use git add -A or git add . — this can stage unintended files.
git add <files for change 1>
git commit -m "feat: add hero section component"

git add <files for change 2>
git commit -m "chore: install framer-motion"

# Only the FINAL commit gets (closes #{N}). Use the appropriate type: feat/fix/chore.
git add <remaining files>
git commit -m "{type}: {issue title} (closes #{N})"

# Push the branch
git push -u origin agent/issue-{N}-{slug}
```

Open the pull request:

```bash
gh pr create \
  --title "feat: {issue title}" \
  --body "$(cat <<'EOF'
Closes #{N}

> This PR implements Issue #{N} and will close it automatically when merged.

## Changes

[2-5 bullet points summarizing what was implemented]

## Plan Summary

[If pre-implementation planning completed (Steps 3b-3d):
- Key design decisions from the plan agent
- Advocate warnings that were accepted or addressed
Or: "Pre-implementation planning skipped (timeout / resumed from WIP branch)."]

## Acceptance Criteria

[Copy the acceptance criteria from the issue, checking off completed items]

## Tests

[Summary from test agent: number of test files, number of test cases, key scenarios covered.
Or: "Tests skipped — [reason from test agent]"]

## Visual Check

[Summary from visual check agent: pages checked, viewports, any regressions found.
Or: "Visual check skipped — non-UI issue." or "Visual check skipped — agent-browser not available."]

## Preview

[Preview URL from Step 6a, if deployment succeeded.
Or: "Preview deployment skipped — no Vercel project linked." or "Preview deployment failed — check local build."]

## Review Notes

[List any non-blocking suggestions from the review agent here.
Or: "No additional suggestions."]
EOF
)"
```

Update the issue:

```bash
PR_URL=$(gh pr view --json url -q .url)
gh issue comment $ISSUE --body "PR opened: $PR_URL"
gh issue edit $ISSUE --remove-label "agent:in-progress" --add-label "agent:done"
```

### Step 9: On failure — escalate

If quality checks fail after 2 attempts (initial + debug-assisted retry):

```bash
# Capture the error
ERROR_OUTPUT="[paste the actual error output here]"

# Push what you have (so the human can see it)
# Stage only tracked/modified files — never use git add -A
git add <files modified so far>
git commit -m "wip: {issue title} (needs help on #{N})"
git push -u origin agent/issue-{N}-{slug}
```

Invoke `/ask` with type `build-failure`, passing:
- `ERROR_OUTPUT` — the quality check error output
- `DEBUG_DIAGNOSIS` — summary of what the debug agent identified and what fixes were attempted
- `BRANCH_NAME` — `agent/issue-{N}-{slug}`

`/ask` handles the comment format and label management (`agent:in-progress` → `agent:needs-human`).

### Step 10: Return to orchestrator

After completing (success or failure), end with:

**Now invoke `/forge` to determine the next action.**

## Rules

- **One issue per invocation.** Never batch multiple issues.
- **Always start from an up-to-date main.** Pull before branching.
- **Always push before opening a PR.** The branch must exist on the remote.
- **Commit message format:** `feat:` for features, `fix:` for bugfixes, `chore:` for config. Only the final commit includes `(closes #{N})`. Split commits by logical change — one concern per commit.
- **PR body must reference the issue** with `Closes #{N}`.
- **Write `.forge-temp/current-issue`** so the Stop hook knows which issue to comment on.
- **Don't modify files outside the issue's scope.** Stay focused on what the issue asks for. If you discover something worth fixing, file a new issue (with `--label "ai-generated"`).
- **Don't skip quality checks.** Even if you're confident, always run lint + typecheck + test + build.
- **Don't skip sub-agents.** Always spawn review and test agents after implementation, even for small changes. The review agent catches issues the linter can't, and the test agent ensures coverage.
- **Respect the build timeout.** Check elapsed time before Steps 6, 6b, 6c, 7, and 8. If the 30-minute limit is reached, commit WIP and push — the next session resumes from the branch.
- **Respect the pre-implementation timeout.** Steps 3a-3d share a 10-minute budget. If exceeded, skip remaining pre-implementation steps and proceed directly to Step 4. Better to build with partial research than to spend the entire budget on planning.
- **Triage is for human issues only.** Don't triage issues with the `ai-generated` label — they were already vetted by `/plan`.
- **Research runs in parallel with triage.** For human-filed issues, spawn both the triage and research agents simultaneously since they have independent inputs.
