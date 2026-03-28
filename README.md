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
forge smelt                  # describe your app to the Smelter
forge refine                 # create GitHub issues from the ingot
forge stoke                  # autonomously implement, review, and PR each issue
forge cast                   # full autonomous cycle: smelt → refine → stoke → hone → scribe
```

## How It Works

Forge uses a medieval forge metaphor. Seven craftsmen — each a Claude Code agent — handle a specific phase of the development lifecycle. You invoke them one at a time, or let them run autonomously.

```
   ┌───────────────┐       ┌──────────┐
   │  forge init   │──────▶│  GitHub  │
   │  (bootstrap)  │       │   repo   │
   └───────────────┘       └──────────┘

   forge smelt  →  forge refine  →  forge hammer  →  forge temper  →  forge proof
                        ↑              ↑─── forge stoke ───↑              │
                        │                                                 │
          forge scribe  ←  forge hone  ←── (app running, issues done) ────┘

                   forge cast  =  smelt → refine → stoke → hone → scribe (full cycle)
```

### The Craftsmen

| Craftsman | Command | What it does |
|-----------|---------|-------------|
| **Smelter** | `forge smelt` | Works with you to produce a comprehensive ingot (GitHub issue). |
| **Refiner** | `forge refine` | Takes an ingot and creates sequenced GitHub issues with milestones. |
| **Blacksmith** | `forge hammer` | Implements the lowest open issue on a feature branch. |
| **Temperer** | `forge temper` | Independently reviews the Blacksmith's work. Approves or sends back for rework. |
| **Proof-Master** | `forge proof` | Ensures test coverage, writes missing tests, fixes test failures, manages CI, and opens a PR. |
| **Honer** | `forge hone` | Triages bugs or audits the codebase. Files implementation issues or ingots. |
| **Scribe** | `forge scribe` | Audits documentation and maintains the GitHub Wiki. Files doc issues for the Blacksmith. |

Each command has an `auto-` variant for autonomous operation (e.g., `forge auto-smelt`). In auto mode, the agent runs headless via `-p` without human interaction.

### Interactive vs Auto

Every agent exists in two variants:

- **Interactive** (`forge smelt`): launches a Claude Code session where you confer with the agent — describe what you want, answer questions, approve the plan before it acts.
- **Auto** (`forge auto-smelt`): runs headless with `-p`. The agent makes decisions autonomously and documents assumptions.

> **Single-track pipeline:** Forge processes one issue at a time, in the order they were created. Do not run multiple `forge stoke` or `forge cast` sessions concurrently — they will conflict on the same issue.

### Agent Architecture

Every Forge agent follows the same pattern:

1. **Research** — parallel Explore agents investigate the codebase, context, and domain
2. **Plan** — a mandatory Plan agent informs the approach (agents own and adjust the output)
3. **Confer** (interactive) or **Decide** (auto) — user approves or agent decides autonomously
4. **Execute** — the agent-specific work
5. **Record** — reasoning posted as a ledger comment on the GitHub issue

Agents also check for user-defined domain agents at `~/.claude/agents/` and spawn them as subagents when relevant.

### Artifacts

All planning artifacts are stored as GitHub issues and comments — not files on disk:

- **Ingots** — comprehensive plans stored as GitHub issues labeled `type:ingot`
- **Ledger entries** — reasoning records stored as tagged comments (e.g., `**[Blacksmith Ledger]**`) on the relevant issue
- **Rework comments** — tagged with `**[Temperer]**`, addressed by prepending `✅`

### Issue Lifecycle

Issues flow through status labels. Agents own all label transitions.

```
status:ready → status:hammering → status:hammered → status:tempering → status:tempered → status:proving → status:proved
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

The Proof-Master does not send work back — it fixes test failures itself or escalates to `agent:needs-human`.

### Bootstrap (`forge init`)

Create a directory and run `forge init`. The bootstrap runs idempotent steps:

- Tool checks: Node.js >= 24, pnpm >= 9, gh CLI, Vercel CLI, python3
- Forge plugin verification
- Git init, GitHub repo, branch protection, production branch
- Label taxonomy (23 labels)
- Project registration in `~/.forge/config.json`

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
| `forge smelt` | Produce an ingot (interactive) |
| `forge auto-smelt` | Picks up oldest human-filed `type:feature` issue |
| `forge refine` | Create GitHub issues from an ingot (interactive) |
| `forge auto-refine` | Same, autonomous |
| `forge hammer` | Implement the current issue (interactive) |
| `forge auto-hammer` | Same, autonomous |
| `forge temper` | Review the current implementation (interactive) |
| `forge auto-temper` | Same, autonomous |
| `forge proof` | Validate and open a PR (interactive) |
| `forge auto-proof` | Same, autonomous |
| `forge hone` | Triage bugs or audit the codebase (interactive) |
| `forge auto-hone` | Triages oldest bug first, then audits |
| `forge stoke` | Process the issue queue autonomously |
| `forge cast` | Full autonomous cycle: smelt → refine → stoke → hone |

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
| `type:ingot` | Ingot from Smelter or Honer |
| `status:ready` | Ready for the Blacksmith to implement |
| `status:hammering` | Implementation in progress |
| `status:hammered` | Implementation complete, awaiting review |
| `status:tempering` | Review in progress |
| `status:tempered` | Review passed, awaiting validation |
| `status:rework` | Sent back to the Blacksmith |
| `status:proving` | Validation in progress |
| `status:proved` | PR opened |

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
│   └── forge-lib.sh                    #   Shared library (labels, helpers, query functions)
├── bootstrap/setup.sh                  # Idempotent project setup
├── plugin/                             # Claude Code plugin
│   ├── .claude-plugin/plugin.json      #   Plugin manifest
│   └── agents/                         #   Forge craftsman agents (interactive + auto)
├── tests/                              # CLI tests (bats framework)
└── .claude-plugin/marketplace.json     # Marketplace listing
```

## Design Decisions

**GitHub is the state machine.** No local workflow state, no database, no coordination server. All project state is encoded in GitHub Issue labels and comments. Clone the repo on a new Mac, run a forge command, and it picks up where it left off.

**Agents own their state.** Each agent sets its own status labels — the CLI is a thin dispatcher that finds issues and launches agents. If an agent crashes mid-run, the in-progress label (`status:hammering`, etc.) persists and `forge stoke` picks it back up.

**Agents, not skills.** Each craftsman is a Claude Code agent loaded via `claude --agent`. The CLI handles dispatch; the agent handles the work, including research (parallel Explore agents), planning (mandatory Plan agent), and label transitions.

**Ledger for reasoning.** Every craftsman records its decisions as tagged comments on GitHub issues. This creates an audit trail — when the Temperer reviews the Blacksmith's work, it can read *why* decisions were made, not just *what* was done.

**Dual artifact model.** The Smelter produces ingots (specifications). The Honer files both ingots (for broad gaps needing architecture) and implementation issues (for concrete fixes that go straight to the Blacksmith). The Refiner breaks ingots into issues regardless of who created them.

**Opinionated scope.** Next.js, Vercel, one developer. This is not a general-purpose framework — it's a sharp tool for a specific workflow.

## License

MIT
