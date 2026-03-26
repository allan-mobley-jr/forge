# Forge

Autonomous Next.js development system. See `README.md` for the full specification.

## Repository Structure

```
.claude-plugin/  — Marketplace listing (marketplace.json)
plugin/          — Claude Code plugin (only this gets cached)
  .claude-plugin/  — Plugin manifest (plugin.json)
  agents/          — Forge craftsman agents (interactive + auto pairs)
    smelter.md       — Smelter: interactive ingot creation
    auto-smelter.md  — Auto-Smelter: ingot from type:feature issue
    refiner.md       — Refiner: interactive ingot → issues
    auto-refiner.md  — Auto-Refiner: ingot → issues headless
    blacksmith.md    — Blacksmith: interactive implementation
    auto-blacksmith.md — Auto-Blacksmith: headless implementation
    temperer.md      — Temperer: interactive code review
    auto-temperer.md — Auto-Temperer: headless code review
    proof-master.md  — Proof-Master: interactive testing + PR
    auto-proof-master.md — Auto-Proof-Master: headless testing + PR
    honer.md         — Honer: interactive bug triage / audit
    auto-honer.md    — Auto-Honer: headless bug triage / audit
bin/             — Forge CLI (forge.sh main executable, forge-lib.sh shared library)
bootstrap/       — setup.sh idempotent project bootstrap
tests/           — CLI tests (bats framework)
install.sh       — curl | bash installer
research/        — ad-hoc research notes and scratchpad (not committed)
```

## Artifacts (in target projects)

All planning artifacts are stored as GitHub issues and comments — not files on disk:

- **Ingots** — GitHub issues labeled `type:ingot`, created by Smelter and Honer
- **Ledger entries** — tagged comments (e.g., `**[Blacksmith Ledger]**`) on the relevant issue
- **Rework comments** — tagged with `**[Temperer]**`

## Conventions

- Agents use YAML frontmatter with `name`, `description`, `tools`
- Each craftsman has two agents: interactive (no `-p`) and auto (with `-p`)
- Agents are invoked via `claude --agent forge:<name>` from the CLI (plugin-namespaced)
- Agents own their label transitions — the CLI only reads state
- Every agent follows: research (Explore agents) → plan (Plan agent) → confer/decide → execute → record
- Domain agents at `~/.claude/agents/` are considered during research
- Forge is distributed as a Claude Code plugin (user scope) + CLI (symlinked from ~/.forge/bin)
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub labels and issue comments track pipeline state
- Forge targets Next.js + Tailwind CSS + TypeScript on Vercel — this is intentional scope, not a limitation to fix

## Labels

Target projects use these labels (23 total, defined in `forge-lib.sh`):

- **Meta:** `ai-generated`, `agent:needs-human`
- **Artifact:** `type:ingot`
- **Status:** `status:ready`, `status:hammering`, `status:hammered`, `status:tempering`, `status:tempered`, `status:rework`, `status:proving`, `status:proved`
- **Type:** `type:bug`, `type:feature`, `type:chore`, `type:refactor`
- **Priority:** `priority:high`, `priority:medium`, `priority:low`
- **Scope:** `scope:ui`, `scope:api`, `scope:data`, `scope:auth`, `scope:infra`

When creating issues or PRs for **this repo**, apply relevant labels:

- **Component:** `cli`, `bootstrap`, `agents`, `ci`
- **Type:** `bug`, `enhancement`, `documentation`, `refactor`, `chore`

## Pipeline Flow

```
forge smelt  →  forge refine  →  forge hammer  →  forge temper  →  forge proof
                     ↑                                                    │
                     │                                                    │
                forge hone  ←─────────── (app running, issues done) ──────┘
```

Each command has an `auto-` variant (e.g., `forge auto-smelt`) for autonomous operation.
`forge stoke` processes the issue queue: dispatches based on the oldest issue's status label.
`forge cast` runs the full autonomous cycle: smelt → refine → stoke → hone (repeats if new work emerges).

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
