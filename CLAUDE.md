# Forge

Autonomous Next.js development system for macOS. See `README.md` for the full specification.

## Repository Structure

```
.claude-plugin/  — Marketplace listing (marketplace.json)
plugin/          — Claude Code plugin (only this gets cached)
  .claude-plugin/  — Plugin manifest (plugin.json)
  agents/          — Forge craftsman agents (orchestrators)
    smelter.md       — Smelter: PROMPT.md → ingot issue
    refiner.md       — Refiner: ingot issue → GitHub implementation issues
    blacksmith.md    — Blacksmith: implement one issue
    temperer.md      — Temperer: independent code review
    proof-master.md  — Proof-Master: validate + open PR
    honer.md         — Honer: audit codebase → improvement ingot issue
  hooks/           — Plugin hooks (hooks.json + standalone scripts)
  system-prompt.md — Context injected into sessions via SessionStart hook
bin/             — Forge CLI (forge.sh main executable, forge-lib.sh shared library)
workflows/       — GitHub Actions CI templates
bootstrap/       — setup.sh idempotent project bootstrap
tests/           — CLI tests (bats framework)
install.sh       — curl | bash installer
research/        — ad-hoc research notes and scratchpad (not committed)
```

## Artifacts (in target projects)

All planning artifacts are stored as GitHub issues and comments — not files on disk:

- **Ingots** — GitHub issues labeled `type:ingot`, created by Smelter and Honer
- **Ledger entries** — tagged comments (e.g., `**[Blacksmith Ledger]**`) on the relevant issue
- **Rework comments** — tagged with `**[Temperer]**` or `**[Proof-Master]**`

## Conventions

- Agents use YAML frontmatter with `name`, `description`, `tools`
- Agents are invoked via `claude --agent forge:<name>` from the CLI (plugin-namespaced)
- Forge is distributed as a Claude Code plugin (user scope) + CLI (symlinked from ~/.forge/bin)
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub labels and issue comments track pipeline state

## Labels

Target projects use these labels:

- **Meta:** `ai-generated`, `agent:needs-human`
- **Artifact:** `type:ingot`
- **Status:** `status:ready`, `status:hammering`, `status:hammered`, `status:tempering`, `status:tempered`, `status:rework`, `status:proving`, `status:proved`

When creating issues or PRs for **this repo**, apply relevant labels:

- **Component:** `cli`, `bootstrap`, `agents`, `hooks`, `ci`
- **Type:** `bug`, `enhancement`, `documentation`, `refactor`, `chore`

## Pipeline Flow

```
forge smelt  →  forge refine  →  forge hammer  →  forge temper  →  forge proof
                     ↑                                                    │
                     │                                                    │
                forge hone  ←─────────── (app running, issues done) ──────┘
```

Each command has an `auto-` variant (e.g., `forge auto-smelt`) for autonomous operation.
`forge auto-run` chains hammer → temper → proof per issue through the queue.

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
