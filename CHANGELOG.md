# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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

[0.1.0]: https://github.com/allan-mobley-jr/forge/releases/tag/v0.1.0
