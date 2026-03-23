# ${\color{#d97706}\textsf{⚒ Forge}}$ ${\color{#d97706}\textsf{—}}$ ${\color{#d97706}\textit{You\ bring\ the\ blueprint.\ The\ smith\ does\ the\ rest.}}$

<p align="center">
  <img src="https://raw.githubusercontent.com/allan-mobley-jr/forge/main/assets/forge-social-preview.png" alt="Forge — Autonomous Next.js development" width="1280" />
</p>

<br/>

$${\color{#d97706}\textbf{Autonomous\ Next.js\ development\ powered\ by\ Claude\ Code.}}$$

$${\color{#d97706}\textbf{Describe\ your\ app\ in\ plain\ English\ —\ Forge\ plans,\ builds,\ and\ deploys\ it\ through\ GitHub\ and\ Vercel.}}$$

<div align="center">
  <a href="#quick-start">Quick Start</a>
  <span>&nbsp;&nbsp;·&nbsp;&nbsp;</span>
  <a href="#how-it-works">How It Works</a>
  <span>&nbsp;&nbsp;·&nbsp;&nbsp;</span>
  <a href="#commands">Commands</a>
  <span>&nbsp;&nbsp;·&nbsp;&nbsp;</span>
  <a href="#troubleshooting">Troubleshooting</a>
</div>

<br/>

## Requirements

- macOS
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with a Pro subscription, Max subscription, or API key
- GitHub account with the [Vercel GitHub App](https://github.com/apps/vercel) installed
- Vercel account

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
forge smelt                  # produce a blueprint from PROMPT.md
forge refine                 # create GitHub issues from the blueprint
forge hammer                 # implement the first issue
forge temper                 # review the implementation
forge proof                  # validate and open a PR
```

## How It Works

Forge uses a medieval forge metaphor. Six craftsmen — each a Claude Code agent — handle a specific phase of the development lifecycle. You invoke them one at a time, or let them run autonomously.

```
    You write PROMPT.md
           │
           ▼
   ┌───────────────┐       ┌──────────┐  ┌────────┐  ┌────────┐
   │  forge init   │──────▶│  GitHub  │  │ Vercel │  │   CI   │
   │  (bootstrap)  │       │   repo   │  │ project│  │pipeline│
   └───────────────┘       └──────────┘  └────────┘  └────────┘

   forge smelt  →  forge refine  →  forge hammer  →  forge temper  →  forge proof
                        ↑                                                    │
                        │                                                    │
                   forge hone  ←────────── (app running, issues done) ───────┘
```

### The Craftsmen

| Craftsman | Command | What it does |
|-----------|---------|-------------|
| **Smelter** | `forge smelt` | Reads PROMPT.md or human feature requests. Produces a blueprint in `blueprints/`. |
| **Refiner** | `forge refine` | Takes a blueprint and creates sequenced GitHub issues with milestones. |
| **Blacksmith** | `forge hammer` | Implements the lowest open issue on a feature branch. |
| **Temperer** | `forge temper` | Independently reviews the Blacksmith's work. Approves or sends back for rework. |
| **Prover** | `forge proof` | Runs tests, validates acceptance criteria, opens a PR if everything passes. |
| **Honer** | `forge hone` | Audits the codebase against the blueprint. Produces a new blueprint of improvements. |

Each command has an `auto-` variant for autonomous operation (e.g., `forge auto-smelt`). In auto mode, the agent makes decisions without asking for human input.

### Artifacts

Each craftsman produces two things:

1. **The artifact** — a blueprint, GitHub issues, code, a review, a PR
2. **A ledger entry** — reasoning and decisions recorded in `ledger/<craftsman>/`

Blueprints go in `blueprints/` (timestamped). Ledger entries go in `ledger/` (timestamped for planning phases, per-issue for implementation phases). Both are git-tracked.

### Issue Lifecycle

Issues flow through status labels:

```
status:ready → status:hammering → status:hammered → status:tempering → status:tempered → status:proving → status:proved
                     ↑                                      │                    │
                     └──────────── status:rework ◀──────────┘────────────────────┘
```

The Blacksmith always picks up the **lowest numbered open issue**. Only one issue is active at a time.

### Rework Protocol

When the Temperer or Prover rejects work:
1. They add `status:rework` and post a tagged comment (`**[Temperer]**` or `**[Prover]**`)
2. The Blacksmith reads the feedback and fixes the issues
3. The Blacksmith marks addressed comments with a `✅` prefix
4. After 3 total rework cycles, the issue is escalated to `agent:needs-human`

### Bootstrap (`forge init`)

Create a directory, write a `PROMPT.md` describing your app, and run `forge init`. The bootstrap runs idempotent steps:

- Tool checks: Homebrew, Python 3, Node, pnpm, GitHub CLI, Vercel CLI, Claude Code
- Project setup: Next.js scaffold, GitHub repo, Vercel project, CI pipeline
- Forge setup: Agents, hooks, labels, CLAUDE.md, branch protection

Every step checks whether it already ran. Resume with `forge init --resume`.

### Merge & Deploy

PRs are auto-merged after CI passes. Every merge to `main` triggers a Vercel staging deployment. Production is promoted manually:

```bash
gh workflow run deploy-production.yml -f confirm=deploy
```

## Commands

### Pipeline commands

| Command | Description |
|---------|-------------|
| `forge smelt` | Produce a blueprint from PROMPT.md (interactive) |
| `forge auto-smelt` | Same, autonomous |
| `forge refine` | Create GitHub issues from a blueprint (interactive) |
| `forge auto-refine` | Same, autonomous |
| `forge hammer` | Implement the current issue (interactive) |
| `forge auto-hammer` | Same, autonomous |
| `forge temper` | Review the current implementation (interactive) |
| `forge auto-temper` | Same, autonomous |
| `forge proof` | Validate and open a PR (interactive) |
| `forge auto-proof` | Same, autonomous |
| `forge hone` | Audit the codebase for improvements (interactive) |
| `forge auto-hone` | Same, autonomous |
| `forge auto-loop` | Chain hammer → temper → proof per issue autonomously |

All pipeline commands accept `--max-budget N` (USD per stage, API key only).

### Setup commands

| Command | Description |
|---------|-------------|
| `forge init` | Bootstrap a new project (requires `PROMPT.md`) |
| `forge init --resume` | Resume a failed or interrupted bootstrap |
| `forge update` | Update Forge to the latest version |
| `forge upgrade` | Update Forge artifacts in the current project |
| `forge doctor` | Check tool versions, auth, and project health |
| `forge uninstall` | Remove Forge from your system (keeps projects) |
| `forge --version` | Show installed version |

### Authentication

**API key users:**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

**Subscription users (Pro/Max):**
```bash
claude setup-token
echo 'export CLAUDE_CODE_OAUTH_TOKEN="<token>"' >> ~/.zshrc
```

## Label System

Target projects use these labels:

| Label | Meaning |
|-------|---------|
| `ai-generated` | Issue or PR filed by an agent |
| `agent:needs-human` | Blocked — check comments for the question |
| `status:ready` | Ready for the Blacksmith to implement |
| `status:hammering` | Implementation in progress |
| `status:hammered` | Implementation complete, awaiting review |
| `status:tempering` | Review in progress |
| `status:tempered` | Review passed, awaiting validation |
| `status:rework` | Sent back to the Blacksmith |
| `status:proving` | Validation in progress |
| `status:proved` | PR opened |

### Filing Issues for the Agent

Create an issue on GitHub — the Refiner or Blacksmith will pick it up. Human-filed issues (without `ai-generated`) can be triaged by the Smelter (feature requests) or Honer (bugs).

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Hangs after "Installing Claude Code..." | Run `claude` in another terminal to complete login, then `forge init --resume`. |
| "This directory is already a git repository" | Run `forge init --resume`. |
| SSH key or GitHub auth failures | `gh auth login --web --git-protocol ssh` |
| Agent gets stuck | Check for `agent:needs-human` label. Answer the question in the comments. |
| PR quality checks keep failing | After 3 rework cycles, the issue is escalated to `agent:needs-human`. |
| "Not a Forge project" error | Run from the project root (where `PROMPT.md` lives). |

## Repository Structure

```
forge/
├── install.sh                          # curl | bash installer
├── cli/                                # Forge CLI
│   ├── forge.sh                        #   Main executable
│   └── forge-lib.sh                    #   Shared library (labels, helpers, query functions)
├── bootstrap/setup.sh                  # Idempotent project setup
├── agents/                             # Forge craftsman agents
│   ├── smelter.md                      #   Smelter: PROMPT.md → blueprint
│   ├── refiner.md                      #   Refiner: blueprint → GitHub issues
│   ├── blacksmith.md                   #   Blacksmith: implement one issue
│   ├── temperer.md                     #   Temperer: independent code review
│   ├── prover.md                       #   Prover: validate + open PR
│   └── honer.md                        #   Honer: audit codebase → improvement blueprint
├── hooks/settings.json                 # Permissions and hook definitions
├── workflows/                          # GitHub Actions templates
│   ├── ci.yml                          #   Lint + typecheck + test + build + E2E
│   └── deploy-production.yml           #   PR-based main → production promotion
├── tests/                              # CLI tests (bats framework)
└── templates/
    ├── CLAUDE.md.hbs                   # Project CLAUDE.md template
    ├── PROMPT.md                       # Example starter prompt
    └── issue-body.md                   # Issue body template
```

## Design Decisions

**GitHub is the state machine.** No local workflow state, no database, no coordination server. All project state is encoded in GitHub Issue labels and the ledger. Clone the repo on a new Mac, run a forge command, and it picks up where it left off.

**Agents, not skills.** Each craftsman is a Claude Code agent loaded via `claude --agent`. The CLI handles dispatch and label transitions; the agent handles the work. Sub-agents for specialized tasks within each craftsman are planned.

**Ledger for reasoning.** Every craftsman records its decisions in `ledger/`. This creates an audit trail — when the Temperer reviews the Blacksmith's work, it can read *why* decisions were made, not just *what* was done.

**Blueprints feed the Refiner.** Both the Smelter (greenfield planning) and Honer (maintenance audits) produce blueprints. The Refiner doesn't care who created the blueprint — it just breaks it into issues. This creates a clean improvement cycle.

**Opinionated scope.** macOS, Next.js, Vercel, one developer. This is not a general-purpose framework — it's a sharp tool for a specific workflow.

## License

MIT
