#!/usr/bin/env python3
"""PostToolUse hook: log written file paths to session log."""
import json
import os
import sys

d = json.load(sys.stdin)
p = d.get("tool_input", {}).get("file_path", "")
if not p:
    sys.exit(0)

os.makedirs(".forge-temp", exist_ok=True)
with open(".forge-temp/session.log", "a") as f:
    f.write(p + "\n")
