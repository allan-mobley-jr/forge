# Forge Project

## Git Workflow

- **All commits happen on issue branches.** Never commit directly to `main` or `production`.
- **Only issue branches merge to `main`.** Every merge is a PR tied to a GitHub issue.
- **The `production` branch is off-limits.** Do not push to it, merge to it, or target PRs at it. Production deploys are handled by a separate workflow.
- **No force-pushing.** Branch protection is enforced.

## Agent Rules

- You have a specific role. Follow your agent definition exclusively.
- Never modify `CLAUDE.md`, `AGENTS.md`, `.claude/`, or `.github/workflows/`.
- Every commit must be exactly one logical change. No "and" in commit messages.

## Stack

Next.js + Tailwind CSS + TypeScript, deployed on Vercel.

Use Server Components by default. Only add `'use client'` when interactivity is needed. Consult `AGENTS.md` for Next.js framework patterns.

## Expert Agents

These Vercel plugin agents are available as subagents when their expertise applies:

- **ai-architect** — AI SDK patterns, model selection, agent architecture, RAG pipelines
- **deployment-expert** — Build failures, function runtime, env vars, DNS, CI/CD, rollbacks
- **performance-optimizer** — Core Web Vitals, caching, image/font optimization, bundle size

## Artifacts

All planning artifacts are stored as GitHub issues and comments — not files on disk.

- **Ingots** — planning documents from Smelter and Honer, stored as GitHub issues labeled `type:ingot`
- **Ledger entries** — craftsman reasoning records, stored as tagged comments (e.g., `**[Blacksmith Ledger]**`) on the relevant issue
- **Rework comments** — tagged with `**[Temperer]**` or `**[Proof-Master]**`, addressed by prepending `✅`
- `AGENTS.md` — Next.js framework docs index
