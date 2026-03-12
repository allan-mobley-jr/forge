#!/usr/bin/env bats
# Tests for determine_next_action() — the forge run state machine.
# Each test mocks `gh` to simulate a specific GitHub state and verifies the output.

load "../helpers/setup"

# --- done: all issues closed ---

@test "done when no open issues and issues exist" {
    ensure_jq
    mock_gh_with '
        args="$*"
        # needs-human query returns empty
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        # agent:done query returns empty
        if [[ "$args" == *"agent:done"* ]]; then
            echo ""; exit 0
        fi
        # stage label query returns empty
        if [[ "$args" == *"--json number,labels"*"--jq"* ]]; then
            echo ""; exit 0
        fi
        # backlog query returns empty
        if [[ "$args" == "issue list --state open --json number,labels -L 200 --jq"* ]]; then
            echo ""; exit 0
        fi
        # all issues count (state all) — some exist
        if [[ "$args" == *"--state all"* ]]; then
            echo "5"; exit 0
        fi
        # open count
        if [[ "$args" == *"--state open --json number -L 200"* ]]; then
            echo "0"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "done" ]]
}

# --- create: first run (zero issues) ---

@test "create on first run (no issues exist)" {
    ensure_jq
    mock_gh_with '
        args="$*"
        # needs-human query returns empty
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        # agent:done returns empty
        if [[ "$args" == *"agent:done"* ]]; then
            echo ""; exit 0
        fi
        # stage/backlog queries return empty
        if [[ "$args" == "issue list --state open --json number,labels"* ]]; then
            echo ""; exit 0
        fi
        # all issues count = 0
        if [[ "$args" == *"--state all"* ]]; then
            echo "0"; exit 0
        fi
        # issue create succeeds
        if [[ "$args" == *"issue create"* ]]; then
            exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "create" ]]
}

# --- create: planning issue exists ---

@test "create when planning issue exists" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        if [[ "$args" == *"agent:done"* ]]; then
            echo ""; exit 0
        fi
        if [[ "$args" == "issue list --state open --json number,labels"* ]]; then
            echo ""; exit 0
        fi
        # all issues count = 1
        if [[ "$args" == *"--state all"* ]]; then
            echo "1"; exit 0
        fi
        # planning issue exists
        if [[ "$args" == *"agent:planning"* ]]; then
            echo "1"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "create" ]]
}

# --- resolve: backlog issue (no agent labels) ---

@test "resolve backlog issue" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        if [[ "$args" == *"agent:done"* ]]; then
            echo ""; exit 0
        fi
        # stage label query — no stage issues
        if [[ "$args" == *"any(startswith"* ]]; then
            echo ""; exit 0
        fi
        # backlog query — issue 42 has no agent labels
        if [[ "$args" == *"all("* ]]; then
            echo "42"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "resolve:42" ]]
}

# --- revise: CHANGES_REQUESTED on PR ---

@test "revise when PR has CHANGES_REQUESTED" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        # agent:done returns issue 10
        if [[ "$args" == *"agent:done"*"--jq"* ]]; then
            echo "10"; exit 0
        fi
        # PR review decision
        if [[ "$args" == *"pr list"*"reviewDecision"* ]]; then
            echo "CHANGES_REQUESTED"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "revise:10" ]]
}

# --- revise: CI failure ---

@test "revise when PR has CI failure" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        if [[ "$args" == *"agent:done"*"--jq"* ]]; then
            echo "15"; exit 0
        fi
        # PR review — approved (not changes requested)
        if [[ "$args" == *"pr list"*"reviewDecision"* ]]; then
            echo "APPROVED"; exit 0
        fi
        # PR number
        if [[ "$args" == *"pr list"*"number"* ]]; then
            echo "20"; exit 0
        fi
        # PR checks — has a failure
        if [[ "$args" == *"pr checks"* ]]; then
            echo "CI	fail	1234	https://example.com"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "revise:15" ]]
}

# --- resolve: human responded to needs-human ---

@test "resolve when human responds to needs-human issue" {
    ensure_jq
    mock_gh_with '
        args="$*"
        # needs-human query: issue 7 with agent question + human reply
        if [[ "$args" == *"agent:needs-human"*"--json number,comments"* ]]; then
            cat <<JSON
[{"number":7,"comments":[
  {"body":"## Agent Question\nWhat should I do?","createdAt":"2026-03-10T00:00:00Z"},
  {"body":"Do option A please","createdAt":"2026-03-10T01:00:00Z"}
]}]
JSON
            exit 0
        fi
        # issue edit (remove label) — just succeed
        if [[ "$args" == *"issue edit"* ]]; then
            exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "resolve:7" ]]
}

# --- wait: needs-human with no response ---

@test "wait when needs-human has no human response" {
    ensure_jq
    mock_gh_with '
        args="$*"
        # needs-human: issue 9, only agent comment, recent (no timeout)
        if [[ "$args" == *"agent:needs-human"*"--json number,comments"* ]]; then
            cat <<JSON
[{"number":9,"comments":[
  {"body":"## Agent Question\nWhat should I do?","createdAt":"2099-01-01T00:00:00Z"}
]}]
JSON
            exit 0
        fi
        # agent:done — none
        if [[ "$args" == *"agent:done"* ]]; then
            echo ""; exit 0
        fi
        # stage/backlog queries — empty
        if [[ "$args" == "issue list --state open --json number,labels"* ]]; then
            echo ""; exit 0
        fi
        # all issues > 1
        if [[ "$args" == *"--state all"* ]]; then
            echo "5"; exit 0
        fi
        # open issues exist
        if [[ "$args" == *"--state open --json number -L 200"* ]]; then
            echo "1"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "wait" ]]
}

# --- create: resume interrupted creating pipeline ---

@test "create when interrupted creating stage found" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        if [[ "$args" == *"agent:done"* ]]; then
            echo ""; exit 0
        fi
        # stage label query — issue 3 has agent:create-researcher
        if [[ "$args" == *"any(startswith"* ]]; then
            echo "3"; exit 0
        fi
        # issue view — show the label
        if [[ "$args" == *"issue view"*"--json labels"* ]]; then
            echo "agent:create-researcher"; exit 0
        fi
        # issue edit (remove stale label)
        if [[ "$args" == *"issue edit"* ]]; then
            exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "create" ]]
}

# --- resolve: resume interrupted resolving pipeline ---

@test "resolve when interrupted resolving stage found" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        if [[ "$args" == *"agent:done"* ]]; then
            echo ""; exit 0
        fi
        # stage label query — issue 5 has agent:resolve-implementor
        if [[ "$args" == *"any(startswith"* ]]; then
            echo "5"; exit 0
        fi
        # issue view — show the label
        if [[ "$args" == *"issue view"*"--json labels"* ]]; then
            echo "agent:resolve-implementor"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "resolve:5" ]]
}

# --- wait: agent:done PR awaiting merge ---

@test "wait when agent:done PR awaits merge (approved, CI passing)" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"agent:needs-human"* ]]; then
            echo "[]"; exit 0
        fi
        # agent:done — issue 20
        if [[ "$args" == *"agent:done"*"--jq"* ]]; then
            echo "20"; exit 0
        fi
        # PR review — approved
        if [[ "$args" == *"pr list"*"reviewDecision"* ]]; then
            echo "APPROVED"; exit 0
        fi
        # PR number
        if [[ "$args" == *"pr list"*"number"* ]]; then
            echo "30"; exit 0
        fi
        # CI passing (no failures)
        if [[ "$args" == *"pr checks"* ]]; then
            echo "CI	pass	1234	https://example.com"; exit 0
        fi
        # stage/backlog — empty
        if [[ "$args" == "issue list --state open --json number,labels"* ]]; then
            echo ""; exit 0
        fi
        # all issues > 1
        if [[ "$args" == *"--state all"* ]]; then
            echo "10"; exit 0
        fi
        # open count > 0
        if [[ "$args" == *"--state open --json number -L 200"* ]]; then
            echo "1"; exit 0
        fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "wait" ]]
}
