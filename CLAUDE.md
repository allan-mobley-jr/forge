# Forge

Autonomous Next.js development system for macOS. See `README.md` for the full specification.

## Repository Structure

```
agents/                              — Forge craftsman agents (orchestrators)
  smelter.md                         — Smelter: PROMPT.md → blueprint
  refiner.md                         — Refiner: blueprint → GitHub issues + milestones
  blacksmith.md                      — Blacksmith: implement one issue
  temperer.md                        — Temperer: independent code review
  prover.md                          — Prover: validate + open PR
  honer.md                           — Honer: audit codebase → improvement blueprint
cli/             — Forge CLI (forge.sh main executable, forge-lib.sh shared library)
hooks/           — .claude/settings.json template for projects
workflows/       — GitHub Actions CI templates
templates/       — CLAUDE.md.hbs, PROMPT.md, issue-body.md
bootstrap/       — setup.sh idempotent project bootstrap
tests/           — CLI tests (bats framework)
install.sh       — curl | bash installer
research/        — ad-hoc research notes and scratchpad (not committed)
```

## Artifact Directories (in target projects)

```
blueprints/      — Timestamped blueprints from Smelter and Honer (git-tracked)
ledger/          — Craftsman reasoning records (git-tracked)
  smelter/       — Smelter decision logs (timestamped)
  refiner/       — Refiner decision logs (timestamped)
  blacksmith/    — Blacksmith implementation decisions (per issue)
  temperer/      — Temperer review findings (per issue)
  prover/        — Prover validation results (per issue)
  honer/         — Honer audit findings (timestamped)
```

## Conventions

- Agents use YAML frontmatter with `name`, `description`, `tools`
- Agents are invoked via `claude --agent <name>` from the CLI
- Bootstrap steps are idempotent bash functions — each checks precondition before acting
- GitHub labels and the ledger track pipeline state
- Shell scripts target macOS (zsh) with Homebrew assumed

## Labels

Target projects use these labels:

- **Meta:** `ai-generated`, `agent:needs-human`
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
`forge auto-loop` chains hammer → temper → proof per issue through the queue.

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
