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
        echo "Forge $(forge_version)"
        # Check for updates (non-blocking)
        if remote_head=$(git -C "$FORGE_REPO" ls-remote --heads origin main 2>/dev/null | cut -f1); then
            local_head=$(git -C "$FORGE_REPO" rev-parse HEAD 2>/dev/null)
            if [ -n "$remote_head" ] && [ "$local_head" != "$remote_head" ]; then
                echo -e "  ${YELLOW}Update available.${NC} Run 'forge update'."
            fi
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
            echo "  1. Installs tools (Homebrew, Node.js, pnpm, gh, Vercel CLI)"
            echo "  2. Scaffolds a Next.js app from your PROMPT.md"
            echo "  3. Creates a GitHub repo with branch protection and CI"
            echo "  4. Links a Vercel project for preview deploys"
            echo "  5. Installs Forge skills, hooks, and CLAUDE.md"
            echo ""
            echo "Options:"
            echo "  --resume    Resume from where a previous bootstrap stopped"
            echo ""
            echo "Requires PROMPT.md in the current directory."
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


        # --- Install / update Claude Code (native binary) ---
        echo "Installing Claude Code..."
        curl -fsSL https://claude.ai/install.sh | bash
        echo ""

        # --- Check billing: API key vs subscription ---
        if [ "$FORGE_RESUME" != true ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
                echo "  ⚠  ANTHROPIC_API_KEY is set in your environment."
                echo "     Forge will use the API key instead of your subscription."
                echo "     API usage is billed per-token with no automatic spending cap."
                echo "     Set a limit: https://console.anthropic.com/settings/limits"
                echo ""
                printf "  Continue with API key? (y/n) [n]: "
                read -r use_api_key
                use_api_key="${use_api_key:-n}"
                if [ "$use_api_key" != "y" ] && [ "$use_api_key" != "Y" ]; then
                    echo "  Unset the key and re-run:"
                    echo "    unset ANTHROPIC_API_KEY"
                    exit 1
                fi
            else
                echo "  Forge works best with a Claude Max subscription."
                echo "  A Pro subscription will burn through its daily limit quickly."
                echo "  Learn more: https://claude.ai/upgrade"
                echo ""
                printf "  Do you have a Claude Max subscription? (y/n) [y]: "
                read -r has_max
                has_max="${has_max:-y}"
                if [ "$has_max" != "y" ] && [ "$has_max" != "Y" ]; then
                    echo "  A Max subscription is recommended for Forge."
                    echo "  Sign up at https://claude.ai/upgrade then re-run forge init."
                    exit 1
                fi
            fi
            echo ""
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
        # Prefer latest tag (release), fall back to origin/main
        latest_tag=$(git -C "$FORGE_REPO" describe --tags --abbrev=0 2>/dev/null || true)
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
        fi
        ;;
    upgrade)
        if [ "${2:-}" = "--help" ] || [ "${2:-}" = "-h" ]; then
            echo "forge upgrade — Update project artifacts"
            echo ""
            echo "Usage: forge upgrade"
            echo ""
            echo "Updates agents, hooks, and CLAUDE.md in the current Forge project"
            echo "to match the installed Forge version. Creates a backup first."
            echo ""
            echo "Backs up to .forge-backup-YYYY-MM-DD-HHMMSS/"
            exit 0
        fi

        require_forge_project

        echo "Upgrading Forge artifacts..."
        echo ""

        # 2. Create backup
        BACKUP_DIR=".forge-backup-$(date +%Y-%m-%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        [ -d .claude/agents ] && cp -r .claude/agents/ "$BACKUP_DIR/agents"
        [ -f .claude/settings.json ] && cp .claude/settings.json "$BACKUP_DIR/settings.json"
        [ -f CLAUDE.md ] && cp CLAUDE.md "$BACKUP_DIR/CLAUDE.md"
        echo -e "  Backed up to ${BOLD}${BACKUP_DIR}/${NC}"

        # 3. Add backup and session patterns to .gitignore
        for pattern in '.forge-backup-*' '.forge-temp/'; do
            if ! grep -Fq "$pattern" .gitignore 2>/dev/null; then
                echo "$pattern" >> .gitignore
            fi
        done

        # 4. Update forge agents (preserve user domain agents: my-*.md)
        mkdir -p .claude/agents
        for f in .claude/agents/*.md; do
            [ -f "$f" ] || continue
            case "$(basename "$f")" in my-*) ;; *) rm -f "$f" ;; esac
        done
        cp "$FORGE_REPO/agents/"*.md .claude/agents/
        echo -e "  ${GREEN}✓${NC} Agents updated"

        # 4b. Generate AGENTS.md if missing (try @latest, fall back to @canary)
        if [ ! -f AGENTS.md ]; then
            pnpm dlx @next/codemod@latest agents-md --output AGENTS.md >/dev/null 2>&1 \
              || pnpm dlx @next/codemod@canary agents-md --output AGENTS.md >/dev/null 2>&1 \
              || true
            [ -f AGENTS.md ] && echo -e "  ${GREEN}✓${NC} AGENTS.md generated"
        fi

        # 5. Update hooks (merge to preserve plugin config)
        merge_forge_hooks
        echo -e "  ${GREEN}✓${NC} Hooks updated"

        # 5b. Ensure Vercel plugin and Playwright MCP are installed
        if ! claude plugin list 2>/dev/null | grep -q "vercel"; then
            claude plugin install vercel@claude-plugins-official --scope project 2>/dev/null \
                && echo -e "  ${GREEN}✓${NC} Vercel plugin installed" \
                || echo -e "  ${YELLOW}!${NC} Vercel plugin failed to install"
        fi
        if ! claude mcp list 2>/dev/null | grep -q "playwright"; then
            claude mcp add --scope project playwright -- npx @playwright/mcp@latest 2>/dev/null \
                && echo -e "  ${GREEN}✓${NC} Playwright MCP installed" \
                || echo -e "  ${YELLOW}!${NC} Playwright MCP failed to install"
        fi

        # 6. Update CLAUDE.md
        cp "$FORGE_REPO/CLAUDE.md.dist" CLAUDE.md
        echo -e "  ${GREEN}✓${NC} CLAUDE.md updated"

        # 7. Copy deploy workflow
        if [ -f "$FORGE_REPO/workflows/deploy-production.yml" ]; then
            mkdir -p .github/workflows
            cp "$FORGE_REPO/workflows/deploy-production.yml" .github/workflows/deploy-production.yml
            echo -e "  ${GREEN}✓${NC} Deploy workflow updated"
        fi

        echo ""
        echo "  Review changes:  git diff"
        echo "  Restore backup:  cp -r ${BACKUP_DIR}/ ."
        echo ""
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

        if command -v brew &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
        else
            echo -e "  ${RED}✗${NC} Homebrew not installed"
        fi

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

        if command -v jq &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} jq $(jq --version 2>/dev/null)"
        else
            echo -e "  ${YELLOW}⚠${NC} jq not installed (used by skills; install with: brew install jq)"
        fi

        # 3. Check artifact freshness
        echo ""
        echo "Artifacts:"

        artifacts_outdated=false

        forge_agents_ok=true
        if [ -d "$FORGE_REPO/agents" ]; then
            for agent_file in "$FORGE_REPO/agents"/*.md; do
                [ -f "$agent_file" ] || continue
                agent="$(basename "$agent_file")"
                if [ -f ".claude/agents/$agent" ]; then
                    if ! diff -q ".claude/agents/$agent" "$agent_file" &>/dev/null; then
                        forge_agents_ok=false
                        break
                    fi
                else
                    forge_agents_ok=false
                    break
                fi
            done
        else
            forge_agents_ok=false
        fi
        if $forge_agents_ok; then
            echo -e "  ${GREEN}✓${NC} Agents up-to-date"
        else
            echo -e "  ${YELLOW}⚠${NC} Agents outdated"
            artifacts_outdated=true
        fi

        if command -v jq &>/dev/null; then
            hooks_match=$(jq -S '{permissions, hooks}' .claude/settings.json 2>/dev/null | \
                diff -q - <(jq -S '{permissions, hooks}' "$FORGE_REPO/hooks/settings.json" 2>/dev/null) &>/dev/null && echo y || echo n)
        else
            hooks_match=$(diff -q .claude/settings.json "$FORGE_REPO/hooks/settings.json" &>/dev/null && echo y || echo n)
        fi
        if [ "$hooks_match" = "y" ]; then
            echo -e "  ${GREEN}✓${NC} Hooks up-to-date"
        else
            echo -e "  ${YELLOW}⚠${NC} Hooks outdated"
            artifacts_outdated=true
        fi

        if [ -f .github/workflows/ci.yml ]; then
            if diff -q .github/workflows/ci.yml "$FORGE_REPO/workflows/ci.yml" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} CI workflow up-to-date"
            else
                echo -e "  ${DIM}-${NC} CI workflow differs (not managed by upgrade)"
            fi
        else
            echo -e "  ${DIM}-${NC} CI workflow not found"
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

        if command -v perl &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} perl available"
        else
            echo -e "  ${RED}✗${NC} perl not found (needed for CLAUDE.md generation)"
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
        if [ "$artifacts_outdated" = true ]; then
            echo "  Run 'forge upgrade' to update outdated artifacts."
        else
            echo "  All managed artifacts are up-to-date."
        fi
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
            echo "produces a comprehensive ingot in ingots/."
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

        # Check for unprocessed ingots
        next_bp=""
        next_bp=$(find_unprocessed_ingots | head -1)
        if [ -z "$next_bp" ]; then
            echo "[forge] No unprocessed ingots. Run 'forge smelt' first."
            exit 0
        fi

        mode="interactive"
        [[ "$FORGE_COMMAND" == auto-* ]] && mode="auto"

        echo "[forge] Starting Refiner ($mode mode) on ingot $next_bp..."
        if ! run_forge_agent "Refiner" "Run in $mode mode. Process ingot ingots/${next_bp}.md"; then
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
        echo "Setup commands:"
        echo "  init             Bootstrap a new Forge project (requires PROMPT.md)"
        echo "  init --resume    Resume a failed or interrupted bootstrap"
        echo "  version          Show installed version and check for updates"
        echo "  update           Update Forge to the latest version"
        echo "  upgrade          Update Forge artifacts in the current project"
        echo "  doctor           Check tool versions and project health"
        echo "  uninstall        Remove Forge from your system"
        echo ""
        echo "Run 'forge <command> --help' for detailed help on a command."
        echo ""
        echo "Quick start:"
        echo "  1. mkdir my-app && cd my-app"
        echo "  2. Write a PROMPT.md describing your app"
        echo "  3. forge init"
        echo "  4. forge smelt"
        echo "  5. forge refine"
        echo "  6. forge hammer && forge temper && forge proof"
        ;;
esac
