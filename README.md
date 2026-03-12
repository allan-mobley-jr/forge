# ⚒ Forge

<img src="https://raw.githubusercontent.com/allan-mobley-jr/forge/main/assets/forge-social-preview.png" alt="Forge — Autonomous Next.js Development" width="1280" />

Forge is an autonomous development system that turns a plain-English description of your app into a working Next.js project — planned, built, and deployed through GitHub Issues, PRs, and Vercel. You describe what you want. Claude Code does the rest. PRs are auto-merged after CI passes, with optional GitHub Copilot code review as a quality gate.

## Requirements

- macOS
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with a Pro subscription, Max subscription, or API key
- GitHub account with the [Vercel GitHub App](https://github.com/apps/vercel) installed
- Vercel account

The bootstrap installs and configures everything else (Homebrew, Node.js, pnpm, GitHub CLI, Vercel CLI, SSH keys).

> **Note:** Branch protection rulesets (required status checks + conversation resolution before merging to `main`) require GitHub Pro or a public repository. On a free plan with a private repo, the agent can push directly to `main` without CI gating. This is acceptable for solo projects but not recommended.

## Quick Start

```bash
# Install Forge (one-time)
curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

# Start a new project
mkdir my-app && cd my-app
touch PROMPT.md
```

Open `PROMPT.md` in your editor and describe the app you want to build in plain English. Then bootstrap and start building:

```bash
forge init                   # bootstraps the project
forge run                    # start building
```

## How It Works


```
    You write PROMPT.md
           │
           ▼
   ┌───────────────┐       ┌──────────┐  ┌────────┐  ┌────────┐
   │  forge init   │──────▶│  GitHub  │  │ Vercel │  │   CI   │
   │  (bootstrap)  │       │   repo   │  │ project│  │pipeline│
   └───────┬───────┘       └────┬─────┘  └────┬───┘  └────┬───┘
           │                    │             │           │
           ▼                    ▼             ▼           ▼
   ┌───────────────┐    ┌─────────────────────────────────────┐
   │  forge run    │    │           GitHub (state)            │
   │  (bash orch.) │───▶│  Issues = backlog  │  PRs = work    │
   └───────┬───────┘    │  Labels = status   │  CI = quality  │
           │            └────────────┬────────────────────────┘
           ▼                         │
   ┌───────────────────┐             │
   │  determine next   │◀── reads ───┘
   │  action (bash)    │
   │                   │
   │  ├─▶ Creating pipeline  (8 stage agents → file issues)
   │  ├─▶ Resolving pipeline (7 stage agents → implement + PR)
   │  └─▶ Revision cycle     (on demand → address PR feedback)
   └───────────────────┘
           │
           ▼
   CI passes ──▶ Auto-merge to main
   Merge ──▶ Vercel staging deploy
   Human promotion ──▶ Vercel production deploy
```

There are four stages: **install**, **init**, **pipeline**, and **merge**. The sections below walk through each one.

### Stage 1 — Install Forge

```
  curl | bash
       │
       ├──▶ Ensures git is available (installs Xcode CLI Tools if needed)
       ├──▶ Clones Forge repo to ~/.forge/repo
       ├──▶ Symlinks the forge CLI to ~/.forge/bin/forge
       └──▶ Adds ~/.forge/bin to your shell PATH
```

After restarting your terminal, you have the `forge` command. Re-running the install command updates Forge to the latest version.

### Stage 2 — Bootstrap a Project (`forge init`)

Create a directory, write a `PROMPT.md` describing your app, and run `forge init`. The bootstrap runs ~21 idempotent steps in two phases:

```
  forge init
       │
       │  Phase 1: Tool checks
       ├──▶ Homebrew, Node ≥18, pnpm ≥8
       ├──▶ GitHub CLI + authentication
       ├──▶ SSH key generation + upload
       ├──▶ Git identity + commit signing
       ├──▶ Vercel CLI + authentication
       │
       │  Phase 2: Project setup
       ├──▶ git init + scaffold Next.js (TypeScript, Tailwind, App Router)
       ├──▶ Install test stack (Vitest, Playwright, Testing Library)
       ├──▶ Create GitHub repo + push
       ├──▶ Link Vercel project
       ├──▶ Generate AGENTS.md (Next.js framework docs index via @next/codemod)
       ├──▶ Install Claude Code skills (orchestrators + stage agents)
       ├──▶ Install vendor skills (next-best-practices, web-design-guidelines, etc.)
       ├──▶ Install hooks (file guards, rate limiting, session management)
       ├──▶ Install CI pipeline (lint, typecheck, test, build, E2E)
       ├──▶ Choose merge mode (copilot or auto)
       ├──▶ Generate CLAUDE.md from template
       ├──▶ Set up branch protection + labels (+ Copilot review if selected)
       └──▶ Done — ready to build
```

Every step checks whether it already ran before acting. If bootstrap fails partway through (network error, auth timeout), resume from where it stopped:

```bash
forge init --resume
```

### Stage 3 — The Pipeline Orchestrator

Run `forge run` in the project directory to start the bash-orchestrated pipeline:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                    forge run (bash orchestrator)                 │
  │                                                                  │
  │   determine_next_action()                                        │
  │        │  Reads GitHub: issues, PRs, labels, stage state         │
  │        │  Detects human responses on needs-human issues          │
  │        │  Detects CHANGES_REQUESTED / CI failures on PRs         │
  │        │                                                         │
  │        ├── PROMPT.md, no issues ────▶ Creating pipeline          │
  │        │                              8 stage agents via         │
  │        │                              forge-create-orchestrator  │
  │        │                                                         │
  │        ├── Backlog issue ready ─────▶ Resolving pipeline         │
  │        │                              7 stage agents via         │
  │        │                              forge-resolve-orchestrator │
  │        │                                                         │
  │        ├── PR needs changes ────────▶ Revision cycle             │
  │        │                              forge-resolve-orchestrator │
  │        │                              with --revise flag         │
  │        │                                                         │
  │        ├── Stuck on a decision ─────▶ Wait for human             │
  │        │                              agent:needs-human label    │
  │        │                              24h timeout auto-resolves  │
  │        │                                                         │
  │        └── All issues closed ───────▶ Done                       │
  │                                                                  │
  │   Bash controls execution. Each stage is a separate claude -p    │
  │   session. Labels are state. Comments are artifacts.             │
  └──────────────────────────────────────────────────────────────────┘
```

**Creating pipeline** (8 stages — runs when PROMPT.md exists and no issues have been filed):
The `forge-create-orchestrator` spawns 8 stage agents in order: researcher (reads PROMPT.md, gathers context), architect (architecture analysis), designer (design analysis), stacker (stack analysis), assessor (risk assessment), planner (synthesizes into ordered issue breakdown), advocate (challenges the plan — PROCEED/REVISE/ESCALATE), and filer (creates GitHub milestones and issues, generates SPECIFICATION.md, archives PROMPT.md). Each stage posts its analysis as a structured comment on a planning issue.

**Resolving pipeline** (7 stages — runs once per backlog issue):
The `forge-resolve-orchestrator` spawns 7 stage agents: researcher (explores codebase, triages), planner (designs implementation approach), advocate (challenges the plan — PROCEED/REVISE/ESCALATE), implementor (writes code, pushes branch), tester (writes and runs tests), reviewer (self-review, quality checks), and opener (opens PR). One issue at a time, lowest-numbered first.

**Revision cycle** (on demand — runs when a PR has review feedback or CI failures):
The `forge-resolve-orchestrator --revise` spawns the reviser agent, which reads PR comments, evaluates each one (fixing valid issues, pushing back on incorrect suggestions), and pushes fixes.

### Stage 4 — Merge

PRs are auto-merged after CI passes. You choose the merge mode during `forge init`:

```
  PR opened by agent
       │
       ├──▶ Lint           (pnpm lint)
       ├──▶ TypeCheck      (pnpm tsc --noEmit)
       ├──▶ Unit Tests     (pnpm test)
       ├──▶ Build          (pnpm build)
       ├──▶ E2E Tests      (pnpm test:e2e, if e2e/ exists)
       ├──▶ Vercel Preview (automatic deploy)
       │
       ▼
  CI passes
       │
       ├── Auto mode ────────▶ Squash-merge immediately
       │                       Vercel deploys to production
       │
       └── Copilot mode ────▶ GitHub Copilot reviews the PR
              │
              ├── No comments ──▶ Squash-merge
              └── Comments ─────▶ Revision cycle evaluates each comment
                                  Fixes valid issues, challenges wrong ones
                                  Resolves all threads, then merges
```

**Auto mode** removes the reviewer from the critical path entirely — CI is the only gate. **Copilot mode** adds GitHub Copilot as an automated code reviewer; the agent addresses Copilot's feedback before merging. In both modes, human `CHANGES_REQUESTED` reviews still trigger a revision cycle and take priority over auto-merge.

The agent escalates when it's stuck instead of guessing.

## Label System

Forge tracks all project state through GitHub Issue labels. There are no databases or local files — if you can see the labels on an issue, you know exactly where it stands.

### How Labels Work

Only one issue is ever active. The agent works on the lowest-numbered open issue. Labels track pipeline state:

| Label | What it means |
|-------|---------------|
| `agent:create-*` | The creating pipeline is running this stage (e.g., `agent:create-researcher`). |
| `agent:resolve-*` | The resolving pipeline is running this stage (e.g., `agent:resolve-implementor`). |
| `agent:done` | The agent finished and opened a PR. Waiting for CI (and Copilot review, if enabled) before auto-merge. |
| `agent:needs-human` | The agent got stuck and needs your input. Check the issue comments for the question. |
| `ai-generated` | The agent created this issue or PR. Tells you at a glance what the agent filed vs. what you filed. |

- **No `agent:*` label** = backlog. The issue is unclaimed and ready to build when its turn comes.
- **Issue ordering = dependency order.** Lower-numbered issues are built first. The creating pipeline files issues in the right order so dependencies are naturally satisfied.
- **Revision detection** is automatic: the bash orchestrator checks if an `agent:done` issue's PR has `CHANGES_REQUESTED` or CI failures and routes to a revision cycle — no separate label needed.

### Filing Issues for the Agent

When the agent plans a project, it creates issues automatically. If you want to file an issue yourself and have the agent work on it, just create it on GitHub — that's it. The agent picks up the lowest-numbered open issue without an `agent:*` label on its next cycle.

### Labels You Can Use Freely

These labels are for your own organization and the agent ignores them:

- `documentation`, `duplicate`, `invalid`, `wontfix` — standard GitHub triage labels
- Any custom label you create without the `agent:` prefix

### What Not to Do

- **Don't remove `agent:create-*` or `agent:resolve-*` labels** while the agent is working — let the bash orchestrator handle state transitions
- **Don't create labels starting with `agent:`** — that namespace is reserved for the pipeline's state machine

## Running Autonomously

```bash
forge run
```

Runs the bash pipeline orchestrator. It determines what needs doing (via `determine_next_action`), invokes the appropriate pipeline (creating or resolving), and loops until all issues are closed, safety limits are reached, or an unrecoverable error occurs (e.g., expired GitHub auth or missing tools). Each pipeline stage runs as a separate `claude -p` session with fresh context. PRs are auto-merged after CI passes (and Copilot review, if enabled).

```bash
forge run --max-budget 50     # limit API spend per stage (USD, API key only)
```

### Authentication

`forge run` requires a token or API key that doesn't expire mid-session. `forge init` configures GitHub authentication; Claude API auth must be set up separately using the steps below.

**API key users** — set your key in the environment and you're good to go:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
forge run
```

Add the export to `~/.zshrc` to make it permanent.

**Pro and Max subscription users** — OAuth tokens expire after ~10 minutes in headless mode. Generate a long-lived token instead:

```bash
claude setup-token
```

Then add it to your shell profile:

```bash
echo 'export CLAUDE_CODE_OAUTH_TOKEN="<token>"' >> ~/.zshrc
source ~/.zshrc
forge run
```

## Extending the Workflow

Forge auto-merges PRs after CI passes, and every merge to `main` triggers a Vercel staging deployment. Production deployments are promoted manually. The sections below describe the built-in deployment architecture and how to layer additional quality gates on PRs. The agent cannot modify `.github/workflows/` (hooks block it), so any workflows you add are safe from agent changes.

### Staged production deployments

Every Forge project has a built-in staging/production split:

- **`main` branch** → Vercel "Staging" deployment (where the agent works)
- **`production` branch** → Vercel "Production" deployment (your live site)
- **PR branches** → Vercel "Preview" deployments

The agent works exclusively on `main`. It never touches the `production` branch. When you're ready to ship, promote `main` to production via the GitHub Actions workflow:

```bash
gh workflow run deploy-production.yml -f confirm=deploy
```

This creates a PR from `main` → `production` and merges it, triggering a Vercel production deployment. The `production` branch is protected by a GitHub ruleset — no direct pushes, no force pushes, no deletion, no bypass actors.

Bootstrap sets this up automatically: creates the `production` branch, configures Vercel to use it as the production branch, creates a staging custom environment on `main`, and installs the deploy workflow and protection ruleset.

### Additional CI checks

You can add GitHub Actions workflows to `.github/workflows/` as additional PR quality gates. Some useful ones:

- **Security:** [`dependency-review-action`](https://github.com/actions/dependency-review-action) flags vulnerable or restrictively-licensed new dependencies. [`CodeQL`](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning-with-codeql) runs static analysis.
- **Performance:** [`lighthouse-ci-action`](https://github.com/treosh/lighthouse-ci-action) enforces page-speed budgets on preview deployments.
- **Bundle size:** [`bundle-stats`](https://github.com/relative-ci/bundle-stats) catches size regressions between the base branch and the PR.

To make a new check required, add its job name to the branch protection ruleset's **Required status checks** list in your GitHub repo settings.

> **Warning:** Do not rename the existing `Quality Checks` job in `ci.yml` — it's referenced by the branch protection ruleset created during bootstrap. Renaming it will block all PRs from merging.

## Resuming Work

All project state lives on GitHub — there's nothing local to lose. Coming back to a project works the same in either mode:

```bash
cd my-app
forge run
```

The bash orchestrator reads labels and comments from GitHub on every cycle — open issues, in-progress stages, PRs — and picks up where it left off.


## Troubleshooting

### During bootstrap (`forge init`)

| Problem | Fix |
|---------|-----|
| Hangs after "Installing Claude Code..." | Claude Code is waiting for auth. Run `claude` in another terminal to complete login, then `forge init --resume`. |
| "This directory is already a git repository" | Run `forge init --resume` to continue where it left off. |
| SSH key or GitHub auth failures | Run `gh auth status`. If not authenticated: `gh auth login --web --git-protocol ssh`. |
| Vercel login fails or times out | Run `vercel login` manually, then `forge init --resume`. |

### During the build loop

| Problem | Fix |
|---------|-----|
| Agent gets stuck on an issue | Check GitHub — the issue is likely labeled `agent:needs-human` with a question in the comments. Answer there and the agent continues on the next cycle. |
| PR quality checks keep failing | CI failures trigger a revision cycle. If the reviser can't fix them, the issue is labeled `agent:needs-human`. Check the branch — work-in-progress is always pushed. |
| Rate limit warnings | GitHub allows 5,000 requests/hour. Forge throttles mutations with `sleep 1`, so this is rare. If it happens, wait for the reset time shown in the warning. |
| Session ends unexpectedly | Context windows are finite. Use `forge run` for automatic restarts with fresh context. The orchestrator recovers state from GitHub each time. |
| "Not a Forge project" error | Run commands from the project root (where `PROMPT.md` and `CLAUDE.md` live). |
| Want to add features after initial build | Create a GitHub Issue and start a new session. The agent picks it up by issue number order. |

## Commands

| Command | Description |
|---------|-------------|
| `forge init` | Bootstrap a new project (requires `PROMPT.md` in current directory) |
| `forge init --resume` | Resume a failed or interrupted bootstrap |
| `forge run` | Run the autonomous build loop (headless) |
| `forge update` | Update Forge to the latest version |
| `forge upgrade` | Update Forge artifacts (skills, vendor skills, hooks, CLAUDE.md, AGENTS.md) in the current project |
| `forge doctor` | Check tool versions, auth, disk space, and project health |
| `forge uninstall` | Remove Forge from your system (keeps existing projects) |
| `forge --version` | Show installed version |

## Design Decisions

**GitHub is the state machine.** No local workflow state, no database, no coordination server. All project state is encoded in GitHub Issue labels and PR status. Clone the repo on a new Mac, run `forge run`, and the session picks up exactly where it left off. This design trades flexibility for reliability — you can never lose state because of a crashed session or a lost laptop.

**Bash orchestrates, not the LLM.** `forge run` is a bash script that determines what needs doing and invokes the right pipeline. Each pipeline stage is a separate `claude -p` session — bash controls execution order, not the LLM. This guarantees every stage runs because bash invokes it.

**Auto-merge with guardrails.** PRs are auto-merged after CI passes, removing the human reviewer from the critical path. In Copilot mode, GitHub Copilot provides automated code review before merge — the agent addresses its feedback, resolving valid issues and challenging incorrect suggestions. Human `CHANGES_REQUESTED` reviews still override and trigger a revision cycle. The agent escalates when it's stuck instead of guessing.

**Opinionated scope.** macOS, Next.js, Vercel, one developer. This is not a general-purpose framework — it's a sharp tool for a specific workflow. Constraints enable reliability.

## Repository Structure

```
forge/
├── install.sh              # curl | bash installer + pipeline orchestrator
├── bootstrap/setup.sh      # Idempotent project setup
├── skills/                 # Claude Code skill definitions (orchestrators)
│   ├── forge-create-orchestrator/  # Creating pipeline (8 stages → file issues)
│   └── forge-resolve-orchestrator/ # Resolving pipeline (7 stages → implement + PR)
├── agents/                 # Pipeline stage agents
│   ├── create-*.md         #   8 creating stages (researcher → filer)
│   └── resolve-*.md        #   8 resolving stages (researcher → reviser)
├── hooks/settings.json     # Permissions and hook definitions
├── workflows/              # GitHub Actions templates
│   ├── ci.yml              #   Lint + typecheck + test + build + E2E
│   └── deploy-production.yml #  PR-based main → production promotion
└── templates/
    ├── CLAUDE.md.hbs       # Project CLAUDE.md template
    ├── PROMPT.md           # Example starter prompt
    └── issue-body.md       # Issue body template
```

## License

MIT
