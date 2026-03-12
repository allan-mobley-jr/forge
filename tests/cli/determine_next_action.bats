#!/usr/bin/env bats
# Tests for determine_next_action() — the forge run state machine (4-pipeline architecture).
# Each test mocks `gh` to simulate a specific GitHub state and verifies the output.
#
# Mock patterns use "--label <name>" to avoid false matches against jq expressions
# that also contain label names (e.g., the backlog query's exclusion filter).

load "../helpers/setup"

# --- smelt: first run (zero issues) ---

@test "smelt on first run (no issues exist)" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "0"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "smelt" ]]
}

# --- smelt: smelting tracking issue exists ---

@test "smelt when smelting tracking issue exists" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo "3"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "smelt:3" ]]
}

# --- temper: agent:tempering issue exists ---

@test "temper when agent:tempering issue exists" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo "10"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "temper:10" ]]
}

# --- revise: CHANGES_REQUESTED on PR ---

@test "revise when PR has CHANGES_REQUESTED" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo "10"; exit 0; fi
        if [[ "$args" == *"pr list"*"reviewDecision"* ]]; then echo "CHANGES_REQUESTED"; exit 0; fi
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
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo "15"; exit 0; fi
        if [[ "$args" == *"pr list"*"reviewDecision"* ]]; then echo "APPROVED"; exit 0; fi
        if [[ "$args" == *"pr list"*"number"* ]]; then echo "20"; exit 0; fi
        if [[ "$args" == *"pr checks"* ]]; then echo "CI	fail	1234	https://example.com"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "revise:15" ]]
}

# --- hammer: resume agent:hammering issue ---

@test "hammer when agent:hammering issue exists" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:hammering"* ]]; then echo "7"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "hammer:7" ]]
}

# --- hammer: claim unclaimed backlog issue ---

@test "hammer when unclaimed ai-generated issue exists" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:hammering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"*"number,labels"* ]]; then echo "42"; exit 0; fi
        if [[ "$args" == *"issue edit"* ]]; then exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "hammer:42" ]]
}

# --- hone: honing tracking issue exists ---

@test "hone when honing tracking issue exists" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:hammering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"*"number,labels"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label honing"* ]]; then echo "15"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "hone:15" ]]
}

# --- hone: no open ai-generated issues, no cooldown ---

@test "hone when no open ai-generated issues and no cooldown" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:hammering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"*"number,labels"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label honing"*"--state open"* ]] || [[ "$args" == *"--state open"*"--label honing"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"* ]]; then echo "0"; exit 0; fi
        if [[ "$args" == *"--state closed"* ]]; then echo ""; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "hone" ]]
}

# --- wait: honing cooldown (last honing <24h ago, filed nothing) ---

@test "wait on honing cooldown when last cycle filed nothing" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "5"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:hammering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"*"number,labels"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--state open"*"--label honing"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"* ]]; then echo "0"; exit 0; fi
        if [[ "$args" == *"closedAt"* ]]; then echo "2099-01-01T00:00:00Z"; exit 0; fi
        if [[ "$args" == *"--state closed"*"--json number"* ]]; then echo "20"; exit 0; fi
        if [[ "$args" == *"issue view"* ]]; then echo "1"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "wait" ]]
}

# --- route: needs-human with human response routes by pipeline label ---

@test "route needs-human response by pipeline label" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"*"--json number,comments"* ]]; then
            cat <<JSON
[{"number":7,"comments":[
  {"body":"## Agent Question\nWhat should I do?","createdAt":"2026-03-10T00:00:00Z"},
  {"body":"Do option A please","createdAt":"2026-03-10T01:00:00Z"}
]}]
JSON
            exit 0
        fi
        if [[ "$args" == *"issue edit"* ]]; then exit 0; fi
        if [[ "$args" == *"issue view"* ]]; then echo "agent:hammering"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "hammer:7" ]]
}

# --- wait: agent:done PR awaiting merge (approved, CI passing) ---

@test "wait when agent:done PR awaits merge (approved, CI passing)" {
    ensure_jq
    mock_gh_with '
        args="$*"
        if [[ "$args" == *"--label agent:needs-human"* ]]; then echo "[]"; exit 0; fi
        if [[ "$args" == *"--state all"* ]]; then echo "10"; exit 0; fi
        if [[ "$args" == *"--label smelting"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:tempering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label agent:done"* ]]; then echo "20"; exit 0; fi
        if [[ "$args" == *"pr list"*"reviewDecision"* ]]; then echo "APPROVED"; exit 0; fi
        if [[ "$args" == *"pr list"*"number"* ]]; then echo "30"; exit 0; fi
        if [[ "$args" == *"pr checks"* ]]; then echo "CI	pass	1234	https://example.com"; exit 0; fi
        if [[ "$args" == *"--label agent:hammering"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"*"number,labels"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--state open"*"--label honing"* ]]; then echo ""; exit 0; fi
        if [[ "$args" == *"--label ai-generated"* ]]; then echo "1"; exit 0; fi
        echo ""
    '

    run determine_next_action
    [[ "$output" == "wait" ]]
}
