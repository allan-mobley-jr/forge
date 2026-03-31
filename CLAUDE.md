# Forge

Autonomous Next.js development system. See `README.md` for the full specification.

## Repository Structure

```
.claude-plugin/  — Marketplace listing (marketplace.json)
plugin/          — Claude Code plugin (only this gets cached)
  .claude-plugin/  — Plugin manifest (plugin.json)
  agents/          — Forge craftsman agents (interactive + auto pairs)
    smelter.md       — Smelter: interactive planning + issue creation
    auto-smelter.md  — Auto-Smelter: plan + create issues from type:feature
    blacksmith.md    — Blacksmith: interactive implementation
    auto-blacksmith.md — Auto-Blacksmith: headless implementation
    temperer.md      — Temperer: interactive review + PR + merge
    auto-temperer.md — Auto-Temperer: headless review + PR + merge
    proof-master.md  — Proof-Master: interactive releases + versioning
    auto-proof-master.md — Auto-Proof-Master: headless releases + versioning
    honer.md         — Honer: interactive bug triage / audit
    auto-honer.md    — Auto-Honer: headless bug triage / audit
    scribe.md        — Scribe: interactive doc audit / wiki
    auto-scribe.md   — Auto-Scribe: headless doc audit / wiki
bin/             — Forge CLI (forge.sh main executable, forge-lib.sh shared library)
bootstrap/       — setup.sh idempotent project bootstrap
tests/           — CLI tests (bats framework)
install.sh       — curl | bash installer
research/        — ad-hoc research notes and scratchpad (not committed)
```

## Artifacts (in target projects)

Planning artifacts live in the codebase and on GitHub:

- **INGOT.md** — One-time project specification written directly to main by the Smelter on first run. Contains the architectural vision, key decisions, and rejected approaches. The Blacksmith appends dated entries when making significant architectural decisions during implementation.
- **GRADING_CRITERIA.md** — Project-specific quality evaluation criteria written by the Smelter on first run. The Honer adjusts after audits. The Temperer evaluates against these alongside issue acceptance criteria.
- **Ledger entries** — tagged comments (e.g., `**[Blacksmith Ledger]**`) on the relevant issue
- **Rework comments** — tagged with `**[Temperer]**`

## Conventions

- Agents use YAML frontmatter with `name`, `description`, `tools`
- Each craftsman has two agents: interactive (no `-p`) and auto (with `-p`)
- Agents are invoked via `claude --agent forge:<name>` from the CLI (plugin-namespaced)
- Agents own their label transitions — the CLI only reads state
- Core pipeline agents (Smelter, Blacksmith, Temperer) follow: research → plan → confer/decide → execute → record
- The Temperer uses lean review: reads diff + ledger + INGOT.md + GRADING_CRITERIA.md + E2E tests (no mandatory Explore/Plan subagents)
- Domain agents at `~/.claude/agents/` are considered during research
- Forge is distributed as a Claude Code plugin (user scope) + CLI (symlinked from ~/.forge/bin)
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub labels and issue comments track pipeline state
- Named sessions persist across issues within a milestone for context preservation
- Forge targets Next.js + Tailwind CSS + TypeScript on Vercel — this is intentional scope, not a limitation to fix

## Labels

Target projects use these labels (20 total, defined in `forge-lib.sh`):

- **Meta:** `ai-generated`, `agent:needs-human`
- **Status:** `status:ready`, `status:hammering`, `status:hammered`, `status:tempering`, `status:tempered`, `status:rework`
- **Type:** `type:bug`, `type:feature`, `type:chore`, `type:refactor`
- **Priority:** `priority:high`, `priority:medium`, `priority:low`
- **Scope:** `scope:ui`, `scope:api`, `scope:data`, `scope:auth`, `scope:infra`, `scope:docs`

When creating issues or PRs for **this repo**, apply relevant labels:

- **Component:** `cli`, `bootstrap`, `agents`, `ci`
- **Type:** `bug`, `enhancement`, `documentation`, `refactor`, `chore`

## Pipeline Flow

```
Core:        forge smelt  →  forge hammer  ⇄  forge temper  (repeat per issue)
Post-cycle:  forge hone  →  forge scribe  →  forge proof
```

Each command has an `auto-` variant (e.g., `forge auto-smelt`) for autonomous operation.
`forge stoke` processes the issue queue: dispatches Blacksmith or Temperer based on the oldest issue's status label. Uses named sessions with resume for crash recovery.
`forge cast` runs the full autonomous cycle: smelt → stoke → hone → scribe → proof (repeats if new work emerges).

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
