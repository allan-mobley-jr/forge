#!/usr/bin/env bash
set -euo pipefail

# Exit cleanly on CTRL+C (exit code 130 = 128 + SIGINT)
trap 'echo ""; echo "[forge] Interrupted."; exit 130' INT

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
            echo -e "\n  ${BLUE}CAST${NC}  Full cast — smelt → refine → stoke → hone"
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
    echo "  smelt            Produce an ingot"
    echo "  refine           Create GitHub issues from an ingot"
    echo "  hammer           Implement the current issue"
    echo "  temper           Review the current issue's implementation"
    echo "  proof            Validate and open a PR"
    echo "  hone             Audit the codebase for improvements"
    echo "  stoke            Autonomously process the issue queue"
    echo "  cast             Full autonomous cycle: smelt → refine → stoke → hone"
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
    echo "  4. forge refine"
    echo "  5. forge stoke          (or forge cast for the full cycle)"
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
            echo "forge smelt — Produce an ingot"
            echo ""
            echo "Usage: forge smelt"
            echo "       forge auto-smelt"
            echo ""
            echo "  smelt        Interactive — describe what you want, confer with the Smelter"
            echo "  auto-smelt   Autonomous — picks up the oldest human-filed type:feature issue"
            ;;
        refine|auto-refine)
            echo "forge refine — Create GitHub issues from an ingot"
            echo ""
            echo "Usage: forge refine"
            echo "       forge auto-refine"
            echo ""
            echo "The Refiner reads the oldest unprocessed ingot and creates"
            echo "sequenced GitHub issues with milestones."
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
            echo "forge temper — Review the current issue's implementation"
            echo ""
            echo "Usage: forge temper"
            echo "       forge auto-temper"
            echo ""
            echo "The Temperer independently reviews the Blacksmith's work and"
            echo "either approves (status:tempered) or sends back (status:rework)."
            ;;
        proof|auto-proof)
            echo "forge proof — Validate and open a PR for the current issue"
            echo ""
            echo "Usage: forge proof"
            echo "       forge auto-proof"
            echo ""
            echo "The Proof-Master ensures test coverage, writes missing tests,"
            echo "fixes test failures, manages CI, and opens a PR."
            ;;
        hone|auto-hone)
            echo "forge hone — Audit the codebase and produce an improvement ingot"
            echo ""
            echo "Usage: forge hone"
            echo "       forge auto-hone"
            echo ""
            echo "  hone         Interactive — choose to triage a bug or audit the codebase"
            echo "  auto-hone    Autonomous — triages oldest bug first, then audits"
            ;;
        stoke)
            echo "forge stoke — Autonomously process the issue queue"
            echo ""
            echo "Usage: forge stoke"
            echo ""
            echo "Processes one issue at a time: hammer → temper → proof."
            echo "Handles all issue states including interrupted runs."
            echo "Exits when no actionable issues remain."
            ;;
        cast)
            echo "forge cast — Full autonomous cycle"
            echo ""
            echo "Usage: forge cast"
            echo ""
            echo "Runs the entire pipeline end-to-end:"
            echo "  smelt → refine → stoke (hammer/temper/proof) → hone"
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
                echo "[forge] No human-filed type:feature issues found."
                exit 0
            fi
            echo "[forge] Starting Auto-Smelter on issue #$feature_issue..."
            if ! run_forge_agent "auto-smelter" "Produce an ingot from the oldest human-filed type:feature issue."; then
                echo "[forge] Smelter failed."
                exit 1
            fi
        else
            echo "[forge] Starting Smelter..."
            if ! run_forge_agent "Smelter" "Greet the user and begin."; then
                echo "[forge] Smelter failed."
                exit 1
            fi
        fi
        echo "[forge] Smelter complete. Run 'forge refine' to create issues from the ingot."
        ;;

    refine|auto-refine)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        next_ingot=$(find_unprocessed_ingots | head -1)
        if [ -z "$next_ingot" ]; then
            echo "[forge] No open ingot issues. Run this command after the Smelter has produced a type:ingot issue."
            exit 0
        fi

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            echo "[forge] Starting Auto-Refiner..."
            if ! run_forge_agent "auto-refiner" "Process the oldest open ingot issue."; then
                echo "[forge] Auto-Refiner failed."
                exit 1
            fi
        else
            echo "[forge] Starting Refiner..."
            if ! run_forge_agent "Refiner" "Greet the user and begin."; then
                echo "[forge] Refiner failed."
                exit 1
            fi
        fi
        echo "[forge] Refiner complete. Run 'forge hammer' to start implementing."
        ;;

    hammer|auto-hammer)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        issue=$(find_issue_for_hammer)
        if [ -z "$issue" ]; then
            echo "[forge] No issues ready for hammering."
            exit 0
        fi

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            echo "[forge] Starting Auto-Blacksmith on issue #$issue..."
            if ! run_forge_agent "auto-blacksmith" "Implement the next ready issue."; then
                echo "[forge] Auto-Blacksmith failed on issue #$issue."
                exit 1
            fi
        else
            echo "[forge] Starting Blacksmith on issue #$issue..."
            if ! run_forge_agent "Blacksmith" "Greet the user and begin."; then
                echo "[forge] Blacksmith failed on issue #$issue."
                exit 1
            fi
        fi
        echo "[forge] Blacksmith complete."
        ;;

    temper|auto-temper)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        issue=$(find_issue_for_temper)
        if [ -z "$issue" ]; then
            echo "[forge] No issues ready for tempering."
            exit 0
        fi

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            echo "[forge] Starting Auto-Temperer on issue #$issue..."
            if ! run_forge_agent "auto-temperer" "Review the next hammered issue."; then
                echo "[forge] Auto-Temperer failed on issue #$issue."
                exit 1
            fi
        else
            echo "[forge] Starting Temperer on issue #$issue..."
            if ! run_forge_agent "Temperer" "Greet the user and begin."; then
                echo "[forge] Temperer failed on issue #$issue."
                exit 1
            fi
        fi
        echo "[forge] Temperer complete."
        ;;

    proof|auto-proof)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        issue=$(find_issue_for_proof)
        if [ -z "$issue" ]; then
            echo "[forge] No issues ready for proofing."
            exit 0
        fi

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            echo "[forge] Starting Auto-Proof-Master on issue #$issue..."
            if ! run_forge_agent "auto-proof-master" "Validate and open PR for the next tempered issue."; then
                echo "[forge] Auto-Proof-Master failed on issue #$issue."
                exit 1
            fi
        else
            echo "[forge] Starting Proof-Master on issue #$issue..."
            if ! run_forge_agent "Proof-Master" "Greet the user and begin."; then
                echo "[forge] Proof-Master failed on issue #$issue."
                exit 1
            fi
        fi
        echo "[forge] Proof-Master complete."
        ;;

    hone|auto-hone)
        FORGE_COMMAND="$1"; shift

        require_forge_project
        check_auth
        check_labels

        if [[ "$FORGE_COMMAND" == auto-* ]]; then
            echo "[forge] Starting Auto-Honer..."
            if ! run_forge_agent "auto-honer" "Check for human-filed bugs first. If none, audit the codebase. Produce an ingot."; then
                echo "[forge] Auto-Honer failed."
                exit 1
            fi
        else
            echo "[forge] Starting Honer..."
            if ! run_forge_agent "Honer" "Greet the user and begin."; then
                echo "[forge] Honer failed."
                exit 1
            fi
        fi
        echo "[forge] Honer complete. Run 'forge refine' to create issues from the ingot."
        ;;

    stoke)
        shift

        require_forge_project
        check_auth
        check_labels

        show_banner stoke
        echo "[forge] Stoking the forge..."
        run_stoke_loop
        echo "[forge] Stoke complete."
        ;;

    cast)
        shift

        require_forge_project
        check_auth
        check_labels

        show_banner cast
        echo "[forge] Starting full cast..."

        cast_did_work=false
        while true; do
            # Check queue state — drain existing work before creating new work
            has_status_issues=$(gh issue list --state open --label "ai-generated" --json number,labels -L 100 --jq '
                [.[] | select(.labels | map(.name) | any(startswith("status:")))] | length
            ' 2>/dev/null || echo "0")
            has_status_issues="${has_status_issues:-0}"

            # Priority 1: Implementation issues on the board → stoke
            if [ "$has_status_issues" -gt 0 ]; then
                cast_did_work=true
                echo "[forge] Stoking the forge..."
                if ! run_stoke_loop; then
                    echo "[forge] Cast paused. Resolve the above, then re-run 'forge cast'."
                    exit 1
                fi
                continue
            fi

            # Priority 2: Unprocessed ingots → refine
            next_ingot=$(find_unprocessed_ingots | head -1)
            if [ -n "$next_ingot" ]; then
                cast_did_work=true
                echo "[forge] Refining ingot #$next_ingot..."
                if ! run_forge_agent "auto-refiner" "Process ingot issue #${next_ingot}."; then
                    echo "[forge] Refiner failed. Stopping."
                    exit 1
                fi
                continue
            fi

            # Priority 3: Human-filed feature requests → smelt
            feature_issue=$(gh issue list --state open --label "type:feature" --json number,labels --jq '
                [.[] | select(.labels | map(.name) | any(. == "ai-generated") | not)] | sort_by(.number) | .[0].number // empty
            ' 2>/dev/null || true)
            if [ -n "$feature_issue" ]; then
                cast_did_work=true
                echo "[forge] Smelting feature request #$feature_issue..."
                if ! run_forge_agent "auto-smelter" "Produce an ingot from feature request issue #${feature_issue}."; then
                    echo "[forge] Smelter failed. Stopping."
                    exit 1
                fi
                continue
            fi

            # Nothing queued — if no work was ever done, exit early (#204)
            if [ "$cast_did_work" = false ]; then
                echo "[forge] Nothing to cast. File a type:feature issue or add code to the project first."
                break
            fi

            # All work drained — audit the result
            echo "[forge] Honing..."
            if ! run_forge_agent "auto-honer" "Check for human-filed bugs first. If none, audit the codebase. Produce an ingot."; then
                echo "[forge] Honer failed. Stopping."
                exit 1
            fi

            # Check if hone produced new work
            next_ingot=$(find_unprocessed_ingots | head -1)
            new_ready=$(gh issue list --state open --label "status:ready" --label "ai-generated" --json number --jq 'length' 2>/dev/null || echo "0")
            new_ready="${new_ready:-0}"
            if [ -z "$next_ingot" ] && [ "$new_ready" -eq 0 ]; then
                echo "[forge] No new work from honing. Cast complete."
                break
            fi
            echo "[forge] Honer produced new work. Continuing cast..."
        done
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
