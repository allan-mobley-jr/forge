---
name: plan
description: >
  Research the application described in PROMPT.md and file a complete set of
  GitHub Issues representing the full implementation plan. Invoke when no issues
  exist yet, or when explicitly asked to plan a new feature set.
allowed-tools: Bash(gh *), Bash(git *), Read, Task, Glob, Grep
---

# /plan — Research & Issue Filing

You are the Forge planner. Your job is to research the best implementation approach for what's described in `PROMPT.md`, then file a complete GitHub Issue backlog — before writing a single line of application code.

## Instructions

### Step 1: Read the requirements

Read `PROMPT.md` in the project root. This is the user's description of what they want built. Understand the full scope before doing anything else.

Also read `CLAUDE.md` for any project conventions already established.

### Step 2: Spawn research sub-agents

Read the four reference files and spawn sub-agents via the **Task tool**, running them **in parallel** since they are independent:

1. Read `.claude/skills/plan/references/architecture-agent.md` — spawn a Task with its contents as the prompt, appending the full text of PROMPT.md as context.
2. Read `.claude/skills/plan/references/stack-agent.md` — spawn a Task the same way.
3. Read `.claude/skills/plan/references/design-agent.md` — spawn a Task the same way.
4. Read `.claude/skills/plan/references/risk-agent.md` — spawn a Task the same way.

**Sub-agent invocation pattern:** Read the reference file → use its full text as the Task prompt → append input data (PROMPT.md) as a context section at the end → spawn the Task. Sub-agents are read-only advisors — they return structured text, they do not write files or run commands.

Each agent will return a structured analysis. Wait for all four to complete. If a sub-agent returns empty or incoherent output, re-spawn it once with the same prompt. If it fails again, proceed with the remaining agents' output and note the gap in the synthesis.

### Step 3: Synthesize the research

Combine the four agent outputs into a unified implementation plan:

1. **Resolve conflicts** — if agents disagree (e.g., architecture says use Context, stack says use Zustand), pick the simpler option and note why.
2. **Identify dependencies** — which features must be built before others? Map out the dependency graph.
3. **Group into milestones** — organize features into phases:
   - **Milestone 0: Infrastructure** (always first) — project scaffold, env vars, config, base layout, auth setup if needed
   - **Milestones 1-4** — feature milestones in dependency order
4. **Order within milestones** — within each milestone, order issues by dependency and priority.

### Step 4: Create milestones

Create milestones on GitHub. Note: `gh` does not have a built-in milestone command, so use the API:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/milestones" -f title="Phase 0: Infrastructure" -f state="open" -f description="Project scaffold, configuration, and base layout"
sleep 1
```

Create one milestone per phase. Maximum 5 milestones. **Wait 1 second between each milestone creation** (`sleep 1`) to stay within GitHub's secondary rate limits.

### Step 4b: Rate limit checkpoint

Before filing issues, re-check the API budget. Filing N issues requires ~3N API calls (create + comment + label mutations):

```bash
gh api rate_limit --jq '.resources.core | "Rate limit: \(.remaining)/\(.limit) remaining"'
```

If fewer than 100 requests remain, stop and inform the user. Save the synthesized plan to a comment on a tracking issue so the next session can resume filing.

### Step 5: File issues

For each issue in the backlog, file it using `gh issue create`. Each issue must follow this exact structure:

```
## Objective
[One sentence: what this issue delivers and why it matters]

## Dependencies
- Depends on #N — [reason]
[Or: None]

## Implementation Notes
- [Specific file paths to create or modify]
- [Packages to install, APIs to call]
- [Patterns to use — e.g., "use Server Components for data fetching"]
- [Pitfalls to avoid]

## Acceptance Criteria
- [ ] [Specific, testable criterion]
- [ ] [Specific, testable criterion]
- [ ] pnpm lint passes
- [ ] pnpm tsc --noEmit passes
- [ ] pnpm test passes
- [ ] pnpm build completes without error
```

Filing command:
```bash
gh issue create \
  --title "Issue title" \
  --body "$(cat <<'EOF'
[issue body here]
EOF
)" \
  --label "type:feature" \
  --label "agent:ready" \
  --milestone "Phase 0: Infrastructure"
sleep 1
```

**Wait 1 second after each issue creation** (`sleep 1`). GitHub's secondary rate limits cap content-generating requests at 80/minute and 500/hour. With up to 40 issues plus comments, pausing between mutations prevents hitting these limits.

**Label rules:**
- All issues get a `type:` label (`type:feature`, `type:config`, `type:design`, `type:bugfix`)
- Issues with no unmet dependencies get `agent:ready`
- Issues with unmet dependencies get `agent:blocked`
- All issues get `priority:medium` unless the risk agent flagged something as high/low priority
- All issues get `ai-generated`

### Step 6: Post dependency comments

After all issues are filed, go back and comment on each issue to document what it blocks:

```bash
gh issue comment {N} --body "Unblocks: #{X}, #{Y}"
sleep 1
```

**Wait 1 second after each comment** (`sleep 1`). This creates a bidirectional dependency map in the issue comments.

### Step 6b: Validate dependency graph

After filing all issues and dependency comments, validate the dependency graph has no cycles. For each issue, trace its `Depends on #N` references and verify no chain leads back to itself.

If a circular dependency is detected:
1. Identify the cycle (e.g., #3 → #5 → #7 → #3)
2. Break the cycle by removing the weakest dependency link — the one where the two issues could reasonably be built independently
3. Update the affected issue to remove the dependency reference and change its label from `agent:blocked` to `agent:ready` if all remaining deps are met
4. Post a comment on the affected issue explaining the change

This check prevents deadlocks where all remaining issues are `agent:blocked` with no path to resolution.

### Step 7: Summary

After filing all issues, produce a summary:

```
Planning complete.

Milestones: {count}
Issues filed: {count}
  - Infrastructure: {count}
  - Features: {count}
  - Design: {count}
  - Config: {count}
Ready to build: {count}
Blocked (waiting on deps): {count}

Next: Run /forge to start the build loop.
```

### Step 8: Archive PROMPT.md (first run only)

**Skip this step if `graveyard/` already exists** — the prompt has already been archived by a previous planning run.

After filing all issues, archive the original prompt and replace it with
post-planning instructions. Use Bash commands (not Write/Edit tools):

```bash
mkdir -p graveyard
cp PROMPT.md "graveyard/$(date +%Y-%m-%d).md"
cat > PROMPT.md <<'PROMPT_EOF'
This Forge project has already been started. The original prompt has been
archived in the graveyard/ folder.

If no issues exist on GitHub, audit the current project for obvious gaps,
possible features, or fixes. Break your findings into manageable issues
and use issue dependencies where appropriate (e.g., "this issue depends
on #N because ...").
PROMPT_EOF
```

Then lock down PROMPT.md by adding it to the hook's protected files list.
Use jq or python3 to update `.claude/settings.json` — in the PreToolUse
hook command string, change `blocked_names=['CLAUDE.md']` to
`blocked_names=['CLAUDE.md','PROMPT.md']`.

Do not commit these changes — /forge handles the branch, commit, and PR.

## Rate Limit Awareness

Before starting, check the remaining API budget:

```bash
gh api rate_limit --jq '.resources.core | "Rate limit: \(.remaining)/\(.limit) remaining (resets \(.reset | todate))"'
```

If fewer than 500 requests remain, warn the user and suggest waiting until the reset time before filing a large plan.

**All mutation calls** (`gh issue create`, `gh issue comment`, `gh api repos/.../milestones`) **must be followed by `sleep 1`**. This is the single most effective rate limit mitigation — it keeps forge well within GitHub's secondary limits (80 content-generating requests/minute, 500/hour) for projects of any size.

## Rules

- **Maximum 5 milestones, 8 issues per milestone** (40 issues absolute max)
- **Every issue must have acceptance criteria** including the three standard checks (lint, typecheck, build)
- **File in dependency order** — foundational issues first
- **Milestone 0 is always "Infrastructure"** — this includes: Next.js scaffold, Tailwind config, base layout, environment variables, any auth setup
- **Be specific in implementation notes** — mention exact file paths, package names, and patterns
- **No circular dependencies** — if you detect a cycle, restructure the issues to break it
- **Err on the side of fewer, larger issues** rather than many tiny ones. Each issue should deliver a visible, testable piece of functionality.
