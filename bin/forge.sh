#!/usr/bin/env bash
set -euo pipefail

FORGE_REPO="$HOME/.forge/repo"

if [ ! -d "$FORGE_REPO" ]; then
    echo "Error: Forge is not installed. Run:"
    echo '  curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash'
    exit 1
fi

# Source shared library (colors, helpers, state machine)
FORGE_LIB_DIR="${FORGE_LIB_DIR:-"$FORGE_REPO/bin"}"
# shellcheck source=bin/forge-lib.sh
source "${FORGE_LIB_DIR}/forge-lib.sh"

# Exit cleanly on CTRL+C (exit code 130 = 128 + SIGINT)
trap '_forge_spinner_stop; echo ""; echo -e "${RED}✗${NC} Interrupted."; exit 130' INT

show_banner() {
    local variant="${1:-main}"
    local version
    version=$(forge_version)

    printf '%b' "$ORANGE"
    cat <<'BANNER'

  ███████╗ ██████╗ ██████╗  ██████╗ ███████╗
  ██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
  █████╗  ██║   ██║██████╔╝██║  ███╗█████╗
  ██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
  ██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
  ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
BANNER
    printf '%b' "$NC"

    case "$variant" in
        stoke)
            echo -e "\n  ${BLUE}STOKE${NC}  Stoking the fire — processing the issue queue"
            ;;
        cast)
            echo -e "\n  ${BLUE}CAST${NC}  Full cast — smelt → stoke → proof → hone → scribe"
            ;;
        init)
            echo -e "\n  ${BLUE}INIT${NC}  Forging a new project"
            ;;
        *)
            echo -e "\n  Autonomous Next.js Development"
            ;;
    esac

    printf "  %-47s %s\n" "MIT License" "$version"
    echo
}

show_usage() {
    show_banner
    echo "Usage: forge <command>"
    echo ""
    echo "Pipeline commands:"
    echo "  smelt            Plan and create implementation issues"
    echo "  hammer           Implement the current issue"
    echo "  temper           Review, open PR, and merge"
    echo "  proof            Create a GitHub release"
    echo "  hone             Audit the codebase for improvements"
    echo "  scribe           Audit docs and update the GitHub Wiki"
    echo "  stoke            Autonomously process the issue queue"
    echo "  cast             Full autonomous cycle: smelt → stoke → proof → hone → scribe"
    echo ""
    echo "  Prefix 'auto-' for autonomous mode (e.g., forge auto-smelt)."
    echo ""
    echo "Operations:"
    echo "  deploy           Deploy main to production (human only)"
    echo ""
    echo "Setup commands:"
    echo "  init             Bootstrap a new Forge project"
    echo "  init --resume    Resume a failed or interrupted bootstrap"
    echo "  version          Show installed version and check for updates"
    echo "  update           Update Forge to the latest version"
    echo "  doctor           Check tool versions and project health"
    echo "  uninstall        Remove Forge from your system"
    echo ""
    echo "Run 'forge help <command>' for detailed help on a command."
    echo ""
    echo "Quick start:"
    echo "  1. mkdir my-app && cd my-app"
    echo "  2. forge init"
    echo "  3. forge smelt"
    echo "  4. forge stoke          (or forge cast for the full cycle)"
}

show_command_help() {
    case "${1:-}" in
        init)
            echo "forge init — Bootstrap a new Forge project"
            echo ""
            echo "Usage: forge init [--resume]"
            echo ""
            echo "Creates a new Forge project in the current directory:"
            echo "  1. Checks prerequisites (Node.js, pnpm, gh, vercel, python3)"
            echo "  2. Verifies Forge plugin is installed"
            echo "  3. Creates a GitHub repo with branch protection and labels"
            echo "  4. Sets up production branch"
            echo ""
            echo "Options:"
            echo "  --resume    Resume from where a previous bootstrap stopped"
            ;;
        version)
            echo "forge version — Show installed version"
            echo ""
            echo "Usage: forge version"
            echo ""
            echo "Shows the current Forge version and checks for updates."
            ;;
        update)
            echo "forge update — Update Forge itself"
            echo ""
            echo "Usage: forge update"
            echo ""
            echo "Pulls the latest version of Forge from GitHub and"
            echo "refreshes all plugins if an update is found."
            ;;
        doctor)
            echo "forge doctor — Health check"
            echo ""
            echo "Usage: forge doctor"
            echo ""
            echo "Checks tool versions, plugins, authentication, and labels."
            ;;
        deploy)
            echo "forge deploy — Deploy main to production"
            echo ""
            echo "Usage: forge deploy"
            echo ""
            echo "Fast-forwards the production branch to match main,"
            echo "triggering a Vercel production deployment."
            echo "Requires confirmation."
            ;;
        uninstall)
            echo "forge uninstall — Remove Forge"
            echo ""
            echo "Usage: forge uninstall"
            echo ""
            echo "Removes ~/.forge (repo + CLI binary) and PATH entries from"
            echo "shell config files. Does NOT affect existing Forge projects."
            ;;
        smelt|auto-smelt)
            echo "forge smelt — Plan and create implementation issues"
            echo ""
            echo "Usage: forge smelt"
            echo "       forge auto-smelt"
            echo ""
            echo "  smelt        Interactive — describe what you want, confer with the Smelter"
            echo "  auto-smelt   Autonomous — picks up the oldest human-filed type:feature issue"
            echo ""
            echo "The Smelter researches, plans, and creates sequenced implementation"
            echo "issues. On the first run, it also creates the project ingot (INGOT.md)."
            ;;
        hammer|auto-hammer)
            echo "forge hammer — Implement the current issue"
            echo ""
            echo "Usage: forge hammer"
            echo "       forge auto-hammer"
            echo ""
            echo "The Blacksmith picks up the lowest open issue (status:ready or"
            echo "status:rework) and implements it on a feature branch."
            ;;
        temper|auto-temper)
            echo "forge temper — Review, open PR, and merge"
            echo ""
            echo "Usage: forge temper"
            echo "       forge auto-temper"
            echo ""
            echo "The Temperer independently reviews the Blacksmith's work. If"
            echo "approved, opens a PR and merges it. If not, sends back for rework."
            ;;
        proof|auto-proof)
            echo "forge proof — Create a GitHub release"
            echo ""
            echo "Usage: forge proof"
            echo "       forge auto-proof"
            echo ""
            echo "The Proof-Master checks for unreleased work on main and creates"
            echo "a versioned release with changelog."
            ;;
        hone|auto-hone)
            echo "forge hone — Audit the codebase and file improvement issues"
            echo ""
            echo "Usage: forge hone"
            echo "       forge auto-hone"
            echo ""
            echo "  hone         Interactive — choose to triage a bug or audit the codebase"
            echo "  auto-hone    Autonomous — triages oldest bug first, then audits"
            ;;
        scribe|auto-scribe)
            echo "forge scribe — Audit docs and update the GitHub Wiki"
            echo ""
            echo "Usage: forge scribe"
            echo "       forge auto-scribe"
            echo ""
            echo "  scribe       Interactive — review docs with the user, get approval before changes"
            echo "  auto-scribe  Autonomous — audits docs and updates wiki headlessly"
            ;;
        stoke)
            echo "forge stoke — Autonomously process the issue queue"
            echo ""
            echo "Usage: forge stoke"
            echo ""
            echo "Processes one issue at a time: hammer → temper."
            echo "Uses named sessions for crash recovery and context preservation."
            echo "Exits when no actionable issues remain."
            ;;
        cast)
            echo "forge cast — Full autonomous cycle"
            echo ""
            echo "Usage: forge cast"
            echo ""
            echo "Runs the entire pipeline end-to-end:"
            echo "  smelt → stoke (hammer/temper) → proof → hone → scribe"
            echo ""
            echo "If the Honer produces new work, the cycle repeats."
            echo "Exits when no new work is generated."
            ;;
        *)
            echo "Unknown command: ${1:-}"
            echo ""
            echo "Run 'forge help' for a list of commands."
            ;;
    esac
}

case "${1:-}" in
    help)
        if [ -n "${2:-}" ]; then
            show_command_help "$2"
        else
            show_usage
        fi
        exit 0
        ;;
    version)
        local_tag=$(git -C "$FORGE_REPO" describe --tags --abbrev=0 2>/dev/null || true)
        local_sha=$(git -C "$FORGE_REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo "Forge ${local_tag:-$local_sha} ($local_sha)"

        # Update check: fetch tags, compare
        if git -C "$FORGE_REPO" fetch origin --tags --quiet 2>/dev/null; then
            latest_tag=$(git -C "$FORGE_REPO" tag -l 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
            if [ -n "$latest_tag" ] && [ "$latest_tag" != "$local_tag" ]; then
                echo -e "  ${YELLOW}Update available: ${local_tag:-dev} → $latest_tag${NC}"
                echo "  Run 'forge update'."
            elif [ -n "$latest_tag" ]; then
                echo -e "  ${GREEN}Up to date.${NC}"
            fi
        else
            echo -e "  ${DIM}(update check skipped — could not reach remote)${NC}"
        fi
        exit 0
        ;;
    init)
        FORGE_RESUME=false
        if [ "${2:-}" = "--resume" ]; then
            FORGE_RESUME=true
        fi

        show_banner init

        if [ -d ".git" ]; then
            if [ "$FORGE_RESUME" = true ]; then
                echo "  Resuming bootstrap..."
                echo ""
            else
                echo "Error: This directory is already a git repository."
                echo "  forge init is for new projects only."
                echo "  To resume a failed bootstrap, run:"
                echo "    forge init --resume"
                exit 1
            fi
        fi

        if [ "$FORGE_RESUME" = true ]; then
            exec "$FORGE_REPO/bootstrap/setup.sh" --resume
        else
            exec "$FORGE_REPO/bootstrap/setup.sh"
        fi
        ;;
    update)
        echo -e "${BLUE}Updating Forge...${NC}"
        git -C "$FORGE_REPO" fetch --quiet --tags
        local_head=$(git -C "$FORGE_REPO" rev-parse HEAD)
        # Prefer highest semver tag (not just nearest to HEAD), fall back to origin/main
        latest_tag=$(git -C "$FORGE_REPO" tag -l 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
        if [ -n "$latest_tag" ]; then
            git -C "$FORGE_REPO" checkout "$latest_tag" --quiet 2>/dev/null || {
                echo -e "${RED}Error:${NC} Failed to checkout $latest_tag in $FORGE_REPO."
                echo "  Check for uncommitted changes: git -C $FORGE_REPO status"
                exit 1
            }
        else
            git -C "$FORGE_REPO" reset --hard origin/main --quiet
        fi
        new_head=$(git -C "$FORGE_REPO" rev-parse HEAD)
        if [ "$local_head" = "$new_head" ]; then
            echo -e "${GREEN}Already up-to-date ($(forge_version)).${NC}"
        else
            echo -e "${GREEN}Forge updated to $(forge_version).${NC}"

            # Refresh plugin caches and reinstall
            echo -e "${BLUE}Refreshing plugins...${NC}"
            for plugin in forge vercel playwright; do
                for cache_dir in "$HOME/.claude/plugins/cache"/*/"$plugin"/*/; do
                    [ -d "$cache_dir" ] && rm -rf "$cache_dir"
                done
            done
            plugins=(
                "Forge|forge@forge"
                "Vercel|vercel@claude-plugins-official"
                "Playwright|playwright@claude-plugins-official"
                "PR Review Toolkit|pr-review-toolkit@claude-plugins-official"
            )
            for plugin_entry in "${plugins[@]}"; do
                display_name="${plugin_entry%%|*}"
                install_spec="${plugin_entry#*|}"
                if claude plugin install "$install_spec" 2>/dev/null; then
                    echo -e "  ${GREEN}✓${NC} $display_name plugin refreshed"
                else
                    echo -e "  ${YELLOW}!${NC} $display_name plugin failed. Run manually: claude plugin install $install_spec"
                fi
            done
        fi
        ;;
    doctor)
        require_forge_project

        echo ""
        echo "Forge Doctor"
        echo "============"
        echo ""

        echo "Tools:"

        if command -v node &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Node.js $(node --version 2>/dev/null)"
        else
            echo -e "  ${RED}✗${NC} Node.js not installed"
        fi

        if command -v pnpm &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} pnpm $(pnpm --version 2>/dev/null)"
        else
            echo -e "  ${RED}✗${NC} pnpm not installed"
        fi

        if command -v gh &>/dev/null; then
            if gh auth status &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} gh CLI $(gh --version 2>/dev/null | head -1 | awk '{print $3}') (authenticated)"
            else
                echo -e "  ${YELLOW}⚠${NC} gh CLI $(gh --version 2>/dev/null | head -1 | awk '{print $3}') (not authenticated)"
            fi
        else
            echo -e "  ${RED}✗${NC} gh CLI not installed"
        fi

        if command -v vercel &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Vercel CLI $(vercel --version 2>/dev/null | head -1)"
        else
            echo -e "  ${RED}✗${NC} Vercel CLI not installed"
        fi

        if command -v python3 &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} python3 $(python3 --version 2>&1 | awk '{print $2}')"
        else
            echo -e "  ${RED}✗${NC} python3 not installed (required; install with: brew install python3)"
        fi

        echo ""
        echo "Plugins:"

        if claude plugin list 2>/dev/null | grep -q "forge"; then
            echo -e "  ${GREEN}✓${NC} Forge plugin installed"
        else
            echo -e "  ${RED}✗${NC} Forge plugin not installed — run: claude plugin install forge@forge"
        fi

        if claude plugin list 2>/dev/null | grep -q "vercel"; then
            echo -e "  ${GREEN}✓${NC} Vercel plugin installed"
        else
            echo -e "  ${YELLOW}⚠${NC} Vercel plugin not installed"
        fi

        if claude mcp list 2>/dev/null | grep -q "playwright"; then
            echo -e "  ${GREEN}✓${NC} Playwright MCP installed"
        else
            echo -e "  ${YELLOW}⚠${NC} Playwright MCP not installed"
        fi

        echo ""
        echo "Connectivity:"

        if gh auth status &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} GitHub authenticated"
        else
            echo -e "  ${RED}✗${NC} GitHub not authenticated — run: gh auth login"
        fi

        if command -v vercel &>/dev/null; then
            if vercel whoami &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Vercel authenticated"
            else
                echo -e "  ${YELLOW}⚠${NC} Vercel not authenticated — run: vercel login"
            fi
        fi

        echo ""
        echo "Labels:"

        if gh auth status &>/dev/null; then
            required_labels=()
            for entry in "${FORGE_REQUIRED_LABELS[@]}"; do
                required_labels+=("${entry%%|*}")
            done
            existing_labels=$(gh label list --json name --jq '.[].name' -L 200 2>/dev/null || true)
            missing_labels=()

            for lbl in "${required_labels[@]}"; do
                if ! echo "$existing_labels" | grep -qx "$lbl"; then
                    missing_labels+=("$lbl")
                fi
            done

            if [ ${#missing_labels[@]} -eq 0 ]; then
                echo -e "  ${GREEN}✓${NC} All ${#required_labels[@]} required labels present"
            else
                echo -e "  ${YELLOW}⚠${NC} Missing ${#missing_labels[@]} label(s): ${missing_labels[*]}"
                echo "    Run 'forge init --resume' to create missing labels"
            fi
        else
            echo -e "  ${DIM}-${NC} Skipped (GitHub not authenticated)"
        fi

        echo ""
        echo "  Run 'forge update' to update Forge and its plugin."
        echo ""
        ;;
    # ==========================================================================
    # Craftsman commands — each invokes a named agent via claude --agent
    # ==========================================================================

    smelt|auto-smelt)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            # Short-circuit: no human-filed feature issues to smelt
            feature_issue=$(gh issue list --state open --label "type:feature" --json number,labels --jq '
                [.[] | select(.labels | map(.name) | any(. == "ai-generated") | not)] | sort_by(.number) | .[0].number // empty
            ' 2>/dev/null || true)
            if [ -z "$feature_issue" ]; then
                forge_info "No human-filed type:feature issues found."
                exit 0
            fi
            agent_msg SMELTER "Starting on issue #$feature_issue..."
            if ! run_forge_agent "auto-smelter" "Process the oldest human-filed type:feature issue. Research, plan, and create implementation issues."; then
                agent_fail SMELTER "failed."
                exit 1
            fi
        else
            # Check for resumable session
            resumed_session=$(pick_session "smelter")
            agent_msg SMELTER "Starting..."
            if [ -n "$resumed_session" ]; then
                if ! run_forge_agent "Smelter" "Continue where you left off." "" --resume-session "$resumed_session"; then
                    agent_fail SMELTER "failed."
                    exit 1
                fi
            else
                local session_id
                local session_name
                if [ -f INGOT.md ]; then
                    session_name="smelter-features"
                else
                    session_name="smelter-ingot"
                fi
                session_id=$(_forge_uuid)
                set_session "smelter" "$session_name" "$session_id" "" 2>/dev/null || true
                if ! run_forge_agent "Smelter" "Greet the user and begin." "" --session-id "$session_id" --session-name "$session_name"; then
                    agent_fail SMELTER "failed."
                    exit 1
                fi
            fi
        fi
        agent_ok SMELTER "complete. Run 'forge stoke' to start implementing."
        ;;

    hammer|auto-hammer)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        issue=$(find_issue_for_hammer)
        if [ -z "$issue" ]; then
            forge_info "No issues ready for hammering."
            exit 0
        fi

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            agent_msg BLACKSMITH "Starting on issue #$issue..."
            if ! run_forge_agent "auto-blacksmith" "Implement the next ready issue."; then
                agent_fail BLACKSMITH "failed on issue #$issue."
                exit 1
            fi
        else
            resumed_session=$(pick_session "blacksmith")
            agent_msg BLACKSMITH "Starting on issue #$issue..."
            if [ -n "$resumed_session" ]; then
                if ! run_forge_agent "Blacksmith" "Continue where you left off. Work on issue #${issue}." "" --resume-session "$resumed_session"; then
                    agent_fail BLACKSMITH "failed on issue #$issue."
                    exit 1
                fi
            else
                local session_id session_name="blacksmith-issue-${issue}"
                session_id=$(_forge_uuid)
                set_session "blacksmith" "$session_name" "$session_id" "$issue" 2>/dev/null || true
                if ! run_forge_agent "Blacksmith" "Read INGOT.md in the project root for architectural context before starting. Greet the user and begin." "" --session-id "$session_id" --session-name "$session_name"; then
                    agent_fail BLACKSMITH "failed on issue #$issue."
                    exit 1
                fi
            fi
        fi
        agent_ok BLACKSMITH "complete."
        ;;

    temper|auto-temper)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        issue=$(find_issue_for_temper)
        if [ -z "$issue" ]; then
            forge_info "No issues ready for tempering."
            exit 0
        fi

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            agent_msg TEMPERER "Starting on issue #$issue..."
            if ! run_forge_agent "auto-temperer" "Review the next hammered issue."; then
                agent_fail TEMPERER "failed on issue #$issue."
                exit 1
            fi
        else
            resumed_session=$(pick_session "temperer")
            agent_msg TEMPERER "Starting on issue #$issue..."
            if [ -n "$resumed_session" ]; then
                if ! run_forge_agent "Temperer" "Continue where you left off. Review issue #${issue}." "" --resume-session "$resumed_session"; then
                    agent_fail TEMPERER "failed on issue #$issue."
                    exit 1
                fi
            else
                local session_id session_name="temperer-issue-${issue}"
                session_id=$(_forge_uuid)
                set_session "temperer" "$session_name" "$session_id" "$issue" 2>/dev/null || true
                if ! run_forge_agent "Temperer" "Read INGOT.md in the project root for architectural context before starting. Greet the user and begin." "" --session-id "$session_id" --session-name "$session_name"; then
                    agent_fail TEMPERER "failed on issue #$issue."
                    exit 1
                fi
            fi
        fi
        agent_ok TEMPERER "complete."
        ;;

    proof|auto-proof)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            agent_msg PROOF-MASTER "Checking for unreleased work..."
            if ! run_forge_agent "auto-proof-master" "Check for unreleased work on main. If found, create a release." "Releasing..."; then
                agent_fail PROOF-MASTER "failed."
                exit 1
            fi
        else
            resumed_session=$(pick_session "proof-master")
            agent_msg PROOF-MASTER "Starting..."
            if [ -n "$resumed_session" ]; then
                if ! run_forge_agent "Proof-Master" "Continue where you left off." "" --resume-session "$resumed_session"; then
                    agent_fail PROOF-MASTER "failed."
                    exit 1
                fi
            else
                local current_tag
                current_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "initial")
                local session_id session_name="proof-master-${current_tag}"
                session_id=$(_forge_uuid)
                set_session "proof-master" "$session_name" "$session_id" "" 2>/dev/null || true
                if ! run_forge_agent "Proof-Master" "Greet the user and begin." "" --session-id "$session_id" --session-name "$session_name"; then
                    agent_fail PROOF-MASTER "failed."
                    exit 1
                fi
            fi
        fi
        agent_ok PROOF-MASTER "complete."
        ;;

    hone|auto-hone)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            agent_msg HONER "Starting..."
            if ! run_forge_agent "auto-honer" "Check for human-filed bugs first. If none, audit the codebase. File implementation issues."; then
                agent_fail HONER "failed."
                exit 1
            fi
        else
            resumed_session=$(pick_session "honer")
            agent_msg HONER "Starting..."
            if [ -n "$resumed_session" ]; then
                if ! run_forge_agent "Honer" "Continue where you left off." "" --resume-session "$resumed_session"; then
                    agent_fail HONER "failed."
                    exit 1
                fi
            else
                local session_id session_name
                local honer_bug
                honer_bug=$(gh issue list --state open --label "type:bug" --json number,labels --jq '
                    [.[] | select(.labels | map(.name) | any(. == "ai-generated") | not)] | sort_by(.number) | .[0].number // empty
                ' 2>/dev/null || true)
                if [ -n "$honer_bug" ]; then
                    session_name="honer-bug-${honer_bug}"
                else
                    session_name="honer-audit-$(date -u +'%m-%d-%YT%H-%M')"
                fi
                session_id=$(_forge_uuid)
                set_session "honer" "$session_name" "$session_id" "" 2>/dev/null || true
                if ! run_forge_agent "Honer" "Greet the user and begin." "" --session-id "$session_id" --session-name "$session_name"; then
                    agent_fail HONER "failed."
                    exit 1
                fi
            fi
        fi
        agent_ok HONER "complete. Run 'forge stoke' to start implementing."
        ;;

    scribe|auto-scribe)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            agent_msg SCRIBE "Starting..."
            if ! run_forge_agent "auto-scribe" "Audit documentation and update the wiki."; then
                agent_fail SCRIBE "failed."
                exit 1
            fi
        else
            resumed_session=$(pick_session "scribe")
            agent_msg SCRIBE "Starting..."
            if [ -n "$resumed_session" ]; then
                if ! run_forge_agent "Scribe" "Continue where you left off." "" --resume-session "$resumed_session"; then
                    agent_fail SCRIBE "failed."
                    exit 1
                fi
            else
                local session_id session_name="scribe-$(date -u +'%m-%d-%YT%H-%M')"
                session_id=$(_forge_uuid)
                set_session "scribe" "$session_name" "$session_id" "" 2>/dev/null || true
                if ! run_forge_agent "Scribe" "Greet the user and begin." "" --session-id "$session_id" --session-name "$session_name"; then
                    agent_fail SCRIBE "failed."
                    exit 1
                fi
            fi
        fi
        agent_ok SCRIBE "complete."
        ;;

    stoke)
        shift

        require_forge_project
        check_auth
        check_labels

        show_banner stoke
        forge_info "Stoking the forge..."
        if ! run_stoke_loop; then
            forge_fail "Stoke failed. Resolve the above, then re-run 'forge stoke'."
            exit 1
        fi
        forge_ok "Stoke complete."
        ;;

    cast)
        shift

        require_forge_project
        check_auth
        check_labels

        show_banner cast
        forge_info "Starting full cast..."

        cast_start_time=$(date +%s)
        cast_did_work=false
        while true; do
            # Priority 0: Resume any interrupted agent session
            local interrupted_role="" interrupted_session=""
            for _role in smelter honer scribe proof-master; do
                local _sess
                _sess=$(get_session "$_role" | cut -f1)
                if [ -n "$_sess" ]; then
                    interrupted_role="$_role"
                    interrupted_session="$_sess"
                    break
                fi
            done
            if [ -n "$interrupted_session" ]; then
                cast_did_work=true
                local _agent_name="auto-${interrupted_role}"
                local _label
                _label=$(echo "$interrupted_role" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                agent_msg "$_label" "Resuming interrupted ${interrupted_role} session..."
                if ! run_forge_agent "$_agent_name" "Continue where you left off." "Resuming ${interrupted_role}..." \
                    --resume-session "$interrupted_session"; then
                    agent_fail "$_label" "failed. Stopping."
                    exit 1
                fi
                if ! clear_session "$interrupted_role" 2>/dev/null; then
                    forge_warn "Failed to clear session for ${interrupted_role}. Forcing clear."
                    # Prevent infinite loop — sweep all projects in case project name derivation failed
                    python3 -c "
import json, sys
cfg_path = sys.argv[1]
with open(cfg_path) as f:
    cfg = json.load(f)
for proj in cfg.get('projects', {}).values():
    sess = proj.get('sessions', {}).get(sys.argv[2])
    if isinstance(sess, dict):
        sess['active'] = None
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" "$FORGE_CONFIG_DIR/config.json" "$interrupted_role" 2>/dev/null || {
                        forge_fail "Cannot clear stale session. Remove manually from $FORGE_CONFIG_DIR/config.json"
                        exit 1
                    }
                fi
                continue
            fi

            # Priority 1: Implementation issues on the board → stoke
            has_status_issues=$(gh issue list --state open --label "ai-generated" --json number,labels -L 100 --jq '
                [.[] | select(.labels | map(.name) | any(startswith("status:")))] | length
            ' 2>/dev/null || echo "0")
            has_status_issues="${has_status_issues:-0}"

            if [ "$has_status_issues" -gt 0 ]; then
                cast_did_work=true
                forge_info "Stoking the forge..."
                if ! run_stoke_loop; then
                    forge_fail "Cast paused. Resolve the above, then re-run 'forge cast'."
                    exit 1
                fi
                continue
            fi

            # Priority 2: Human-filed feature requests → smelt (creates issues directly)
            feature_issue=$(gh issue list --state open --label "type:feature" --json number,labels --jq '
                [.[] | select(.labels | map(.name) | any(. == "ai-generated") | not)] | sort_by(.number) | .[0].number // empty
            ' 2>/dev/null || true)
            if [ -n "$feature_issue" ]; then
                cast_did_work=true
                local smelter_session_id smelter_session_name="smelter-feature-${feature_issue}"
                smelter_session_id=$(_forge_uuid)
                set_session "smelter" "$smelter_session_name" "$smelter_session_id" "$feature_issue" 2>/dev/null || true
                agent_msg SMELTER "Smelting feature request #$feature_issue..."
                if ! run_forge_agent "auto-smelter" "Process feature request issue #${feature_issue}. Research, plan, and create implementation issues." "Smelting #${feature_issue}..." \
                    --session-id "$smelter_session_id" --session-name "$smelter_session_name"; then
                    agent_fail SMELTER "failed. Stopping."
                    exit 1
                fi
                clear_session "smelter" 2>/dev/null || true
                continue
            fi

            # Nothing queued — check if work was ever done in this project
            if [ "$cast_did_work" = false ]; then
                ever_worked=$(gh issue list --state all --label "ai-generated" --json number --jq 'length' 2>/dev/null || echo "0")
                ever_worked="${ever_worked:-0}"
                if [ "$ever_worked" -eq 0 ]; then
                    forge_info "Nothing to cast. File a type:feature issue or add code to the project first."
                    break
                fi
                cast_did_work=true
            fi

            # All work drained — audit, document, then check for new work
            local honer_session_id honer_session_name
            local honer_bug
            honer_bug=$(gh issue list --state open --label "type:bug" --json number,labels --jq '
                [.[] | select(.labels | map(.name) | any(. == "ai-generated") | not)] | sort_by(.number) | .[0].number // empty
            ' 2>/dev/null || true)
            if [ -n "$honer_bug" ]; then
                honer_session_name="honer-bug-${honer_bug}"
            else
                honer_session_name="honer-audit-$(date -u +'%m-%d-%YT%H-%M')"
            fi
            honer_session_id=$(_forge_uuid)
            set_session "honer" "$honer_session_name" "$honer_session_id" "" 2>/dev/null || true
            agent_msg HONER "Honing..."
            if ! run_forge_agent "auto-honer" "Check for human-filed bugs first. If none, audit the codebase." "Honing..." \
                --session-id "$honer_session_id" --session-name "$honer_session_name"; then
                agent_fail HONER "failed. Stopping."
                exit 1
            fi
            clear_session "honer" 2>/dev/null || true

            local scribe_session_id scribe_session_name="scribe-$(date -u +'%m-%d-%YT%H-%M')"
            scribe_session_id=$(_forge_uuid)
            set_session "scribe" "$scribe_session_name" "$scribe_session_id" "" 2>/dev/null || true
            agent_msg SCRIBE "Scribing..."
            if ! run_forge_agent "auto-scribe" "Audit documentation and update the wiki." "Scribing..." \
                --session-id "$scribe_session_id" --session-name "$scribe_session_name"; then
                agent_fail SCRIBE "failed. Stopping."
                exit 1
            fi
            clear_session "scribe" 2>/dev/null || true

            # Check if hone/scribe produced new work
            new_ready=$(gh issue list --state open --label "status:ready" --label "ai-generated" --json number --jq 'length' 2>/dev/null || echo "0")
            new_ready="${new_ready:-0}"
            if [ "$new_ready" -gt 0 ]; then
                forge_info "New work produced. Continuing cast..."
                continue
            fi

            # No new work — stamp the release
            local pm_current_tag pm_session_id pm_session_name
            pm_current_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "initial")
            pm_session_name="proof-master-${pm_current_tag}"
            pm_session_id=$(_forge_uuid)
            set_session "proof-master" "$pm_session_name" "$pm_session_id" "" 2>/dev/null || true
            agent_msg PROOF-MASTER "Checking for unreleased work..."
            run_forge_agent "auto-proof-master" "Check for unreleased work on main. If found, create a release." "Releasing..." \
                --session-id "$pm_session_id" --session-name "$pm_session_name" || true
            clear_session "proof-master" 2>/dev/null || true

            forge_ok "Cast complete."
            break
        done

        if [ "$cast_did_work" = true ]; then
            forge_cast_summary "$cast_start_time"
        fi
        ;;

    uninstall)
        echo ""
        echo "This will remove Forge from your system."
        echo ""
        echo "  Removes:  ~/.forge/ (repo, CLI binary)"
        echo "  Removes:  PATH entries from shell config"
        echo "  Keeps:    All existing Forge projects (untouched)"
        echo ""
        printf "  Continue? (y/n) [n]: "
        read -r confirm
        confirm="${confirm:-n}"
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "  Cancelled."
            exit 0
        fi

        # Remove Forge plugin and marketplace
        claude plugin uninstall forge 2>/dev/null || true
        claude plugin marketplace remove forge 2>/dev/null || true

        # Remove PATH from shell configs
        for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
            if [ -f "$rc" ]; then
                sed -i.bak '/# Forge/d' "$rc" 2>/dev/null && rm -f "${rc}.bak"
                sed -i.bak '/\.forge\/bin/d' "$rc" 2>/dev/null && rm -f "${rc}.bak"
            fi
        done

        # Remove fish config
        rm -f "$HOME/.config/fish/conf.d/forge.fish" 2>/dev/null || true

        # Remove Forge itself
        rm -rf "$HOME/.forge"

        echo ""
        echo "  Forge has been uninstalled."
        echo "  Your Forge projects are still intact — only the CLI was removed."
        echo "  Restart your terminal to update PATH."
        echo ""
        exit 0
        ;;

    deploy)
        require_forge_project

        # Ensure we have fresh remote state
        git fetch origin main production --quiet 2>/dev/null || {
            echo -e "${RED}Error:${NC} Could not fetch from remote."
            exit 1
        }

        remote_main=$(git rev-parse origin/main 2>/dev/null)
        remote_prod=$(git rev-parse origin/production 2>/dev/null)

        if [ -z "$remote_prod" ]; then
            echo -e "${RED}Error:${NC} Remote production branch not found."
            echo "  Run 'forge init --resume' to create it, or push manually:"
            echo "  git push origin main:production"
            exit 1
        fi

        if [ "$remote_main" = "$remote_prod" ]; then
            echo -e "${GREEN}Nothing to deploy — production is already at main.${NC}"
            exit 0
        fi

        if ! git merge-base --is-ancestor origin/production origin/main; then
            echo -e "${RED}Error:${NC} production has diverged from main. Resolve manually."
            exit 1
        fi

        # Show what's being deployed
        echo ""
        echo "Commits to deploy:"
        git log --oneline origin/production..origin/main
        echo ""
        printf "Deploy to production? (y/n) [n]: "
        read -r confirm
        confirm="${confirm:-n}"
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "  Cancelled."
            exit 0
        fi

        git push origin origin/main:refs/heads/production
        echo -e "${GREEN}Production updated. Vercel will deploy automatically.${NC}"
        ;;

    --help|-h|"")
        show_usage
        ;;

    *)
        echo "Unknown command: $1"
        echo ""
        echo "Run 'forge help' for a list of commands."
        exit 1
        ;;
esac
