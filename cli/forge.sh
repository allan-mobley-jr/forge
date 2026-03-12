#!/usr/bin/env bash
set -euo pipefail

FORGE_REPO="$HOME/.forge/repo"

if [ ! -d "$FORGE_REPO" ]; then
    echo "Error: Forge is not installed. Run:"
    echo '  curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash'
    exit 1
fi

# Source shared library (colors, helpers, state machine)
FORGE_LIB_DIR="${FORGE_LIB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
# shellcheck source=cli/forge-lib.sh
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
    --version|-v|-V)
        echo "Forge $(forge_version)"
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

        # Drop the starter template if no PROMPT.md exists
        if [ ! -f "PROMPT.md" ]; then
            cp "$FORGE_REPO/templates/PROMPT.md" PROMPT.md
            echo "Created PROMPT.md from the starter template."
            echo ""
            echo "  Edit PROMPT.md to describe your application before continuing."
            echo "  Open it in your editor now — we'll wait."
            echo ""
            printf "  Press Enter when PROMPT.md is ready... "
            read -r
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
        git -C "$FORGE_REPO" fetch --quiet
        git -C "$FORGE_REPO" reset --hard origin/main --quiet
        echo -e "${GREEN}Forge updated to $(forge_version).${NC}"
        ;;
    upgrade)
        if [ "${2:-}" = "--help" ] || [ "${2:-}" = "-h" ]; then
            echo "forge upgrade — Update project artifacts"
            echo ""
            echo "Usage: forge upgrade"
            echo ""
            echo "Updates skills, hooks, and CLAUDE.md in the current Forge project"
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
        cp -r .claude/skills/ "$BACKUP_DIR/skills"
        [ -f .claude/settings.json ] && cp .claude/settings.json "$BACKUP_DIR/settings.json"
        [ -f CLAUDE.md ] && cp CLAUDE.md "$BACKUP_DIR/CLAUDE.md"
        echo -e "  Backed up to ${BOLD}${BACKUP_DIR}/${NC}"

        # 3. Add backup and session patterns to .gitignore
        for pattern in '.forge-backup-*' '.forge-temp/'; do
            if ! grep -Fq "$pattern" .gitignore 2>/dev/null; then
                echo "$pattern" >> .gitignore
            fi
        done

        # 4. Update skills (clean replacement + reinstall vendor skills)
        rm -rf .claude/skills/
        mkdir -p .claude/skills
        cp -r "$FORGE_REPO/skills/"* .claude/skills/
        echo -e "  ${GREEN}✓${NC} Skills updated"

        # 4b. Reinstall vendor skills (always, since step 4 wipes the directory)
        echo "  Installing vendor skills..."
        source "$FORGE_REPO/bootstrap/vendor-skills.sh"
        if install_vendor_skills; then
            touch .claude/skills/.vendor-skills-installed
            echo -e "  ${GREEN}✓${NC} Vendor skills installed"
        else
            echo -e "  ${YELLOW}!${NC} Some vendor skills failed to install; will retry on next upgrade."
        fi

        # Ensure vendor skills sentinel is gitignored
        if [ -f .gitignore ] && ! grep -Fq '.vendor-skills-installed' .gitignore 2>/dev/null; then
            printf '\n# Vendor skills sentinel\n.claude/skills/.vendor-skills-installed\n' >> .gitignore
        fi

        # 4c. Generate AGENTS.md if missing (try @latest, fall back to @canary)
        if [ ! -f AGENTS.md ]; then
            pnpm dlx @next/codemod@latest agents-md --output AGENTS.md >/dev/null 2>&1 \
              || pnpm dlx @next/codemod@canary agents-md --output AGENTS.md >/dev/null 2>&1 \
              || true
            [ -f AGENTS.md ] && echo -e "  ${GREEN}✓${NC} AGENTS.md generated"
        fi

        # 5. Update hooks
        cp "$FORGE_REPO/hooks/settings.json" .claude/settings.json
        # Disable any user-installed plugins at project level
        if [ -f "$HOME/.claude/settings.json" ]; then
            python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    user = json.load(f)
with open(sys.argv[2]) as f:
    proj = json.load(f)
plugins = user.get('enabledPlugins', {})
if plugins:
    proj['enabledPlugins'] = {k: False for k in plugins}
    with open(sys.argv[2], 'w') as f:
        json.dump(proj, f, indent=2)
        f.write('\n')
" "$HOME/.claude/settings.json" .claude/settings.json 2>/dev/null || true
        fi
        echo -e "  ${GREEN}✓${NC} Hooks updated"

        # 6. Re-render CLAUDE.md
        if [ -f "$BACKUP_DIR/CLAUDE.md" ]; then
            # Extract values from existing CLAUDE.md
            project_name=$(head -1 "$BACKUP_DIR/CLAUDE.md" | sed 's/^# //')
            github_repo=$(grep -o 'https://github.com/[^ *]*' "$BACKUP_DIR/CLAUDE.md" | head -1)
            description=$(sed -n '/^## Project$/,/^##/{/^## Project$/d;/^##/d;/^$/d;/^\*\*/d;p;}' "$BACKUP_DIR/CLAUDE.md" | head -1)
            created_date=$(sed -n 's/.*Generated by Forge on \(.*\)/\1/p' "$BACKUP_DIR/CLAUDE.md")
        fi

        # Fallbacks
        project_name="${project_name:-$(basename "$(pwd)")}"
        github_repo="${github_repo:-$(gh repo view --json url -q .url 2>/dev/null || echo "https://github.com/unknown")}"
        if [ -z "${description:-}" ] && [ -f PROMPT.md ]; then
            description=$(head -5 PROMPT.md | grep -v '^#' | grep -v '^$' | head -1)
        fi
        description="${description:-A Forge project}"
        created_date="${created_date:-$(date +%Y-%m-%d)}"

        # Detect merge mode from config.json or existing CLAUDE.md
        merge_mode=""
        if [ -f "$HOME/.forge/config.json" ]; then
            merge_mode=$(python3 -c "
import json, sys
try:
    with open('$HOME/.forge/config.json') as f:
        cfg = json.load(f)
    print(cfg.get('projects', {}).get(sys.argv[1], {}).get('merge_mode', ''))
except:
    print('')
" "$project_name" 2>/dev/null || true)
        fi
        if [ -z "$merge_mode" ] && [ -f "$BACKUP_DIR/CLAUDE.md" ]; then
            if grep -q '^\*\*Mode:\*\* copilot' "$BACKUP_DIR/CLAUDE.md" 2>/dev/null; then
                merge_mode="copilot"
            fi
        fi
        merge_mode="${merge_mode:-auto}"

        PROJECT_NAME="$project_name" \
            GITHUB_REPO="$github_repo" \
            DESCRIPTION="$description" \
            CREATED_DATE="$created_date" \
            MERGE_MODE="$merge_mode" \
            perl -0pe '
                s/\{\{project_name\}\}/$ENV{PROJECT_NAME}/g;
                s/\{\{github_repo\}\}/$ENV{GITHUB_REPO}/g;
                s/\{\{description\}\}/$ENV{DESCRIPTION}/g;
                s/\{\{created_date\}\}/$ENV{CREATED_DATE}/g;
                if ($ENV{MERGE_MODE} eq "copilot") {
                    s/\{\{#if_auto\}\}.*?\{\{\/if_auto\}\}\n?//gs;
                    s/\{\{#if_copilot\}\}\n?//g;
                    s/\{\{\/if_copilot\}\}\n?//g;
                } else {
                    s/\{\{#if_copilot\}\}.*?\{\{\/if_copilot\}\}\n?//gs;
                    s/\{\{#if_auto\}\}\n?//g;
                    s/\{\{\/if_auto\}\}\n?//g;
                }
            ' "$FORGE_REPO/templates/CLAUDE.md.hbs" > CLAUDE.md
        echo -e "  ${GREEN}✓${NC} CLAUDE.md re-generated"

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

        forge_skills_ok=true
        if [ -d "$FORGE_REPO/skills" ]; then
            for forge_skill_dir in "$FORGE_REPO/skills"/*/; do
                [ -d "$forge_skill_dir" ] || continue
                skill="$(basename "$forge_skill_dir")"
                if [ -d ".claude/skills/$skill" ]; then
                    if ! diff -rq --exclude='.*' ".claude/skills/$skill" "$forge_skill_dir" &>/dev/null; then
                        forge_skills_ok=false
                        break
                    fi
                else
                    forge_skills_ok=false
                    break
                fi
            done
        else
            forge_skills_ok=false
        fi
        if $forge_skills_ok; then
            echo -e "  ${GREEN}✓${NC} Skills up-to-date"
        else
            echo -e "  ${YELLOW}⚠${NC} Skills outdated"
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
            echo -e "  ${YELLOW}⚠${NC} Claude auth: short-lived OAuth — may expire during forge run"
            echo "    Run 'claude setup-token' and set CLAUDE_CODE_OAUTH_TOKEN in your shell profile"
        fi

        # 6. Check labels
        echo ""
        echo "Labels:"

        if gh auth status &>/dev/null 2>&1; then
            required_labels=(
                "agent:planning" "agent:done" "agent:needs-human" "ai-generated"
                "agent:create-researcher" "agent:create-architect" "agent:create-designer"
                "agent:create-stacker" "agent:create-assessor" "agent:create-planner"
                "agent:create-advocate" "agent:create-filer"
                "agent:resolve-researcher" "agent:resolve-planner" "agent:resolve-advocate"
                "agent:resolve-implementor" "agent:resolve-tester" "agent:resolve-reviewer"
                "agent:resolve-opener" "agent:resolve-reviser"
            )
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
                echo "    Run 'forge run' to auto-create missing labels, or 'forge init --resume'"
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
    run)
        shift

        require_forge_skills

        # Parse flags (before dependency checks so --help always works)
        max_budget=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget)   max_budget="$2"; shift 2 ;;
                -h|--help)
                    echo "Usage: forge run [--max-budget N]"
                    echo ""
                    echo "  --max-budget N     Max API spend per stage in USD (API key only)"
                    exit 0
                    ;;
                *) echo "Unknown flag: $1. Run 'forge run --help' for usage."; exit 1 ;;
            esac
        done

        if ! command -v jq &>/dev/null; then
            echo -e "${RED}Error:${NC} jq is required for forge run."
            echo "  Install with: brew install jq"
            exit 1
        fi

        # Validate numeric flags
        if [ -n "$max_budget" ] && ! [[ "$max_budget" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "Error: --max-budget must be a number"; exit 1
        fi

        # Skip --max-budget on subscription plans (only applies to API key usage)
        if [ -n "$max_budget" ]; then
            sub_type=""
            if command -v claude >/dev/null 2>&1; then
                sub_type=$(claude auth status --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('subscriptionType',''))" 2>/dev/null || true)
            fi
            if [ -n "$sub_type" ] && [ "$sub_type" != "none" ]; then
                echo -e "  ${YELLOW}Note:${NC} --max-budget ignored (subscription plan: $sub_type)"
                max_budget=""
            fi
        fi

        # Pre-flight: warn if bypassPermissions is active in local or managed settings
        check_bypass_permissions() {
            local bypass_sources=()

            # Check .claude/settings.local.json
            if [ -f ".claude/settings.local.json" ]; then
                local local_mode
                local_mode=$(python3 -c "import json; d=json.load(open('.claude/settings.local.json')); print(d.get('permissions',{}).get('defaultMode',''))" 2>/dev/null || true)
                if [ "$local_mode" = "bypassPermissions" ]; then
                    bypass_sources+=(".claude/settings.local.json")
                fi
            fi

            # Check managed settings
            local managed="/Library/Application Support/ClaudeCode/managed-settings.json"
            if [ -f "$managed" ]; then
                local managed_mode
                managed_mode=$(python3 -c "import json; d=json.load(open('$managed')); print(d.get('permissions',{}).get('defaultMode',''))" 2>/dev/null || true)
                if [ "$managed_mode" = "bypassPermissions" ]; then
                    bypass_sources+=("$managed")
                fi
            fi

            if [ ${#bypass_sources[@]} -gt 0 ]; then
                echo ""
                echo -e "  ${YELLOW}Warning:${NC} bypassPermissions mode detected in:"
                for src in "${bypass_sources[@]}"; do
                    echo "    - $src"
                done
                echo ""
                echo "  Forge agents rely on tool restrictions in their frontmatter to stay"
                echo "  in their lanes. bypassPermissions may weaken these guardrails."
                echo ""
                read -r -p "  Continue anyway? [y/N] " response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    echo "Aborted."
                    exit 1
                fi
            fi
        }

        check_bypass_permissions

        echo ""
        echo -e "  ${YELLOW}forge run${NC} — pipeline orchestrator"
        [ -n "$max_budget" ] && echo "  Budget per stage: \$$max_budget"
        echo ""

        # --- Auth pre-check ---
        notify_failure() {
            osascript -e "display notification \"$1\" with title \"Forge\"" 2>/dev/null || true
        }

        check_auth() {
            local errors=()

            # GitHub CLI
            if ! command -v gh &>/dev/null; then
                errors+=("GitHub CLI (gh) not found in PATH. Install with: brew install gh")
            elif ! gh auth status &>/dev/null; then
                echo "[forge] GitHub auth invalid. Attempting refresh..."
                if gh auth refresh &>/dev/null; then
                    echo "[forge] GitHub auth refreshed."
                else
                    errors+=("GitHub not authenticated. Run: gh auth login")
                fi
            fi

            # Claude CLI
            if ! command -v claude &>/dev/null; then
                errors+=("Claude CLI not found in PATH. Install from: https://claude.ai/download")
            else
                local logged_in
                logged_in=$(claude auth status --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('loggedIn',''))" 2>/dev/null || true)
                if [ -z "$logged_in" ]; then
                    errors+=("Unable to check Claude auth. Run: claude auth status")
                elif [ "$logged_in" != "True" ]; then
                    errors+=("Claude not authenticated. Run: claude auth login")
                fi
            fi

            if [ ${#errors[@]} -gt 0 ]; then
                echo ""
                echo -e "[forge] ${RED}Auth check failed:${NC}"
                for err in "${errors[@]}"; do
                    echo "  - $err"
                done
                echo ""
                echo "Fix the above, then re-run forge run."
                notify_failure "Auth check failed — see terminal for details"
                exit 1
            fi

            # Warn if using short-lived OAuth (no long-lived token configured) — once per run
            if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${_forge_oauth_warned:-}" ]; then
                _forge_oauth_warned=1
                echo -e "[forge] ${YELLOW}Warning:${NC} No long-lived auth token detected."
                echo "  Short-lived OAuth tokens expire after ~8-12h and may fail during headless runs."
                echo "  Run 'claude setup-token' and set CLAUDE_CODE_OAUTH_TOKEN in your shell profile."
                echo "  See: https://docs.anthropic.com/en/docs/claude-code/cli-usage#non-interactive-mode"
                echo ""
            fi
        }

        # --- Run a Claude Code session ---
        run_claude_session() {
            local skill_invocation="$1"
            local cmd=(claude -p "$skill_invocation")
            [ -n "$max_budget" ] && cmd+=(--max-budget-usd "$max_budget")

            local exit_code=0
            "${cmd[@]}" || exit_code=$?
            return $exit_code
        }

        # --- Creating Pipeline ---
        run_creating_pipeline() {
            echo "[forge] Starting creating pipeline"

            # Find the planning issue by label
            local plan_issue
            plan_issue=$(gh issue list --state open --label "agent:planning" --json number --jq '.[0].number // empty' 2>/dev/null)

            if [ -z "$plan_issue" ]; then
                echo "[forge] No planning issue found."
                return 1
            fi
            echo "[forge] Planning issue: #$plan_issue"

            if ! run_claude_session "/forge-create-orchestrator $plan_issue"; then
                echo "[forge] Creating orchestrator failed."
                return 1
            fi
            echo "[forge] Creating pipeline complete."
        }

        # --- Resolving Pipeline ---
        # Usage: run_resolving_pipeline <issue-number>
        run_resolving_pipeline() {
            local issue="$1"
            echo "[forge] Starting resolving pipeline for issue #$issue"

            if ! run_claude_session "/forge-resolve-orchestrator $issue"; then
                echo "[forge] Resolving orchestrator failed for issue #$issue."
                return 1
            fi
            echo "[forge] Resolving pipeline complete for issue #$issue"
            return 0
        }

        # --- Revise stage (on demand, via resolve orchestrator) ---
        run_revise_stage() {
            local issue="$1"
            echo "[forge] Running revision cycle for issue #$issue"

            if ! run_claude_session "/forge-resolve-orchestrator $issue --revise"; then
                echo "[forge] Revision orchestrator failed for issue #$issue."
                return 1
            fi
            return 0
        }

        # --- Main orchestrator loop ---
        check_auth
        check_labels

        while true; do
            echo "[forge] Determining next action..."
            action=$(determine_next_action)

            case "$action" in
                create)
                    run_creating_pipeline
                    result=$?
                    if [ "$result" -eq 2 ]; then
                        # Pipeline blocked — wait for human
                        echo "[forge] Pipeline blocked. Polling for human response..."
                    elif [ "$result" -ne 0 ]; then
                        echo "[forge] Creating pipeline failed."
                        exit 1
                    fi
                    ;;
                resolve:*)
                    issue="${action#resolve:}"
                    run_resolving_pipeline "$issue"
                    result=$?
                    if [ "$result" -eq 2 ]; then
                        echo "[forge] Pipeline blocked on issue #$issue. Continuing..."
                    elif [ "$result" -ne 0 ]; then
                        echo "[forge] Resolving pipeline failed on issue #$issue. Continuing..."
                    fi
                    ;;
                revise:*)
                    issue="${action#revise:}"
                    run_revise_stage "$issue"
                    ;;
                wait)
                    echo "[forge] Waiting for human input or PR merge. Polling every 60s..."
                    while true; do
                        sleep 60
                        check_auth
                        next=$(determine_next_action)
                        if [ "$next" != "wait" ]; then
                            echo "[forge] Change detected. Resuming..."
                            break
                        fi
                    done
                    ;;
                done)
                    echo ""
                    echo "[forge] All issues closed. Project complete!"
                    exit 0
                    ;;
                *)
                    echo "[forge] Unexpected action: $action"
                    exit 1
                    ;;
            esac
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
        echo "Commands:"
        echo "  init             Bootstrap a new Forge project (requires PROMPT.md)"
        echo "  init --resume    Resume a failed or interrupted bootstrap"
        echo "  run              Run the autonomous build loop (headless)"
        echo "  update           Update Forge to the latest version"
        echo "  upgrade          Update Forge artifacts in the current project"
        echo "  doctor           Check tool versions and project health"
        echo "  uninstall        Remove Forge from your system"
        echo ""
        echo "Flags:"
        echo "  --version          Show installed version"
        echo ""
        echo "Run 'forge <command> --help' for detailed help on a command."
        echo ""
        echo "Quick start:"
        echo "  1. mkdir my-app && cd my-app"
        echo "  2. Write a PROMPT.md describing your app"
        echo "  3. forge init"
        echo "  4. forge run"
        ;;
esac
