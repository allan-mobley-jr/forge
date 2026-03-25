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

show_banner() {
    local version
    version=$(forge_version)
    echo ""
    echo -e "  ${YELLOW}███████╗ ██████╗ ██████╗  ██████╗ ███████╗${NC}"
    echo -e "  ${YELLOW}██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝${NC}"
    echo -e "  ${YELLOW}█████╗  ██║   ██║██████╔╝██║  ███╗█████╗${NC}"
    echo -e "  ${YELLOW}██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝${NC}"
    echo -e "  ${YELLOW}██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗${NC}"
    echo -e "  ${YELLOW}╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
    echo ""
    echo -e "  Autonomous Next.js Development      ${DIM}${version}${NC}"
    echo ""
}

case "${1:-}" in
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
        if [ "${2:-}" = "--help" ] || [ "${2:-}" = "-h" ]; then
            echo "forge init — Bootstrap a new Forge project"
            echo ""
            echo "Usage: forge init [--resume]"
            echo ""
            echo "Creates a new Forge project in the current directory:"
            echo "  1. Checks prerequisites (Node.js, pnpm, gh, claude)"
            echo "  2. Verifies Forge plugin is installed"
            echo "  3. Creates a GitHub repo with branch protection and labels"
            echo "  4. Sets up production branch"
            echo ""
            echo "Options:"
            echo "  --resume    Resume from where a previous bootstrap stopped"
            exit 0
        fi

        FORGE_RESUME=false
        if [ "${2:-}" = "--resume" ]; then
            FORGE_RESUME=true
        fi

        show_banner

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
        if [ "${2:-}" = "--help" ] || [ "${2:-}" = "-h" ]; then
            echo "forge update — Update Forge itself"
            echo ""
            echo "Usage: forge update"
            echo ""
            echo "Pulls the latest version of Forge from GitHub."
            echo "The CLI updates automatically via symlink."
            echo "Run 'forge upgrade' inside a project to update its artifacts."
            exit 0
        fi
        echo -e "${BLUE}Updating Forge...${NC}"
        git -C "$FORGE_REPO" fetch --quiet --tags
        local_head=$(git -C "$FORGE_REPO" rev-parse HEAD)
        # Prefer highest semver tag (not just nearest to HEAD), fall back to origin/main
        latest_tag=$(git -C "$FORGE_REPO" tag -l 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
        if [ -n "$latest_tag" ]; then
            git -C "$FORGE_REPO" checkout "$latest_tag" --quiet 2>/dev/null || true
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
            claude plugin install forge@forge 2>/dev/null \
                && echo -e "  ${GREEN}✓${NC} Forge plugin refreshed" \
                || echo -e "  ${YELLOW}!${NC} Forge plugin failed. Run manually: claude plugin install forge@forge"
            claude plugin install vercel@claude-plugins-official 2>/dev/null \
                && echo -e "  ${GREEN}✓${NC} Vercel plugin refreshed" \
                || echo -e "  ${YELLOW}!${NC} Vercel plugin failed. Run manually: claude plugin install vercel@claude-plugins-official"
            claude plugin install playwright@claude-plugins-official 2>/dev/null \
                && echo -e "  ${GREEN}✓${NC} Playwright plugin refreshed" \
                || echo -e "  ${YELLOW}!${NC} Playwright plugin failed. Run manually: claude plugin install playwright@claude-plugins-official"
        fi
        ;;
    doctor)
        if [ "${2:-}" = "--help" ] || [ "${2:-}" = "-h" ]; then
            echo "forge doctor — Health check"
            echo ""
            echo "Usage: forge doctor"
            echo ""
            echo "Checks tool versions, authentication, disk space, and whether"
            echo "project artifacts are up-to-date with the installed Forge version."
            exit 0
        fi

        require_forge_project

        echo ""
        echo "Forge Doctor"
        echo "============"
        echo ""

        # 2. Check tools
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

        if command -v vercel &>/dev/null || [ -x "${PNPM_HOME:-$HOME/Library/pnpm}/vercel" ]; then
            echo -e "  ${GREEN}✓${NC} Vercel CLI $( (vercel --version 2>/dev/null || "${PNPM_HOME:-$HOME/Library/pnpm}/vercel" --version 2>/dev/null) | head -1)"
        else
            echo -e "  ${YELLOW}⚠${NC} Vercel CLI not installed"
        fi

        if command -v python3 &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} python3 $(python3 --version 2>&1 | awk '{print $2}')"
        else
            echo -e "  ${RED}✗${NC} python3 not installed (required; install with: brew install python3)"
        fi

        if command -v claude &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Claude Code $(claude --version 2>/dev/null | head -1)"
        else
            echo -e "  ${RED}✗${NC} Claude Code not installed"
        fi


        # 3. Check Forge plugin
        echo ""
        echo "Plugin:"

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

        if ls .github/workflows/*.yml &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} CI workflows present"
        else
            echo -e "  ${DIM}-${NC} No CI workflows found"
        fi

        # 4. Check version requirements
        echo ""
        echo "Versions:"

        if command -v node &>/dev/null; then
            node_major=$(node --version | sed 's/v//' | cut -d. -f1)
            if [ "$node_major" -ge 18 ]; then
                echo -e "  ${GREEN}✓${NC} Node.js >= 18"
            else
                echo -e "  ${RED}✗${NC} Node.js $(node --version) — need >= 18"
            fi
        fi

        if command -v pnpm &>/dev/null; then
            pnpm_major=$(pnpm --version | cut -d. -f1)
            if [ "$pnpm_major" -ge 8 ]; then
                echo -e "  ${GREEN}✓${NC} pnpm >= 8"
            else
                echo -e "  ${RED}✗${NC} pnpm $(pnpm --version) — need >= 8"
            fi
        fi


        # 5. Check connectivity
        echo ""
        echo "Connectivity:"

        if gh auth status &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} GitHub authenticated"
        else
            echo -e "  ${RED}✗${NC} GitHub not authenticated — run: gh auth login"
        fi

        if command -v vercel &>/dev/null || [ -x "${PNPM_HOME:-$HOME/Library/pnpm}/vercel" ]; then
            if (vercel whoami &>/dev/null 2>&1 || "${PNPM_HOME:-$HOME/Library/pnpm}/vercel" whoami &>/dev/null 2>&1); then
                echo -e "  ${GREEN}✓${NC} Vercel authenticated"
            else
                echo -e "  ${YELLOW}⚠${NC} Vercel not authenticated — run: vercel login"
            fi
        fi

        if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            echo -e "  ${GREEN}✓${NC} Claude auth: API key"
        elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
            echo -e "  ${GREEN}✓${NC} Claude auth: long-lived token (setup-token)"
        else
            echo -e "  ${YELLOW}⚠${NC} Claude auth: short-lived OAuth — may expire during long sessions"
            echo "    Run 'claude setup-token' and set CLAUDE_CODE_OAUTH_TOKEN in your shell profile"
        fi

        # 6. Check labels
        echo ""
        echo "Labels:"

        if gh auth status &>/dev/null 2>&1; then
            # Use the canonical label list from forge-lib.sh
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

        # 7. Check disk space
        echo ""
        echo "System:"
        avail_gb=$(df -g . 2>/dev/null | tail -1 | awk '{print $4}')
        if [ -n "$avail_gb" ] && [ "$avail_gb" -ge 2 ]; then
            echo -e "  ${GREEN}✓${NC} Disk space: ${avail_gb}GB available"
        elif [ -n "$avail_gb" ]; then
            echo -e "  ${YELLOW}⚠${NC} Low disk space: ${avail_gb}GB (need >= 2GB)"
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
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            echo "forge smelt — Produce an ingot from PROMPT.md or a feature request"
            echo ""
            echo "Usage: forge smelt [--max-budget N]"
            echo "       forge auto-smelt [--max-budget N]"
            echo ""
            echo "The Smelter reads PROMPT.md (or human-filed feature requests) and"
            echo "creates a comprehensive ingot as a GitHub issue."
            echo ""
            echo "  smelt        Interactive — may ask clarifying questions"
            echo "  auto-smelt   Autonomous — makes reasonable assumptions"
            exit 0
        fi

        require_forge_project
        FORGE_MAX_BUDGET=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget) FORGE_MAX_BUDGET="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        check_auth
        check_labels

        mode="interactive"
        [[ "$FORGE_COMMAND" == auto-* ]] && mode="auto"

        echo "[forge] Starting Smelter ($mode mode)..."
        if ! run_forge_agent "Smelter" "Run in $mode mode. Read PROMPT.md and produce an ingot."; then
            echo "[forge] Smelter failed."
            exit 1
        fi
        echo "[forge] Smelter complete. Run 'forge refine' to create issues from the ingot."
        ;;

    refine|auto-refine)
        FORGE_COMMAND="$1"; shift
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            echo "forge refine — Create GitHub issues from an ingot"
            echo ""
            echo "Usage: forge refine [--max-budget N]"
            echo "       forge auto-refine [--max-budget N]"
            echo ""
            echo "The Refiner reads the oldest unprocessed ingot and creates"
            echo "sequenced GitHub issues with milestones."
            exit 0
        fi

        require_forge_project
        FORGE_MAX_BUDGET=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget) FORGE_MAX_BUDGET="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        check_auth
        check_labels

        # Check for open ingot issues
        next_ingot=""
        next_ingot=$(find_unprocessed_ingots | head -1)
        if [ -z "$next_ingot" ]; then
            echo "[forge] No open ingot issues. Run 'forge smelt' first."
            exit 0
        fi

        mode="interactive"
        [[ "$FORGE_COMMAND" == auto-* ]] && mode="auto"

        echo "[forge] Starting Refiner ($mode mode) on ingot issue #$next_ingot..."
        if ! run_forge_agent "Refiner" "Run in $mode mode. Process ingot issue #${next_ingot}."; then
            echo "[forge] Refiner failed."
            exit 1
        fi
        echo "[forge] Refiner complete. Run 'forge hammer' to start implementing."
        ;;

    hammer|auto-hammer)
        FORGE_COMMAND="$1"; shift
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            echo "forge hammer — Implement the current issue"
            echo ""
            echo "Usage: forge hammer [--max-budget N]"
            echo "       forge auto-hammer [--max-budget N]"
            echo ""
            echo "The Blacksmith picks up the lowest open issue (status:ready or"
            echo "status:rework) and implements it on a feature branch."
            exit 0
        fi

        require_forge_project
        FORGE_MAX_BUDGET=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget) FORGE_MAX_BUDGET="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        check_auth
        check_labels

        issue=$(find_issue_for_hammer)
        if [ -z "$issue" ]; then
            echo "[forge] No issues ready for hammering."
            exit 0
        fi

        mode="interactive"
        [[ "$FORGE_COMMAND" == auto-* ]] && mode="auto"

        echo "[forge] Starting Blacksmith ($mode mode) on issue #$issue..."
        transition_status "$issue" "" "status:hammering"
        if ! run_forge_agent "Blacksmith" "Run in $mode mode. Implement issue #$issue."; then
            echo "[forge] Blacksmith failed on issue #$issue."
            exit 1
        fi
        transition_status "$issue" "status:hammering" "status:hammered"
        echo "[forge] Blacksmith complete. Run 'forge temper' to review."
        ;;

    temper|auto-temper)
        FORGE_COMMAND="$1"; shift
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            echo "forge temper — Review the current issue's implementation"
            echo ""
            echo "Usage: forge temper [--max-budget N]"
            echo "       forge auto-temper [--max-budget N]"
            echo ""
            echo "The Temperer independently reviews the Blacksmith's work and"
            echo "either approves (status:tempered) or sends back (status:rework)."
            exit 0
        fi

        require_forge_project
        FORGE_MAX_BUDGET=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget) FORGE_MAX_BUDGET="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        check_auth
        check_labels

        issue=$(find_issue_for_temper)
        if [ -z "$issue" ]; then
            echo "[forge] No issues ready for tempering."
            exit 0
        fi

        mode="interactive"
        [[ "$FORGE_COMMAND" == auto-* ]] && mode="auto"

        echo "[forge] Starting Temperer ($mode mode) on issue #$issue..."
        transition_status "$issue" "status:hammered" "status:tempering"
        if ! run_forge_agent "Temperer" "Run in $mode mode. Review issue #$issue."; then
            echo "[forge] Temperer failed on issue #$issue."
            exit 1
        fi
        # The Temperer decides the verdict — check what label it set
        # If it posted a [Temperer] rework comment, set status:rework; otherwise status:tempered
        has_rework=""
        has_rework=$(gh issue view "$issue" --json comments --jq '
            [.comments[].body | select(test("^\\*\\*\\[Temperer\\]\\*\\*"))] | length
        ' 2>/dev/null || echo "0")
        if [ "$has_rework" -gt 0 ]; then
            transition_status "$issue" "status:tempering" "status:rework"
            echo "[forge] Temperer sent issue #$issue back for rework."
        else
            transition_status "$issue" "status:tempering" "status:tempered"
            echo "[forge] Temperer approved. Run 'forge proof' to validate."
        fi
        ;;

    proof|auto-proof)
        FORGE_COMMAND="$1"; shift
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            echo "forge proof — Validate and open a PR for the current issue"
            echo ""
            echo "Usage: forge proof [--max-budget N]"
            echo "       forge auto-proof [--max-budget N]"
            echo ""
            echo "The Proof-Master runs the quality suite, validates acceptance criteria,"
            echo "and opens a PR if everything passes."
            exit 0
        fi

        require_forge_project
        FORGE_MAX_BUDGET=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget) FORGE_MAX_BUDGET="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        check_auth
        check_labels

        issue=$(find_issue_for_proof)
        if [ -z "$issue" ]; then
            echo "[forge] No issues ready for proofing."
            exit 0
        fi

        mode="interactive"
        [[ "$FORGE_COMMAND" == auto-* ]] && mode="auto"

        echo "[forge] Starting Proof-Master ($mode mode) on issue #$issue..."
        transition_status "$issue" "status:tempered" "status:proving"
        if ! run_forge_agent "Proof-Master" "Run in $mode mode. Validate and open PR for issue #$issue."; then
            echo "[forge] Proof-Master failed on issue #$issue."
            exit 1
        fi
        # Check verdict — if a [Proof-Master] rework comment was posted, it failed
        has_rework=""
        has_rework=$(gh issue view "$issue" --json comments --jq '
            [.comments[].body | select(test("^\\*\\*\\[Proof-Master\\]\\*\\*"))] | length
        ' 2>/dev/null || echo "0")
        if [ "$has_rework" -gt 0 ]; then
            transition_status "$issue" "status:proving" "status:rework"
            echo "[forge] Proof-Master sent issue #$issue back for rework."
        else
            transition_status "$issue" "status:proving" "status:proved"
            echo "[forge] Proof-Master complete. PR opened for issue #$issue."
        fi
        ;;

    hone|auto-hone)
        FORGE_COMMAND="$1"; shift
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            echo "forge hone — Audit the codebase and produce an improvement ingot"
            echo ""
            echo "Usage: forge hone [--max-budget N]"
            echo "       forge auto-hone [--max-budget N]"
            echo ""
            echo "The Honer audits the app against the ingot, triages human"
            echo "issues, and produces a new ingot for the Refiner."
            exit 0
        fi

        require_forge_project
        FORGE_MAX_BUDGET=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget) FORGE_MAX_BUDGET="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        check_auth
        check_labels

        mode="interactive"
        [[ "$FORGE_COMMAND" == auto-* ]] && mode="auto"

        echo "[forge] Starting Honer ($mode mode)..."
        if ! run_forge_agent "Honer" "Run in $mode mode. Audit the codebase and produce an improvement ingot."; then
            echo "[forge] Honer failed."
            exit 1
        fi
        echo "[forge] Honer complete. Run 'forge refine' to create issues from the ingot."
        ;;

    auto-run)
        shift
        if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
            echo "forge auto-run — Autonomously process the issue queue"
            echo ""
            echo "Usage: forge auto-run [--max-budget N]"
            echo ""
            echo "Chains auto-hammer → auto-temper → auto-proof for each issue,"
            echo "processing one issue at a time through the full pipeline."
            echo "Exits when no actionable issues remain."
            exit 0
        fi

        require_forge_project
        FORGE_MAX_BUDGET=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget) FORGE_MAX_BUDGET="$2"; shift 2 ;;
                *) echo "Unknown flag: $1"; exit 1 ;;
            esac
        done

        check_auth
        check_labels

        echo "[forge] Starting auto-run..."

        while true; do
            # Find next issue to work on
            issue=""
            issue=$(find_issue_for_hammer)

            # If nothing to hammer, check temper/proof queues
            if [ -z "$issue" ]; then
                issue=$(find_issue_for_temper)
                if [ -n "$issue" ]; then
                    echo "[forge] Tempering issue #$issue..."
                    transition_status "$issue" "status:hammered" "status:tempering"
                    run_forge_agent "Temperer" "Run in auto mode. Review issue #$issue." || true
                    has_rework=""
                    has_rework=$(gh issue view "$issue" --json comments --jq '
                        [.comments[].body | select(test("^\\*\\*\\[Temperer\\]\\*\\*"))] | length
                    ' 2>/dev/null || echo "0")
                    if [ "$has_rework" -gt 0 ]; then
                        transition_status "$issue" "status:tempering" "status:rework"
                    else
                        transition_status "$issue" "status:tempering" "status:tempered"
                    fi
                    continue
                fi

                issue=$(find_issue_for_proof)
                if [ -n "$issue" ]; then
                    echo "[forge] Proofing issue #$issue..."
                    transition_status "$issue" "status:tempered" "status:proving"
                    run_forge_agent "Proof-Master" "Run in auto mode. Validate and open PR for issue #$issue." || true
                    has_rework=""
                    has_rework=$(gh issue view "$issue" --json comments --jq '
                        [.comments[].body | select(test("^\\*\\*\\[Proof-Master\\]\\*\\*"))] | length
                    ' 2>/dev/null || echo "0")
                    if [ "$has_rework" -gt 0 ]; then
                        transition_status "$issue" "status:proving" "status:rework"
                    else
                        transition_status "$issue" "status:proving" "status:proved"
                    fi
                    continue
                fi

                # Nothing actionable
                echo "[forge] No actionable issues. Auto-loop complete."
                break
            fi

            # Hammer the issue
            echo "[forge] Hammering issue #$issue..."
            transition_status "$issue" "" "status:hammering"
            run_forge_agent "Blacksmith" "Run in auto mode. Implement issue #$issue." || {
                echo "[forge] Blacksmith failed on issue #$issue. Stopping."
                break
            }
            transition_status "$issue" "status:hammering" "status:hammered"

            # Temper the same issue
            echo "[forge] Tempering issue #$issue..."
            transition_status "$issue" "status:hammered" "status:tempering"
            run_forge_agent "Temperer" "Run in auto mode. Review issue #$issue." || {
                echo "[forge] Temperer failed on issue #$issue. Stopping."
                break
            }
            has_rework=""
            has_rework=$(gh issue view "$issue" --json comments --jq '
                [.comments[].body | select(test("^\\*\\*\\[Temperer\\]\\*\\*"))] | length
            ' 2>/dev/null || echo "0")
            if [ "$has_rework" -gt 0 ]; then
                transition_status "$issue" "status:tempering" "status:rework"
                echo "[forge] Issue #$issue sent back for rework. Continuing loop..."
                continue
            fi
            transition_status "$issue" "status:tempering" "status:tempered"

            # Proof the same issue
            echo "[forge] Proofing issue #$issue..."
            transition_status "$issue" "status:tempered" "status:proving"
            run_forge_agent "Proof-Master" "Run in auto mode. Validate and open PR for issue #$issue." || {
                echo "[forge] Proof-Master failed on issue #$issue. Stopping."
                break
            }
            has_rework=$(gh issue view "$issue" --json comments --jq '
                [.comments[].body | select(test("^\\*\\*\\[Proof-Master\\]\\*\\*"))] | length
            ' 2>/dev/null || echo "0")
            if [ "$has_rework" -gt 0 ]; then
                transition_status "$issue" "status:proving" "status:rework"
                echo "[forge] Issue #$issue sent back for rework. Continuing loop..."
            else
                transition_status "$issue" "status:proving" "status:proved"
                echo "[forge] Issue #$issue complete. PR opened."
            fi
        done
        ;;

    uninstall)
        if [ "${2:-}" = "--help" ] || [ "${2:-}" = "-h" ]; then
            echo "forge uninstall — Remove Forge"
            echo ""
            echo "Usage: forge uninstall"
            echo ""
            echo "Removes ~/.forge (repo + CLI binary) and PATH entries from"
            echo "shell config files. Does NOT affect existing Forge projects."
            exit 0
        fi

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
                # Remove the Forge PATH line and its comment
                sed -i '' '/# Forge/d' "$rc" 2>/dev/null || true
                sed -i '' '/\.forge\/bin/d' "$rc" 2>/dev/null || true
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
        if [ "${2:-}" = "--help" ] || [ "${2:-}" = "-h" ]; then
            echo "forge deploy — Deploy main to production"
            echo ""
            echo "Usage: forge deploy"
            echo ""
            echo "Fast-forwards the production branch to match main,"
            echo "triggering a Vercel production deployment."
            echo "Requires confirmation."
            exit 0
        fi

        require_forge_project

        # Ensure we have fresh remote state
        git fetch origin main production --quiet 2>/dev/null || {
            echo -e "${RED}Error:${NC} Could not fetch from remote."
            exit 1
        }

        local_main=$(git rev-parse origin/main 2>/dev/null)
        local_prod=$(git rev-parse origin/production 2>/dev/null)

        if [ "$local_main" = "$local_prod" ]; then
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
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "  Cancelled."
            exit 0
        fi

        git push origin origin/main:refs/heads/production
        echo -e "${GREEN}Production updated. Vercel will deploy automatically.${NC}"
        ;;

    --help|-h|*)
        show_banner
        echo "Usage: forge <command>"
        echo ""
        echo "Pipeline commands:"
        echo "  smelt            Produce an ingot from PROMPT.md"
        echo "  refine           Create GitHub issues from an ingot"
        echo "  hammer           Implement the current issue"
        echo "  temper           Review the current issue's implementation"
        echo "  proof            Validate and open a PR"
        echo "  hone             Audit the codebase for improvements"
        echo "  auto-run        Autonomously process the issue queue"
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
        echo "Run 'forge <command> --help' for detailed help on a command."
        echo ""
        echo "Quick start:"
        echo "  1. mkdir my-app && cd my-app"
        echo "  2. forge init"
        echo "  3. Write a PROMPT.md describing your app"
        echo "  4. forge smelt"
        echo "  5. forge refine"
        echo "  6. forge auto-run"
        ;;
esac
