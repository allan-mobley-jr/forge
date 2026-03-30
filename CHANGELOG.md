# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-03-30

### Added
- Named session history with interactive arrow-key picker for all commands
- Milestone-scoped session resume (CLI resumes context on crash/relaunch)
- INGOT.md as persistent codebase artifact (materialized from ingot by first Blacksmith issue)
- Smelter handles Vercel environment setup on first run (production + staging environments, env vars, Neon database branching)
- CLI session helpers: `pick_session`, `list_sessions`, `set_session`, `get_session`, `clear_session`, `clear_all_sessions`
- `find_issue_for_temper_recovery` for status:tempered PR/merge recovery
- `sessions` field in bootstrap project config

### Changed
- Rework pipeline from 7 agents to 3 core + 3 post-cycle agents (Smelter/Blacksmith/Temperer + Proof-Master/Honer/Scribe)
- Smelter absorbs Refiner — plans and creates implementation issues in one session
- Temperer absorbs Proof-Master PR/merge — lean review with E2E tests, opens PR, squash-merges
- Proof-Master rewritten as release manager — analyzes commits, determines semver, builds changelog, creates GitHub releases
- Honer files implementation issues directly instead of ingots (milestone-grouped for larger gaps)
- Blacksmith reads INGOT.md for architectural context before implementation
- Blacksmith self-review proportional to change complexity (mandatory for substantial, optional for small)
- Enriched ledgers with Key Decisions and Approaches Rejected sections
- Stoke/cast loop simplified to 3-agent state machine with milestone-scoped session resume
- Cast post-cycle order: Honer → Scribe → Proof-Master (was Proof-Master first)
- Cast loop resilient to interruption via GitHub history check
- Issue ownership enforcement on all agents (auto: skip non-owner, interactive: flag + approve)
- `type:ingot` label scoped to one-time Smelter specification

### Removed
- Refiner agent (merged into Smelter)
- `forge refine` / `forge auto-refine` commands
- `status:proving` and `status:proved` labels (24 → 22)
- Copilot review workflow from all agents
- Vercel deployment from Proof-Master
- Proof-Master ledger comment (release notes and changelog are its artifacts)
- `find_issue_for_proof` and `find_unprocessed_ingots` CLI functions
- `forge_status_transition` CLI output

## [0.1.3] - 2026-03-28

### Added
- Scribe agent — new craftsman that audits documentation and maintains the GitHub Wiki
- Proof-Master milestone-gated actions — Vercel project setup and GitHub releases when milestones complete
- Stoke agents file out-of-scope findings as GitHub issues instead of only noting them in ledgers
- Refiner applies `scope:*` labels to implementation issues
- Per-agent bracket/message colors, visual separators between agent passes, status transition lines, contextual spinner, and cast completion summary

### Fixed
- Consistent label transition ordering (action before ledger) and status label cleanup on issue close

## [0.1.2] - 2026-03-28

### Added
- Colored message text — DIM for in-progress, GREEN for success, RED for failure
- Braille spinner during headless agent execution showing activity during startup
- Already-addressed handling codified in all six craftsman agents — when acceptance criteria are already met, the pipeline passes through with ledgers and closes the issue without a PR

### Fixed
- Test suite no longer clobbers real `~/.forge/config.json` — introduced `FORGE_CONFIG_DIR` for test isolation

## [0.1.1] - 2026-03-27

### Added
- Colorized agent labels and structured console output — agent messages display with orange brackets (e.g., `[ BLACKSMITH ]`), success with green `✓`, failure with red `✗`

### Fixed
- Stoke loop now passes specific issue number to agents, preventing the Blacksmith from working on the wrong issue
- Smelter now closes source feature issue after creating ingot, preventing duplicate smelting
- Cast loop uses priority-based dispatch (status issues → stoke, ingots → refine, features → smelt) instead of running all phases in fixed order
- Cast exits on stoke failure instead of silently continuing to the Honer
- Added SIGINT trap so CTRL+C stops forge immediately
- Installer banner uses orange color matching the CLI

## [0.1.0] - 2026-03-26

### Added
- Forge CLI with pipeline commands (smelt, refine, hammer, temper, proof, hone, stoke, cast) and setup commands (init, deploy, doctor, update, version, help, uninstall)
- Six craftsman agents — Smelter, Refiner, Blacksmith, Temperer, Proof-Master, Honer — each with interactive and auto variants
- Claude Code plugin with marketplace listing
- Idempotent project bootstrap (`forge init`) with `--resume` recovery
- GitHub-as-state-machine: 23-label taxonomy, issue lifecycle, and ledger-based reasoning audit trail
- `forge stoke` queue dispatcher and `forge cast` full autonomous cycle
- `forge deploy` for human-controlled production releases
- `curl | bash` installer with Vercel plugin and Playwright MCP setup

[0.2.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.2.0
[0.1.3]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.3
[0.1.2]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.2
[0.1.1]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.1
[0.1.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.0
