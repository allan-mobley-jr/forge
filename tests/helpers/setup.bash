#!/usr/bin/env bash
# Shared test setup for Forge CLI tests.
# Sources forge-lib.sh with mocked externals.

FORGE_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Create a temp directory for mock binaries and test state
setup() {
    TEST_TMPDIR="$(mktemp -d)"
    MOCK_BIN="$TEST_TMPDIR/bin"
    mkdir -p "$MOCK_BIN"

    # Put mock bin first on PATH so mocks override real commands
    export PATH="$MOCK_BIN:$PATH"

    # Create a fake FORGE_REPO so forge-lib.sh can source
    export FORGE_REPO="$TEST_TMPDIR/forge-repo"
    mkdir -p "$FORGE_REPO"
    git -C "$FORGE_REPO" init --quiet
    git -C "$FORGE_REPO" config user.name "forge-test"
    git -C "$FORGE_REPO" config user.email "forge-test@example.com"
    git -C "$FORGE_REPO" commit --allow-empty -m "init" --quiet

    # Disable colors for cleaner test output
    export RED="" GREEN="" YELLOW="" ORANGE="" BLUE="" BOLD="" DIM="" NC=""

    # Source the library under test
    source "$FORGE_TEST_DIR/bin/forge-lib.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# --- Mock helpers ---

# Create a mock `gh` that dispatches based on arguments.
# Usage: mock_gh_with <script-body>
# The script receives all gh arguments as $@.
mock_gh_with() {
    cat > "$MOCK_BIN/gh" <<MOCK_SCRIPT
#!/usr/bin/env bash
$1
MOCK_SCRIPT
    chmod +x "$MOCK_BIN/gh"
}

# Create a mock `claude` that dispatches based on arguments.
# Usage: mock_claude_with <script-body>
mock_claude_with() {
    cat > "$MOCK_BIN/claude" <<MOCK_SCRIPT
#!/usr/bin/env bash
$1
MOCK_SCRIPT
    chmod +x "$MOCK_BIN/claude"
}

# Create a minimal agent file for run_forge_agent to parse.
# Usage: _create_agent_file <agent-name>
_create_agent_file() {
    mkdir -p "$FORGE_REPO/plugin/agents"
    cat > "$FORGE_REPO/plugin/agents/$1.md" <<AGENT
---
name: $1
tools:
  - Bash
---
AGENT
}

# Ensure jq is available, otherwise skip the test.
ensure_jq() {
    if ! command -v jq &>/dev/null; then
        skip "jq is required for this test"
    fi
}
