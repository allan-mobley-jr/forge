# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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

[0.1.1]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.1
[0.1.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.0
