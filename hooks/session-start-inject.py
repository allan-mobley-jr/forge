#!/usr/bin/env python3
"""SessionStart hook: inject Forge project context into the session."""
import json
import os
import sys

plugin_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
claude_md_path = os.path.join(plugin_root, "CLAUDE.md.dist")

if not os.path.exists(claude_md_path):
    sys.exit(0)

with open(claude_md_path) as f:
    content = f.read()

print(json.dumps({"additionalContext": content}))
