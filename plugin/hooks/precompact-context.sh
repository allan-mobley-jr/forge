#!/usr/bin/env bash
# PreCompact hook: recover Forge context after compaction.
echo '--- FORGE CONTEXT RECOVERY ---'
echo 'You are running as a Forge pipeline stage.'
if [ -f .forge-temp/current-issue ]; then
    echo "Working on issue #$(cat .forge-temp/current-issue)"
fi
echo 'Complete your current stage task and post the output comment.'
echo '--- END RECOVERY ---'
