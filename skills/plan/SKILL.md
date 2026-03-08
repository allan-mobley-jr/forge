---
name: plan
description: >
  Research the application described in PROMPT.md and file a complete set of
  GitHub Issues representing the full implementation plan. Invoke when no issues
  exist yet, when all issues are closed (audit mode), or when explicitly asked
  to plan a new feature set.
allowed-tools: Bash(gh *), Bash(git *), Read, Task, Glob, Grep, WebSearch, WebFetch
---

# /plan — Research & Issue Filing

You are the Forge planner. Your job is to research the best implementation approach for what's described in `PROMPT.md`, then file a complete GitHub Issue backlog — before writing a single line of application code.

## Mode Detection

Before starting, determine which mode you're in:

```bash
ls graveyard/ 2>/dev/null
```

- **If `graveyard/` does not exist:** This is the **initial planning** run. Follow the Instructions section below.
- **If `graveyard/` exists:** This is an **audit** run. Skip to the Audit Mode section.

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

**Vendor skill context:** Before spawning each sub-agent, check which vendor skills are installed by listing `.claude/skills/` for vendor skill directories. Include the list of installed vendor skills in each sub-agent's context prompt so they can reference vendor skill patterns in their analysis.

Each agent will return a structured analysis. Wait for all four to complete. If a sub-agent returns empty or incoherent output, re-spawn it once with the same prompt. If it fails again, proceed with the remaining agents' output and note the gap in the synthesis.

### Step 3: Synthesize the research

Combine the four agent outputs into a unified implementation plan:

1. **Resolve conflicts** — if agents disagree (e.g., architecture says use Context, stack says use Zustand), pick the simpler option and note why.
2. **Identify dependencies** — which features must be built before others? Map out the dependency graph.
3. **Group into milestones** — organize features into phases:
   - **Milestone 0: Infrastructure** (always first) — project scaffold, env vars, config, base layout, auth setup if needed
   - **Milestones 1-4** — feature milestones in dependency order
4. **Order within milestones** — within each milestone, order issues by dependency. Issue ordering IS the dependency graph — lower-numbered issues are built first.
5. **Note recommended vendor skills** — if the stack agent recommended additional vendor skills (e.g., `neon-postgres`, `supabase`, `stripe`), include the install commands in the first issue's Implementation Notes so `/build` can run them during the infrastructure phase.

### Step 3.5: Devil's Advocate

Before filing anything, challenge the synthesized plan. Spawn an **advocate agent** via the Task tool. Read `.claude/skills/plan/references/advocate-agent.md` and spawn a Task with its contents as the prompt. Append PROMPT.md and the full synthesized plan (milestones, issue list with titles, objectives, implementation notes, and dependency ordering) as context.

Handle the advocate verdict:

| Verdict | Action |
|---------|--------|
| PROCEED | Continue to Step 4 |
| REVISE | Re-synthesize once incorporating the advocate's feedback. Do not re-run the advocate — proceed to Step 4 with the revised plan. |
| ESCALATE | Route to `/ask` with the advocate's concerns for human input. |

### Step 4: Create milestones

Create milestones on GitHub. Note: `gh` does not have a built-in milestone command, so use the API:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/milestones" -f title="Phase 0: Infrastructure" -f state="open" -f description="Project scaffold, configuration, and base layout"
```

Create one milestone per phase. Maximum 5 milestones.

### Step 4b: Rate limit checkpoint

Before filing issues, re-check the API budget. Filing N issues requires ~2N API calls (create + comment):

```bash
gh api rate_limit --jq '.resources.core | "Rate limit: \(.remaining)/\(.limit) remaining"'
```

If fewer than 100 requests remain, stop and inform the user. Save the synthesized plan to a comment on a tracking issue so the next session can resume filing. If the budget is insufficient, the milestones created in Step 4 are harmless — they'll be reused when the session resumes.

### Step 4c: File README update issue

Before filing any feature issues, file a README update issue so it gets the lowest issue number. `/build` will pick it up first, replacing the default Next.js boilerplate before any feature work begins.

```bash
gh issue create \
  --title "Replace default README with project README" \
  --body "$(cat <<'EOF'
## Objective
Replace the default Next.js boilerplate README with a project-specific README derived from SPECIFICATION.md, so GitHub repo visitors understand what the project is.

## Dependencies
None

## Implementation Notes
- Read SPECIFICATION.md for project purpose, stack, and architecture
- Target audience: developers visiting the GitHub repo for the first time
- Include: project description, tech stack, getting started, development commands
- Remove all default create-next-app content

## Acceptance Criteria
- [ ] README.md describes the actual project (not Next.js boilerplate)
- [ ] Includes project purpose, tech stack, and getting started instructions
- [ ] pnpm lint passes
- [ ] pnpm tsc --noEmit passes
- [ ] pnpm test passes
- [ ] pnpm build completes without error
EOF
)" \
  --label "ai-generated" \
  --milestone "Phase 0: Infrastructure"
```

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
- [Vendor skill hints — e.g., "Use Server Actions per next-best-practices", "Follow web-design-guidelines for form accessibility"]
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
  --label "ai-generated" \
  --milestone "Phase 0: Infrastructure"
```

**Label rules:** All issues get `ai-generated`. No other labels are needed — issue ordering handles dependencies (lower number = build first), and the agent claims issues by number.

### Step 6: Post dependency comments

After all issues are filed, go back and comment on each issue to document what it blocks:

```bash
gh issue comment {N} --body "Unblocks: #{X}, #{Y}"
```

This creates a bidirectional dependency map in the issue comments.

### Step 6.5: Generate SPECIFICATION.md

Using the synthesized findings from Step 3 (do NOT re-invoke sub-agents), write a `SPECIFICATION.md` to the project root via Bash:

```bash
cat > SPECIFICATION.md <<'SPEC_EOF'
# Application Specification
> Generated by Forge /plan on YYYY-MM-DD

## Purpose
[1-2 paragraphs: what the app does, who it's for, core value proposition]

## Architecture
[Route structure, component hierarchy, data flow, state management, API design — with rationale]

## Technology Stack
[Core deps with rationale, third-party services, database/storage, auth strategy, env vars needed]

## Design System
[Layout strategy, styling decisions, key UI patterns, visual hierarchy]

## Constraints & Risks
[Technical risks with mitigations, complexity hotspots, security, performance, external deps]

## Vendor Skills Configuration
[List vendor skills installed beyond defaults, with rationale — e.g., "stripe: project handles payments"]

## Decisions Log
[Conflicts resolved during synthesis: what was chosen over what, and why]
SPEC_EOF
```

Replace each bracketed placeholder with actual content derived from the sub-agent synthesis. Keep each section to 10-15 bullet points max. The spec captures the WHY — do not duplicate the task-level WHAT already in issues. Replace `YYYY-MM-DD` with the current date.

### Step 7: Summary

After filing all issues, produce a summary:

```
Planning complete.

Milestones: {count}
Issues filed: {count}

Next: Run /forge to start the build loop.
```

### Step 8: Archive PROMPT.md (first run only)

**Skip this step if `graveyard/` already exists** — the prompt has already been archived by a previous planning run.

After filing all issues, archive the original prompt and replace it with
post-planning instructions. Use Bash commands (not Write/Edit tools):

```bash
mkdir -p graveyard
cp PROMPT.md "graveyard/$(date +%Y-%m-%d-%H%M%S).md"
cat > PROMPT.md <<'PROMPT_EOF'
Audit the current project against the original requirements archived in
graveyard/. Review what was built (closed issues) and compare it to what
was requested. Identify missing features, incomplete implementations, and
anything that doesn't match the original spec. File issues for each gap.
PROMPT_EOF
```

Then lock down PROMPT.md by adding it to the hook's protected files list.
Use jq or python3 to update `.claude/settings.json` — in the PreToolUse
hook command string, change `blocked_names=['CLAUDE.md']` to
`blocked_names=['CLAUDE.md','PROMPT.md','SPECIFICATION.md']`.

Do not commit these changes — /forge handles the branch, commit, and PR.

## Audit Mode

When `/forge` Case E re-invokes `/plan` after all issues have been closed, `graveyard/` will exist (created during the initial planning run). Your job is to compare what was requested against what was built and file issues for anything missing.

### Audit Step 1: Gather context

Read three sources to understand the full picture:

1. **Specification** — the structured architectural blueprint generated during initial planning:
   ```bash
   cat SPECIFICATION.md
   ```

2. **Original requirements** — read all files in `graveyard/`:
   ```bash
   cat graveyard/*.md
   ```

3. **What was built** — read closed issues to understand the implemented scope:
   ```bash
   gh issue list --state closed --label "ai-generated" --limit 200 --json number,title,body --jq '.[] | "### #\(.number): \(.title)\n\(.body)\n"'
   ```

Also read `CLAUDE.md` for project conventions.

### Audit Step 1.5: Explore the codebase

Before spawning audit sub-agents, explore the actual built codebase to understand what was implemented — not just what closed issues say was built:

- Use Glob to map the project structure (`src/**/*.tsx`, `src/**/*.ts`)
- Use Grep to find key patterns (route definitions, component exports, API endpoints)
- Read key files (layout components, main pages, API routes) to understand the actual architecture

Compile a codebase summary including:
- Route structure (actual `src/app/` directory layout)
- Key components and their relationships
- Data fetching patterns in use
- State management approach
- Test coverage (which files have corresponding test files)

Include this codebase summary in the audit sub-agent context alongside closed issues and graveyard requirements. This ensures the audit compares requirements against the actual implementation, not just issue descriptions.

### Audit Step 2: Spawn audit sub-agents

Read the same four reference files from `.claude/skills/plan/references/` and spawn sub-agents via the **Task tool** in parallel. For each agent, prepend the following audit context before the agent's original prompt:

```
AUDIT CONTEXT: This is a post-implementation audit, not initial planning.
The application has been built. Your job is to review what was built against
the original requirements and identify gaps, missing features, or issues.

ORIGINAL REQUIREMENTS:
[contents of graveyard/*.md]

SPECIFICATION (structured interpretation of requirements):
[contents of SPECIFICATION.md]

CLOSED ISSUES (what was planned):
[summary of closed issue titles and objectives]

CODEBASE (what was actually built):
[codebase summary from Audit Step 1.5]

Instead of recommending what to build, identify what is MISSING or WRONG
compared to the requirements. Compare against the actual codebase, not
just the closed issues — implementations may have diverged from plans. For each gap, describe what's missing and why
it matters. If everything looks complete for your area, say so explicitly.
```

Append this context, then the agent's reference file contents. The agents will analyze their respective domains (architecture, stack, design, risk) through the lens of "what's missing" rather than "what to build."

### Audit Step 3: Synthesize findings

Combine the four agent outputs into a gap analysis:

1. **Discard non-issues** — if an agent says everything looks complete, move on.
2. **Deduplicate** — multiple agents may flag the same gap from different angles.
3. **Prioritize** — rank gaps by impact on the original requirements.
4. **Skip milestones** — audit issues do not need new milestones. Assign them to existing milestones if appropriate, or leave them unassigned.

### Audit Step 4: File gap issues

If gaps were found, file them using the same structured template as initial planning (Step 5 format):

```bash
gh issue create \
  --title "Issue title" \
  --body "$(cat <<'EOF'
[issue body here]
EOF
)" \
  --label "ai-generated"
```

### Audit Step 4.5: Append revision to SPECIFICATION.md

Only if gap issues were filed in Step 4. Append (not overwrite) a revision section via Bash:

```bash
cat >> SPECIFICATION.md <<'REVISION_EOF'

## Revision — YYYY-MM-DD

### Gaps Identified
- [issue #N: title — relates to spec section X]

### Refinements
- [any architectural/design decisions refined based on build phase learnings]
REVISION_EOF
```

Replace placeholders with actual content from the gap analysis. Replace `YYYY-MM-DD` with the current date. This uses `cat >>` via Bash, which bypasses the PreToolUse hook by design — no temporary unblock needed.

If **no gaps are found**, file nothing — just output a summary:

```
Audit complete. No gaps found — all original requirements are implemented.
```

### Audit Step 5: Summary

```
Audit complete.

Issues filed: {count}
  - Missing features: {count}
  - Implementation fixes: {count}
No gaps found: {list of areas that passed audit}

Next: Run /forge to continue the build loop.
```

## Rate Limit Awareness

Before starting, check the remaining API budget:

```bash
gh api rate_limit --jq '.resources.core | "Rate limit: \(.remaining)/\(.limit) remaining (resets \(.reset | todate))"'
```

If fewer than 500 requests remain, warn the user and suggest waiting until the reset time before filing a large plan.

Rate limiting for GitHub mutations is handled automatically by the PostToolUse hook — no explicit `sleep` commands are needed in skill code.

## Rules

- **Maximum 5 milestones, 8 issues per milestone** (40 issues absolute max)
- **Every issue must have acceptance criteria** including the four standard checks (lint, typecheck, test, build)
- **File in dependency order** — foundational issues first, so lower issue numbers = build first
- **Milestone 0 is always "Infrastructure"** — this includes: Next.js scaffold, Tailwind config, base layout, environment variables, any auth setup
- **Be specific in implementation notes** — mention exact file paths, package names, and patterns
- **Err on the side of fewer, larger issues** rather than many tiny ones. Each issue should deliver a visible, testable piece of functionality.
