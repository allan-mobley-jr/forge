#!/usr/bin/env python3
"""PreToolUse hook: block access to protected files and paths."""
import json
import os
import sys

d = json.load(sys.stdin)
p = d.get("tool_input", {}).get("file_path", "")
if not p:
    sys.exit(0)

ap = os.path.abspath(p)
basename = os.path.basename(ap)
tool = d.get("tool_name", "")

# Exact filenames — always blocked
blocked_exact = {".env", ".env.local", ".env.production", ".env.development"}

# Directory segments — always blocked
blocked_dirs = [".git/", "node_modules/", ".vercel/"]

# Filenames — always blocked
blocked_names = {"CLAUDE.md", "AGENTS.md"}

# Path prefixes — always blocked
blocked_prefixes = [".claude/skills/", ".claude/agents/"]

# Write-only protections
write_protected = [".github/workflows/", "pnpm-lock.yaml"]

hit = (
    basename in blocked_exact
    or any(("/" + b) in (ap + "/") for b in blocked_dirs)
    or basename in blocked_names
    or any(b in ap for b in blocked_prefixes)
)

# Additional write-only checks
if not hit and tool in ("Write", "Edit", "MultiEdit"):
    hit = any(x in p for x in write_protected)

sys.exit(2 if hit else 0)
