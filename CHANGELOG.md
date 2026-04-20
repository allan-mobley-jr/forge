# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.8.0] - 2026-04-20

### Added
- Workshop state machine: 6 new `workshop:*` status labels (`workshop:hammering`, `workshop:hammered`, `workshop:reworked`, `workshop:tempering`, `workshop:tempered`, `workshop:rework`) mirroring the pipeline `status:*` lifecycle. Workshop issues still carry the `workshop` label and stay off the autonomous pipeline queue.
- Workshop agent split: 2 new dedicated rework agents (Workshop-Rework-Blacksmith, Workshop-Rework-Temperer) that resume the original workshop session with focused rework instructions when the issue is labeled `workshop:rework` or `workshop:reworked`.
- `classify_workshop_issue` helper in forge-lib.sh for workshop dispatch based on `workshop:*` labels. Mirrors `classify_issue_by_number`.
- Workshop prompt helpers (`_workshop_blacksmith_prompt_for_status`, `_workshop_rework_blacksmith_prompt_for_status`, `_workshop_temperer_prompt_for_status`, `_workshop_rework_temperer_prompt_for_status`) mirroring the Blacksmith prompt helpers.

### Changed
- **Breaking:** CLI workshop subcommand renamed from `new` to `workshop`. Use `forge hammer workshop` / `forge temper workshop` (and `... workshop sessions` for the session picker) in place of the old `new` subcommand. No alias — forge is pre-1.0.
- `forge hammer workshop` now dispatches Workshop-Blacksmith or Workshop-Rework-Blacksmith based on the `workshop:*` label on the associated issue. Fresh sessions start with the Workshop-Blacksmith's greet & discuss flow; `workshop:rework` routes to Workshop-Rework-Blacksmith to address Temperer feedback; `workshop:hammered` / `workshop:tempering` / `workshop:tempered` / `workshop:reworked` inform the user to run `forge temper workshop` instead.
- `forge temper workshop` now dispatches Workshop-Temperer or Workshop-Rework-Temperer based on the `workshop:*` label. `workshop:hammered` routes to first-pass Workshop-Temperer; `workshop:reworked` routes to Workshop-Rework-Temperer. For the ambiguous labels `workshop:tempering` (interrupt-resume) and `workshop:tempered` (approved but PR/merge didn't complete), the CLI picks first-pass vs rework by counting prior ✅-addressed Temperer cycles, keeping the resumed session's conversation history aligned with the agent's system prompt. `workshop:rework` / `workshop:hammering` informs the user to run `forge hammer workshop`.
- Workshop-Blacksmith and Workshop-Temperer rewritten for first-pass only — rework detection, ledger templates, and rework-specific feedback reading moved to the new dedicated rework agents. Self-review is now called out as mandatory, and PR creation is strictly the Workshop-Temperer's responsibility.
- Workshop-Blacksmith framing updated from "discuss, file an issue, then implement" to "refine, fix, or reshape something you discovered while using the app." Major new features still point to `forge smelt`.
- `archive_closed_sessions` now runs at the top of `forge hammer workshop` and `forge temper workshop`, letting a just-merged workshop cycle cleanly to a fresh discussion on the next invocation.
- `update_workshop_session_issue` now also renames the session from its placeholder (`workshop-<role>-new`) to `workshop-<role>-issue-<N>` once an issue is filed, so the session picker can distinguish past workshops.

### Fixed
- Workshop-Blacksmith no longer conflates first-pass and rework modes. Previously, when the Workshop-Temperer sent work back, the Workshop-Blacksmith had no label to detect the rework and would typically mistake the second invocation for an interrupted first pass — skipping feedback reading and silently repeating the self-review. The new `workshop:rework` label plus dedicated Workshop-Rework-Blacksmith agent make the mode explicit end-to-end.

## [0.7.0] - 2026-04-14

### Added
- Rework agent split: 4 new dedicated agents (Rework-Blacksmith, auto-Rework-Blacksmith, Rework-Temperer, auto-Rework-Temperer) that resume the original session with focused rework instructions via `--agent` + `--resume`.
- Workshop mode (`forge hammer new` / `forge temper new`) for ad-hoc interactive work outside the pipeline queue. Workshop issues use a `workshop` label and stay off the state machine.
- Focused commands (`forge hammer <N>` / `forge temper <N>`) to target specific pipeline issues by number, bypassing the queue.
- `status:reworked` label in the state machine to distinguish rework completions from first-pass completions. Rework-Temperer picks up `status:reworked`; regular Temperer picks up `status:hammered`.
- `workshop` label for ad-hoc workshop issues.
- `classify_issue_by_number` helper in forge-lib.sh for focused command dispatch, with a drift-guard test ensuring its case arms stay in sync with `classify_lowest_open_issue`.
- Workshop session management (`get_workshop_session`, `set_workshop_session`, `update_workshop_session_issue`) stored under `sessions.workshop-*` in config.json. CLI auto-detects the workshop issue number after the Workshop-Blacksmith session exits.

### Changed
- First-pass Temperer now treats all findings as blocking — the approval gate is "zero findings" instead of "zero must-fix items." The must-fix vs non-blocker distinction now lives exclusively in the Rework-Temperer for subsequent passes.
- Temperer rework comment format changed from two tables (`Must-Fix Issues` + `Non-Blockers`) to a single `Issues Found` table on first pass.
- Existing Blacksmith/Temperer agents simplified to first-pass only — rework detection, human recovery, rework ledger templates, and "max rework cycles" rule moved to dedicated rework agents.
- Blacksmith "file out-of-scope features" rule replaced with "expand scope to fully implement" — build supporting functionality rather than filing follow-ups.
- Strengthened E2E testing language across all agents: thorough user-perspective walkthroughs of affected pages (edge cases, error states, adjacent functionality) instead of shallow spot checks.
- Stoke loop now routes `status:rework` to auto-Rework-Blacksmith and `status:reworked` to auto-Rework-Temperer.

### Fixed
- `run_forge_agent` now always passes `--agent` on resume (not just on fresh sessions). Previously, agent system prompts were lost when resuming sessions via `--resume`. This also enables cross-agent session resumption (e.g., Rework-Blacksmith resuming a Blacksmith session).

## [0.6.3] - 2026-04-10

### Fixed
- `forge deploy` no longer hard-errors when the production branch has diverged from main. Since production is solely a Vercel deployment trigger, the command now uses `--force-with-lease` to always update production to match main, handling setup artifacts gracefully.

## [0.6.2] - 2026-04-09

### Fixed
- Agent execution rule in all 12 craftsman agent files now bans ALL background agents — previously the rule said "research or planning" (or "research or review" in Temperer variants), leaving review agents uncovered. The Blacksmith was backgrounding its self-review agents and skipping `pr-test-analyzer` entirely. Blacksmith self-review step now explicitly requires all three review agents in a single foreground message.

### Added
- Version consistency test (`tests/cli/forge_lib.bats`) that asserts `plugin.json`, `marketplace.json` (both entries), and `CHANGELOG.md` all carry the same version string. Uses `jq -er` for null-safe extraction and semver-filtered CHANGELOG heading.

## [0.6.1] - 2026-04-08

### Added
- `forge hammer`, `forge auto-hammer`, and `run_stoke_loop` now pass status-specific prompts to the Blacksmith via a new shared `_blacksmith_prompt_for_status` helper. The rework path tells the agent to read every `[Temperer]` comment (must-fix AND non-blockers) and address every finding in one pass; the needs-human path frames the interactive recovery workflow; the hammering path explicitly names the interrupted-resume case. Unexpected status values fail loudly rather than silently degrading.
- Temperer agents (interactive + auto) now define an explicit Must-Fix vs Non-Blocker finding taxonomy. Must-fix items block approval; non-blockers do not.
- Temperer rework comments now include a `### Non-Blockers` table alongside `### Must-Fix Issues` when non-blocker findings exist.

### Changed
- Temperer must include **every** finding (must-fix AND non-blockers) in the REWORK comment rather than deferring "secondary" findings across cycles. Stops the Blacksmith from closing out work the Temperer still had concerns about.
- `classify_lowest_open_issue` now emits a third tab-separated `<status>` field so callers can dispatch on the specific status label (previously collapsed into just a category).

## [0.6.0] - 2026-04-08

### Changed
- `forge hammer` and `forge temper` in interactive mode now deterministically dispatch on the **lowest open issue** via a new `classify_lowest_open_issue` helper (replacing `find_issue_for_hammer` and `find_issue_for_temper`) — no more session picker, no more silently skipping past stuck lower-numbered issues. When the lowest issue is in the wrong state, the CLI exits with a routed message pointing at the correct sibling command (`forge temper`, `forge smelt`, or `forge hone`).
- `agent:needs-human` renamed to `status:needs-human` so every lifecycle label lives in the `status:*` namespace. `check_labels` runs a one-time in-place rename via `gh label edit --name` that preserves every existing issue association, and loudly reports any failure. External tooling referencing `agent:needs-human` by name must update to `status:needs-human`; issue associations migrate automatically.

## [0.5.2] - 2026-04-06

### Changed
- Blacksmith protected files narrowed to just `GRADING_CRITERIA.md` — the Blacksmith now owns the entire project repo and can update CLAUDE.md, `.claude/`, `.github/workflows/`, and `.env*` files as needed. Only the Temperer's scoreboard remains hard-protected.
- Blacksmith ledger now requires recording gitignored file writes (`.env.local`, `.claude/settings.local.json`, etc.) with a `(gitignored)` marker — these don't appear in `git diff` so the ledger is the only audit trail.
- Temperer (interactive + auto) now explicitly reviews `CLAUDE.md` diffs as meta-changes that affect future Blacksmith runs.

## [0.5.1] - 2026-04-06

### Added
- `Skill` tool added to all agent allowedTools so agents can deterministically invoke skills (frontend-design, marketplace, vercel-storage, etc.) instead of relying on auto-loading or manual file reads

### Changed
- Smelter monorepo Vercel infrastructure now consolidates into a mandatory restructure issue (the first implementation issue) instead of being scattered across per-hub issues. INGOT.md gains required Shared Resource Provisioning and Per-Hub Vercel Project Setup subsections. Auto-Smelter ledger records the Vercel infrastructure anchor issue number.

### Fixed
- `run_forge_agent` now fails loudly when an agent file exists but yields no extractable tools, preventing silent `--allowedTools` omission that would cause headless agents to hang

## [0.5.0] - 2026-04-06

### Added
- `forge <command> sessions` — browse all sessions including archived for any craftsman (smelt, hammer, temper, hone)
- Auto-prune of closed-issue sessions from the normal session picker — closed issues are archived (not deleted) so they can still be browsed via the sessions command
- `archived` flag on session history entries; `get_session` skips archived sessions so auto/stoke/cast won't resume stale work

### Changed
- `pick_session` and `list_sessions` now accept a mode parameter (`all` to include archived sessions)

## [0.4.5] - 2026-04-06

### Fixed
- Smelter monorepo Vercel setup — single-app projects get linked at scaffold time; monorepos defer all Vercel project creation to per-app issues with `sourceFilesOutsideRootDirectory` and shared resource acceptance criteria
- Agents now post ledger comments before transitioning status labels — if interrupted, the reasoning is preserved and the label can be flipped on resume

### Changed
- Hardcoded production branch API endpoint removed from Smelter — agents now use Vercel MCP tools or web search for current correct method

## [0.4.4] - 2026-04-06

### Added
- All agents now auto-approve MCP tools from installed plugins (`mcp__*` wildcard in `--allowedTools`) — eliminates permission prompts for Vercel plugin operations

## [0.4.3] - 2026-04-06

### Fixed
- Agent definitions now load correctly for interactive sessions — preserve original agent name casing for `--agent` flag and place interactive prompt before flags

## [0.4.2] - 2026-04-06

### Fixed
- Session picker TUI now renders correctly — output redirected to stderr so command substitution doesn't swallow the interactive display

### Added
- Configuration section in README documenting `forge config model` and extended context window usage (`claude-opus-4-6[1m]`)

## [0.4.1] - 2026-04-06

### Fixed
- Interactive agent sessions (`forge smelt`, `forge hammer`, `forge temper`, `forge hone`) now stay interactive — prompt is passed as a positional argument instead of `-p` (headless mode)
- `feature-dev` and `frontend-design` plugins added to managed dependencies in `install.sh` and `forge update` — these were already referenced by agents but missing from the install chain; Blacksmith now references the `frontend-design` skill for UI implementation

## [0.4.0] - 2026-04-04

### Added
- agent-browser CLI replaces Playwright MCP for browser automation — 80-90% fewer tokens per page snapshot, installed globally via `npm install -g agent-browser`
- agent-browser reference docs downloaded to `~/.forge/docs/` during install and update
- `forge doctor` reports agent-browser CLI and docs status

### Changed
- Node.js >= 24 is now verified during installation (previously only checked during `forge init`)

### Fixed
- Add missing Issue Ownership section to auto-honer-audit agent
- Reorder Issue Ownership section in auto-blacksmith and auto-temperer agents for consistency
- Add `json.JSONDecodeError` handling to all JSON config parsing
- Fix `clear_issue_sessions` silently swallowing errors
- README rework cycle limit corrected from 5 to 7
- README label count corrected from 22 to 21

### Removed
- Playwright MCP no longer installed, cached, or checked by Forge
- Dead `find_issue_for_temper_recovery` function removed

> **Upgrading from v0.3.0:** Run `forge update` to install agent-browser and download its documentation. Node.js >= 24 is now required.

## [0.3.0] - 2026-04-03

### Added
- Smelter split into 4 agents: bootstrap (scaffold, Vercel, INGOT.md) and feature (plan within existing architecture), each with interactive and auto variants
- Honer split into 4 agents: bug triage and audit, each with interactive and auto variants
- Per-project model pinning via `forge config model` — prevents accidental model drift across pipeline runs
- Project state detection for automatic agent routing (empty project → bootstrap, has bugs → triage, otherwise → audit/feature)
- Blacksmith reads GRADING_CRITERIA.md during implementation, runs local E2E tests via Playwright MCP, maintains README
- Temperer evaluates against GRADING_CRITERIA.md with Quality Assessment in ledger, manages releases after merges
- Honer two-pass audit: technical (tests, lint, build) + UX/design (browse app as user) against grading criteria
- Issue-scoped sessions with descriptive names and crash recovery for all agents

### Changed
- Blacksmith uses code-explorer for codebase research, code-architect as devil's advocate (drafts first, then challenges)
- Temperer reframed as evaluator — browses the app as a user, no pr-review-toolkit subagents
- Honer evaluates directly — no pr-review-toolkit subagents, reads previous ledgers before flagging problems
- All agents: Plan agent role changed to devil's advocate (agent drafts, Plan challenges)
- Sessions scoped to individual issues instead of milestones
- Rework cycle limit increased from 5 to 7
- Branch protection simplified: removed required CI checks and Copilot review (all testing is local)
- Pipeline reduced from 6 craftsmen to 4: Smelter, Blacksmith, Temperer, Honer
- Issue body format simplified to Objective + Acceptance Criteria only (no Technical Notes or Dependencies)

### Removed
- Scribe agent — README maintenance moved to Blacksmith
- Proof-Master agent — release management absorbed by Temperer
- `forge proof`, `forge auto-proof`, `forge scribe`, `forge auto-scribe` commands

### Fixed
- Defensive status label transitions prevent stale label accumulation from interrupted transitions
- Stoke loop crash with "Issue #null" when all status issues are resolved

## [0.2.2] - 2026-03-31

### Fixed
- Resumed sessions now pass `--allowedTools` to prevent infinite permission-denial loops in headless mode

## [0.2.1] - 2026-03-31

### Added
- Smelter writes INGOT.md and GRADING_CRITERIA.md directly to main on first run, replacing the ingot issue convention
- Honer adjusts GRADING_CRITERIA.md after audits, closing the evaluator tuning loop
- Temperer evaluates against GRADING_CRITERIA.md alongside issue acceptance criteria
- Smelter scope ambition, design altitude, and feature-level sizing prompts for higher-quality planning
- Blacksmith appends dated entries to INGOT.md when making significant architectural decisions

### Fixed
- UUID-based session IDs for headless resume — `--session-id` on first launch, `--resume` on subsequent
- Double divider output between stoke loop passes
- Temperer now removes `status:tempered` label after merge

### Changed
- Removed `type:ingot` label — no agent creates ingot issues anymore

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

[0.8.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.8.0
[0.7.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.7.0
[0.6.3]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.6.3
[0.6.2]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.6.2
[0.6.1]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.6.1
[0.6.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.6.0
[0.5.2]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.5.2
[0.5.1]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.5.1
[0.5.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.5.0
[0.4.5]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.4.5
[0.4.4]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.4.4
[0.4.3]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.4.3
[0.4.2]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.4.2
[0.4.1]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.4.1
[0.4.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.4.0
[0.3.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.3.0
[0.2.2]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.2.2
[0.2.1]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.2.1
[0.2.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.2.0
[0.1.3]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.3
[0.1.2]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.2
[0.1.1]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.1
[0.1.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.0
