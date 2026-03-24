#!/usr/bin/env python3
"""Stop hook: clean up session log."""
import os

session_log = ".forge-temp/session.log"
if os.path.exists(session_log):
    os.remove(session_log)
