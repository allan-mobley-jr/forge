#!/usr/bin/env python3
"""PostToolUse hook: rate-limit GitHub API mutations (1s pause)."""
import json
import sys
import time

d = json.load(sys.stdin)
cmd = d.get("tool_input", {}).get("command", "")

gh_mutations = [
    "gh issue create", "gh issue comment", "gh issue edit",
    "gh issue close", "gh issue develop",
    "gh pr create", "gh pr comment", "gh pr edit",
    "gh label create",
]

api_flags = [" -f ", " -X POST", " -X PATCH", " -X PUT", " -X DELETE"]

is_mutation = any(m in cmd for m in gh_mutations) or (
    "gh api" in cmd and any(f in cmd for f in api_flags)
)

if is_mutation:
    time.sleep(1)
