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
   │  forge run   │    │           GitHub (state)            │
   │              │───▶│  Issues = backlog  │  PRs = work    │
   └───────┬───────┘    │  Labels = status   │  CI = quality  │
           │            └────────────┬────────────────────────┘
           ▼                         │
   ┌───────────────┐                 │
   │  /forge loop  │◀────── reads ───┘
   │               │
   │  sync ──▶ route ──┬──▶ /plan   (research + file issues)
   │    ▲              ├──▶ /build  (implement + open PR)
   │    │              └──▶ /revise (address PR feedback)
   │    │                     │
   │    └─────────────────────┘
   └───────────────┘
           │
           ▼
   CI passes ──▶ Auto-merge to main
   Merge ──▶ Vercel staging deploy
   Human promotion ──▶ Vercel production deploy
```

There are four stages: **install**, **init**, **build loop**, and **merge**. The sections below walk through each one.

### Stage 1 — Install Forge

```
  curl | bash
       │
       ├──▶ Ensures git is available (installs Xcode CLI Tools if needed)
       ├──▶ Clones Forge repo to ~/.forge/repo
       ├──▶ Creates the forge CLI at ~/.forge/bin/forge
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
       ├──▶ Install Claude Code skills (/forge, /plan, /build, /revise)
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

### Stage 3 — The Autonomous Loop

Run `forge run` in the project directory to enter the build loop:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                        /forge (orchestrator)                     │
  │                                                                  │
  │   ┌──────────┐                                                   │
  │   │  sync    │  Reads GitHub: issues, PRs, labels (3 API calls)  │
  │   └────┬─────┘  Recovers stale state, promotes unblocked issues  │
  │        │                                                         │
  │        ▼                                                         │
  │   What needs doing?                                              │
  │        │                                                         │
  │        ├── No issues yet ──────────▶ /plan                       │
  │        │                             Spawns 4 research agents    │
  │        │                             Files issues as backlog     │
  │        │                                                         │
  │        ├── Issues ready ───────────▶ /build                      │
  │        │                             Claims issue, branches      │
  │        │                             Implements, tests, opens PR │
  │        │                                                         │
  │        ├── Review requested ───────▶ /revise                     │
  │        │                             Reads PR comments           │
  │        │                             Applies fixes, re-pushes    │
  │        │                                                         │
  │        ├── Stuck on a decision ────▶ Escalate                     │
  │        │                             Posts question on issue     │
  │        │                             Labels agent:needs-human    │
  │        │                                                         │
  │        ├── PR ready to merge ──────▶ Auto-merge (squash)         │
  │        │                             Copilot mode: wait for      │
  │        │                             review first, resolve any   │
  │        │                             comments, then merge        │
  │        │                                                         │
  │        └── All issues closed ──────▶ /plan (audit for gaps)      │
  │                                                                  │
  │   After each action, /forge loops back to sync automatically.    │
  └──────────────────────────────────────────────────────────────────┘
```

**What /plan does:**
The agent reads PROMPT.md, spawns 4 research sub-agents (architecture, stack, design, risk), synthesizes their findings into a plan, and files GitHub Issues as an ordered backlog grouped into milestones. Each issue includes an objective, dependencies, implementation notes, and acceptance criteria. On the first run, PROMPT.md contains your app description; after planning, it's archived to `graveyard/`. When all issues are eventually closed, `/forge` routes back to `/plan`, which detects `graveyard/` and enters audit mode — comparing the original requirements against closed issues and filing new issues for any gaps.

**What /build does (one issue per cycle):**
The agent picks the lowest-numbered open issue with no `agent:*` label, creates a GitHub-linked feature branch (via `gh issue develop`), implements the code, then spawns up to 3 sub-agents in parallel: a review agent, a test agent, and (for UI-affecting issues) a visual check agent that takes screenshots and compares against baselines. It applies fixes, runs quality checks (lint, typecheck, test, build), deploys a Vercel preview if available, and opens a PR. The PR is then auto-merged after CI passes (and Copilot review, if enabled), enforcing a strict one-PR-at-a-time lifecycle. If quality checks fail, a debug sub-agent gets one retry. If it still fails, the issue is labeled `agent:needs-human` so you can step in. If a build times out, work-in-progress is pushed to the branch and the next session resumes from it.

**What /revise does:**
When Copilot leaves review comments or a human requests changes on a PR, the agent picks it up on the next cycle. It reads the review comments, critically evaluates each one (fixing valid issues, pushing back on incorrect suggestions), re-runs quality checks, and pushes fixes.

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
              └── Comments ─────▶ /revise evaluates each comment
                                  Fixes valid issues, challenges wrong ones
                                  Resolves all threads, then merges
```

**Auto mode** removes the reviewer from the critical path entirely — CI is the only gate. **Copilot mode** adds GitHub Copilot as an automated code reviewer; the agent addresses Copilot's feedback before merging. In both modes, human `CHANGES_REQUESTED` reviews still trigger `/revise` and take priority over auto-merge.

The agent escalates when it's stuck instead of guessing.

## Label System

Forge tracks all project state through GitHub Issue labels. There are no databases or local files — if you can see the labels on an issue, you know exactly where it stands.

### How Labels Work

Only one issue is ever active. The agent works on the lowest-numbered open issue. There are just 3 agent labels plus one metadata label:

| Label | What it means |
|-------|---------------|
| `agent:in-progress` | The agent is actively working on this issue right now. |
| `agent:done` | The agent finished and opened a PR. Waiting for CI (and Copilot review, if enabled) before auto-merge. |
| `agent:needs-human` | The agent got stuck and needs your input. Check the issue comments for the question. |
| `ai-generated` | The agent created this issue or PR. Tells you at a glance what the agent filed vs. what you filed. |

- **No `agent:*` label** = backlog. The issue is unclaimed and ready to build when its turn comes.
- **Issue ordering = dependency order.** Lower-numbered issues are built first. `/plan` files issues in the right order so dependencies are naturally satisfied.
- **Revision detection** is automatic: the orchestrator checks if an `agent:done` issue's PR has `CHANGES_REQUESTED` and routes to `/revise` — no separate label needed.

### Filing Issues for the Agent

When the agent plans a project, it creates issues automatically. If you want to file an issue yourself and have the agent work on it, just create it on GitHub — that's it. The agent picks up the lowest-numbered open issue without an `agent:*` label on its next cycle.

### Labels You Can Use Freely

These labels are for your own organization and the agent ignores them:

- `documentation`, `duplicate`, `invalid`, `wontfix` — standard GitHub triage labels
- Any custom label you create without the `agent:` prefix

### What Not to Do

- **Don't remove `agent:in-progress`** while the agent is working — let the orchestrator handle stale issues
- **Don't create labels starting with `agent:`** — that namespace is reserved for the agent's state machine

## Running Autonomously

```bash
forge run
```

Runs the pipeline orchestrator with automatic session restarts. Each session gets fresh context, syncs state from GitHub, and picks up where the last session left off. PRs are auto-merged after CI passes (and Copilot review, if enabled), so the loop continues building without waiting. The loop exits when all issues are closed, safety limits are reached, or an unrecoverable error occurs (e.g., expired GitHub auth or missing tools).

```bash
forge run --max-budget 50     # limit API spend per stage (USD)
forge run --timeout 3600      # wall-clock timeout per stage (requires coreutils: brew install coreutils)
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

The orchestrator syncs state from GitHub on every session start — open issues, in-progress PRs, labels — and picks up where it left off.


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
| PR quality checks keep failing | The agent gets 2 attempts (initial + debug retry). After that, the issue is labeled `agent:needs-human`. Check the branch — work-in-progress is always pushed. |
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

**Single entry point.** `forge run` is the sole runtime entry point. It orchestrates pipeline stages, manages session restarts, and syncs state from GitHub on every cycle.

**Auto-merge with guardrails.** PRs are auto-merged after CI passes, removing the human reviewer from the critical path. In Copilot mode, GitHub Copilot provides automated code review before merge — the agent addresses its feedback, resolving valid issues and challenging incorrect suggestions. Human `CHANGES_REQUESTED` reviews still override and trigger `/revise`. The agent escalates when it's stuck instead of guessing.

**Opinionated scope.** macOS, Next.js, Vercel, one developer. This is not a general-purpose framework — it's a sharp tool for a specific workflow. Constraints enable reliability.

## Repository Structure

```
forge/
├── install.sh              # curl | bash installer
├── bootstrap/setup.sh      # Idempotent project setup
├── skills/                 # Claude Code skill definitions
│   ├── forge/SKILL.md      #   Master orchestrator
│   ├── plan/SKILL.md       #   Research & issue filing
│   │   └── references/     #   Sub-agent prompts (architecture, stack, design, risk)
│   ├── build/SKILL.md      #   Issue → branch → PR
│   │   └── references/     #   Sub-agent prompts (review, test, debug)
│   └── revise/SKILL.md     #   Address PR review feedback
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
