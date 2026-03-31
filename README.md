# ${\color{#d97706}\textsf{⚒ Forge}}$ ${\color{#d97706}\textsf{—}}$ ${\color{#d97706}\textit{You\ bring\ the\ ingot.\ The\ smith\ does\ the\ rest.}}$

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

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with a Pro subscription, Max subscription, or API key
- GitHub account with the [Vercel GitHub App](https://github.com/apps/vercel) installed
- Vercel account

## Quick Start

```bash
# Install Forge (one-time)
curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

# Start a new project
mkdir my-app && cd my-app
forge init
```

> **Note:** The installer also sets up the **Vercel plugin** and **Playwright MCP** for Claude Code. The Vercel plugin requires OAuth authentication — it will prompt on first use. Playwright runs locally and needs no auth.

Then start building:

```bash
forge smelt                  # describe your app — the Smelter plans and creates issues
forge stoke                  # autonomously implement, review, and merge each issue
forge cast                   # full autonomous cycle: smelt → stoke → proof → hone → scribe
```

## How It Works

Forge uses a medieval forge metaphor. Three core craftsmen — each a Claude Code agent — handle the development pipeline. Three post-cycle craftsmen handle releases, auditing, and documentation. You invoke them one at a time, or let them run autonomously.

```
   ┌───────────────┐       ┌──────────┐
   │  forge init   │──────▶│  GitHub  │
   │  (bootstrap)  │       │   repo   │
   └───────────────┘       └──────────┘

   Core:        forge smelt  →  forge hammer  ⇄  forge temper  (per issue)
                                ↑─── forge stoke ───↑

   Post-cycle:  forge hone  →  forge scribe  →  forge proof

                forge cast  =  smelt → stoke → hone → scribe → proof (full cycle)
```

### The Craftsmen

| Craftsman | Command | What it does |
|-----------|---------|-------------|
| **Smelter** | `forge smelt` | Researches, plans, and creates sequenced implementation issues. On first run, produces the project ingot (INGOT.md). |
| **Blacksmith** | `forge hammer` | Implements the lowest open issue on a feature branch. Reads INGOT.md for architectural context. |
| **Temperer** | `forge temper` | Reviews the Blacksmith's work with E2E tests. Approves and merges, or sends back for rework. |
| **Proof-Master** | `forge proof` | Checks for unreleased work on main. Creates versioned releases with changelog. |
| **Honer** | `forge hone` | Triages bugs or audits the codebase. Files implementation issues for the Blacksmith. |
| **Scribe** | `forge scribe` | Audits documentation and maintains the GitHub Wiki. Files doc issues for the Blacksmith. |

Each command has an `auto-` variant for autonomous operation (e.g., `forge auto-smelt`). In auto mode, the agent runs headless via `-p` without human interaction.

### Interactive vs Auto

Every agent exists in two variants:

- **Interactive** (`forge smelt`): launches a Claude Code session where you confer with the agent — describe what you want, answer questions, approve the plan before it acts.
- **Auto** (`forge auto-smelt`): runs headless with `-p`. The agent makes decisions autonomously and documents assumptions.

> **Single-track pipeline:** Forge processes one issue at a time, in the order they were created. Do not run multiple `forge stoke` or `forge cast` sessions concurrently — they will conflict on the same issue.

### Agent Architecture

The three core agents follow a structured pattern:

- **Smelter**: research (parallel Explore agents) → plan (mandatory Plan agent) → confer/decide → create issues → record
- **Blacksmith**: read INGOT.md → research → plan → implement → test → self-review (proportional) → record
- **Temperer**: read INGOT.md → lean review (diff + ledger + E2E tests) → verdict → PR/merge → record

Agents check for user-defined domain agents at `~/.claude/agents/` and spawn them as subagents when relevant.

### Session Management

Named sessions persist across issues within a milestone. The CLI resumes sessions on crash or relaunch, preserving the agent's full context. Sessions clear at milestone boundaries. Session state is stored in `~/.forge/config.json` per project.

### Artifacts

- **INGOT.md** — One-time project specification written directly to main by the Smelter on first run. Contains the architectural vision, key decisions, and rejected approaches. The Blacksmith appends dated entries during implementation.
- **GRADING_CRITERIA.md** — Project-specific quality evaluation criteria written by the Smelter, adjusted by the Honer after audits. The Temperer evaluates against these alongside issue acceptance criteria.
- **Ledger entries** — Reasoning records as tagged comments (e.g., `**[Blacksmith Ledger]**`) on the relevant issue. Include Approaches Rejected sections.
- **Rework comments** — Tagged with `**[Temperer]**`, addressed by prepending `✅`

### Issue Lifecycle

Issues flow through status labels. Agents own all label transitions.

```
status:ready → status:hammering → status:hammered → status:tempering → status:tempered → merged
                     ↑                                      │
                     └──────────── status:rework ◀──────────┘
```

The Blacksmith always picks up the **lowest numbered open issue** — `agent:needs-human` first (interactive recovery), then `status:rework`, then `status:ready`. Only one issue is active at a time.

### Rework Protocol

When the Temperer rejects work:
1. It sets `status:rework` and posts a tagged comment (`**[Temperer]**`)
2. The Blacksmith reads the feedback and fixes the issues
3. The Blacksmith marks addressed comments with a `✅` prefix
4. After 5 total rework cycles, the issue is escalated to `agent:needs-human`

### Bootstrap (`forge init`)

Create a directory and run `forge init`. The bootstrap runs idempotent steps:

- Tool checks: Node.js >= 24, pnpm >= 9, gh CLI, Vercel CLI, python3
- Forge plugin verification
- Git init, GitHub repo, branch protection, production branch
- Label taxonomy (22 labels)
- Project registration in `~/.forge/config.json` (with session slots)

Every step checks whether it already ran. Resume with `forge init --resume`.

### Git Workflow

- All commits happen on issue branches — never directly on `main` or `production`
- Only issue branches merge to `main` via PR
- The `production` branch is off-limits to agents — human-only deploys via `forge deploy`

### Deploy

```bash
forge deploy                 # fast-forwards production to main
```

Vercel watches the `production` branch and deploys automatically. The human controls *when*, Vercel handles *how*.

## Commands

### Pipeline commands

| Command | Description |
|---------|-------------|
| `forge smelt` | Plan and create implementation issues (interactive) |
| `forge auto-smelt` | Picks up oldest human-filed `type:feature` issue |
| `forge hammer` | Implement the current issue (interactive) |
| `forge auto-hammer` | Same, autonomous |
| `forge temper` | Review, open PR, and merge (interactive) |
| `forge auto-temper` | Same, autonomous |
| `forge proof` | Create a GitHub release (interactive) |
| `forge auto-proof` | Same, autonomous |
| `forge hone` | Triage bugs or audit the codebase (interactive) |
| `forge auto-hone` | Triages oldest bug first, then audits |
| `forge stoke` | Process the issue queue autonomously |
| `forge cast` | Full autonomous cycle: smelt → stoke → proof → hone → scribe |

### Operations

| Command | Description |
|---------|-------------|
| `forge deploy` | Fast-forward production to main (human only) |

### Setup commands

| Command | Description |
|---------|-------------|
| `forge init` | Bootstrap a new project |
| `forge init --resume` | Resume a failed or interrupted bootstrap |
| `forge version` | Show installed version and check for updates |
| `forge update` | Update Forge to the latest version |
| `forge doctor` | Check tool versions and project health |
| `forge help` | List all commands |
| `forge help <command>` | Show help for a specific command |
| `forge uninstall` | Remove Forge from your system (keeps projects) |

## Label System

Target projects use these labels:

### Pipeline labels

| Label | Meaning |
|-------|---------|
| `ai-generated` | Issue or PR filed by an agent |
| `agent:needs-human` | Blocked — check comments for the question |
| `status:ready` | Ready for the Blacksmith to implement |
| `status:hammering` | Implementation in progress |
| `status:hammered` | Implementation complete, awaiting review |
| `status:tempering` | Review in progress |
| `status:tempered` | Review passed, PR/merge in progress |
| `status:rework` | Sent back to the Blacksmith |

### Descriptive labels

| Label | Meaning |
|-------|---------|
| `type:bug` | Something is broken |
| `type:feature` | New functionality |
| `type:chore` | Maintenance or infrastructure |
| `type:refactor` | Code improvement without behavior change |
| `priority:high` | Needs immediate attention |
| `priority:medium` | Should be addressed soon |
| `priority:low` | Nice to have |
| `scope:ui` | Frontend or visual changes |
| `scope:api` | Backend or API changes |
| `scope:data` | Database or data model changes |
| `scope:auth` | Authentication or authorization |
| `scope:infra` | CI, deploy, or config changes |

### Filing Issues for the Agent

Create an issue on GitHub with the appropriate labels:
- **Feature requests:** add `type:feature` — the Smelter will pick it up in auto mode
- **Bug reports:** add `type:bug` — the Honer will triage it in auto mode

Human-filed issues (without `ai-generated`) are what trigger the auto-smelter and auto-honer.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "This directory is already a git repository" | Run `forge init --resume`. |
| SSH key or GitHub auth failures | `gh auth login --web --git-protocol ssh` |
| Agent gets stuck | Check for `agent:needs-human` label. Answer the question in the comments. |
| PR quality checks keep failing | After 5 rework cycles, the issue is escalated to `agent:needs-human`. |
| "Not a Forge project" error | Run from the project root where `forge init` was run. |

## Repository Structure

```
forge/
├── install.sh                          # curl | bash installer
├── bin/                                # Forge CLI
│   ├── forge.sh                        #   Main executable
│   └── forge-lib.sh                    #   Shared library (labels, helpers, session management)
├── bootstrap/setup.sh                  # Idempotent project setup
├── plugin/                             # Claude Code plugin
│   ├── .claude-plugin/plugin.json      #   Plugin manifest
│   └── agents/                         #   Forge craftsman agents (interactive + auto)
├── tests/                              # CLI tests (bats framework)
└── .claude-plugin/marketplace.json     # Marketplace listing
```

## Design Decisions

**GitHub is the state machine.** No local workflow state, no database, no coordination server. All project state is encoded in GitHub Issue labels and comments. Clone the repo on a new Mac, run a forge command, and it picks up where it left off.

**Three core agents, not seven.** Research against Anthropic's harness design articles showed that fewer, more capable agents with richer handoffs outperform a long pipeline. The Smelter (planner), Blacksmith (generator), and Temperer (evaluator) map to Article 1's validated Planner/Generator/Evaluator triad. See `research/harness-design-analysis.md`.

**Agents own their state.** Each agent sets its own status labels — the CLI is a thin dispatcher that finds issues and launches agents. If an agent crashes mid-run, the in-progress label (`status:hammering`, etc.) persists and `forge stoke` picks it back up with session resume.

**INGOT.md for architectural context.** The Smelter writes `INGOT.md` directly to main on first run — no intermediate GitHub issue, no Blacksmith materialization step. Every subsequent agent reads it for Key Decisions and Approaches Rejected, eliminating the context loss that plagued the old multi-handoff pipeline.

**GRADING_CRITERIA.md for quality evaluation.** The Smelter devises project-specific grading criteria informed by Anthropic's four evaluation dimensions (design quality, originality, craft, functionality). The Temperer evaluates against these alongside issue acceptance criteria. The Honer adjusts criteria after audits, closing the evaluator tuning loop.

**Named sessions with resume.** Sessions persist across issues within a milestone, preserving the agent's full reasoning context. The CLI resumes on crash or relaunch. Sessions clear at milestone boundaries.

**Lean Temperer.** The Temperer reads the diff, Blacksmith ledger, INGOT.md, and runs E2E tests — no mandatory Explore/Plan subagents. This matches Article 1's recommendation for evaluators that test artifacts directly.

**Ledger for reasoning.** Every craftsman records its decisions as tagged comments on GitHub issues, including an Approaches Rejected section. This creates an audit trail — when the Temperer reviews the Blacksmith's work, it can read *why* decisions were made, not just *what* was done.

**Opinionated scope.** Next.js, Vercel, one developer. This is not a general-purpose framework — it's a sharp tool for a specific workflow.

## License

MIT
