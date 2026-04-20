# Forge

Autonomous Next.js development system. See `README.md` for the full specification.

## Repository Structure

```
.claude-plugin/  — Marketplace listing (marketplace.json)
plugin/          — Claude Code plugin (only this gets cached)
  .claude-plugin/  — Plugin manifest (plugin.json)
  agents/          — Forge craftsman agents (interactive + auto pairs)
    smelter.md       — Smelter: interactive bootstrap (scaffold, Vercel, INGOT.md)
    auto-smelter.md  — Auto-Smelter: headless bootstrap from feature request
    smelter-feature.md     — Smelter-Feature: interactive feature planning
    auto-smelter-feature.md — Auto-Smelter-Feature: headless feature planning
    blacksmith.md    — Blacksmith: interactive first-pass implementation
    auto-blacksmith.md — Auto-Blacksmith: headless first-pass implementation
    rework-blacksmith.md — Rework-Blacksmith: interactive rework (addresses Temperer feedback)
    auto-rework-blacksmith.md — Auto-Rework-Blacksmith: headless rework
    temperer.md      — Temperer: interactive first-pass evaluation + PR + merge + release
    auto-temperer.md — Auto-Temperer: headless first-pass evaluation + PR + merge + release
    rework-temperer.md — Rework-Temperer: interactive rework re-review
    auto-rework-temperer.md — Auto-Rework-Temperer: headless rework re-review
    workshop-blacksmith.md — Workshop-Blacksmith: interactive ad-hoc first-pass implementation
    workshop-rework-blacksmith.md — Workshop-Rework-Blacksmith: interactive ad-hoc rework
    workshop-temperer.md — Workshop-Temperer: interactive ad-hoc first-pass evaluation
    workshop-rework-temperer.md — Workshop-Rework-Temperer: interactive ad-hoc re-review
    honer.md             — Honer: interactive bug triage
    honer-audit.md       — Honer-Audit: interactive codebase audit
    auto-honer.md        — Auto-Honer: headless bug triage
    auto-honer-audit.md  — Auto-Honer-Audit: headless codebase audit
bin/             — Forge CLI (forge.sh main executable, forge-lib.sh shared library)
bootstrap/       — setup.sh idempotent project bootstrap
tests/           — CLI tests (bats framework)
install.sh       — curl | bash installer
research/        — ad-hoc research notes and scratchpad (not committed)
```

## Artifacts (in target projects)

Planning artifacts live in the codebase and on GitHub:

- **INGOT.md** — One-time project specification written directly to main by the bootstrap Smelter. Contains the architectural vision, key decisions, rejected approaches, and design language. The Blacksmith appends dated entries when making significant architectural decisions during implementation.
- **GRADING_CRITERIA.md** — Project-specific quality evaluation criteria written by the Smelter on first run. The Honer adjusts after audits. The Temperer evaluates against these alongside issue acceptance criteria.
- **Ledger entries** — tagged comments (e.g., `**[Blacksmith Ledger]**`) on the relevant issue
- **Rework comments** — tagged with `**[Temperer]**`

## Conventions

- Agents use YAML frontmatter with `name`, `description`, `tools`
- Each craftsman has two agents: interactive (no `-p`) and auto (with `-p`). The Smelter has four (bootstrap + feature variants), the Honer has four (bug triage + audit variants), the Blacksmith and Temperer each have four (first-pass + rework variants), and the Workshop Blacksmith and Temperer each have two (first-pass + rework variants, interactive only — no auto variants).
- Agents are invoked via `claude --agent forge:<name>` from the CLI (plugin-namespaced)
- Agents own their label transitions — the CLI only reads state
- Core pipeline agents (Smelter, Blacksmith, Temperer) follow: research → plan → confer/decide → execute → record
- The Temperer uses lean evaluation: reads diff + ledger + INGOT.md + GRADING_CRITERIA.md + browses the app as a user (no mandatory subagents). Also manages releases after merges.
- Domain agents at `~/.claude/agents/` are considered during research
- Forge is distributed as a Claude Code plugin (user scope) + CLI (symlinked from ~/.forge/bin)
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub labels and issue comments track pipeline state
- Named sessions are scoped to individual issues; resume on interruption, clear on completion
- Forge targets Next.js + Tailwind CSS + TypeScript on Vercel — this is intentional scope, not a limitation to fix

## Labels

Target projects use these labels (29 total, defined in `forge-lib.sh`):

- **Meta:** `ai-generated`
- **Status:** `status:ready`, `status:hammering`, `status:hammered`, `status:reworked`, `status:tempering`, `status:tempered`, `status:rework`, `status:needs-human`
- **Type:** `type:bug`, `type:feature`, `type:chore`, `type:refactor`
- **Priority:** `priority:high`, `priority:medium`, `priority:low`
- **Scope:** `scope:ui`, `scope:api`, `scope:data`, `scope:auth`, `scope:infra`, `scope:docs`
- **Workshop:** `workshop`, `workshop:hammering`, `workshop:hammered`, `workshop:reworked`, `workshop:tempering`, `workshop:tempered`, `workshop:rework`

When creating issues or PRs for **this repo**, apply relevant labels:

- **Component:** `cli`, `bootstrap`, `agents`, `ci`
- **Type:** `bug`, `enhancement`, `documentation`, `refactor`, `chore`

## Pipeline Flow

```
Core:        forge smelt  →  forge hammer  ⇄  forge temper  (repeat per issue)
Workshop:    forge hammer workshop  ⇄  forge temper workshop  (ad-hoc, user-driven)
Post-cycle:  forge hone
```

Each command has an `auto-` variant (e.g., `forge auto-smelt`) for autonomous operation. Workshop commands are interactive only.
`forge stoke` processes the issue queue: dispatches Blacksmith or Temperer based on the oldest issue's status label. Uses named sessions with resume for crash recovery.
`forge cast` runs the full autonomous cycle: smelt → stoke → hone (repeats if new work emerges). Releases happen naturally in the Temperer after merges.

Workshop mode has its own state machine with `workshop:*` labels (hammering → hammered → tempering → tempered → merged, with rework → reworked → tempering loopback). The CLI dispatches Workshop-Blacksmith/Workshop-Rework-Blacksmith on `forge hammer workshop` and Workshop-Temperer/Workshop-Rework-Temperer on `forge temper workshop` based on the current label. Workshop issues stay off the autonomous `forge stoke` / `forge cast` queue — they lack the `ai-generated` label.

## Git Workflow

### Atomic commits

**Every commit must be exactly one logical change.** This is non-negotiable.

- One fix per commit. One feature per commit. One refactor per commit.
- If you changed an agent file AND updated docs AND fixed a bootstrap bug, that's three commits — not one.
- If you're about to `git add` files from different concerns, stop and split them.
- Commit early and often. Small commits are easier to review, revert, and bisect.
- Write a short "why" summary on the first line, add detail in the body if needed.

**Test:** Before committing, review the staged diff. Can you describe the change in a single short sentence without "and"? If not, split it.

### After a PR is merged

1. `git checkout main && git pull` — switch to main and pull the merge commit
2. `git branch -d <branch>` — delete the local feature branch
3. `git remote prune origin` — remove the stale remote-tracking ref (GitHub auto-deletes the remote branch on merge)
