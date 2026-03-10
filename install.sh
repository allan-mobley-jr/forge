#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "Error: Forge requires macOS."; exit 1; }

# Forge Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

FORGE_HOME="$HOME/.forge"
FORGE_REPO="$FORGE_HOME/repo"
FORGE_BIN="$FORGE_HOME/bin"
FORGE_REMOTE="https://github.com/allan-mobley-jr/forge.git"

# --- Step 1: Ensure git, clone/update repo, show banner ---

# --- Retry helper ---

retry() {
    local max_attempts=3
    local delay=2
    local attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -lt "$max_attempts" ]; then
            echo -e "  ${YELLOW}Retrying in ${delay}s... (attempt $((attempt+1))/$max_attempts)${NC}"
            sleep "$delay"
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    echo -e "${RED}Failed after $max_attempts attempts.${NC}"
    return 1
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "  ${YELLOW}███████╗ ██████╗ ██████╗  ██████╗ ███████╗${NC}"
echo -e "  ${YELLOW}██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝${NC}"
echo -e "  ${YELLOW}█████╗  ██║   ██║██████╔╝██║  ███╗█████╗${NC}"
echo -e "  ${YELLOW}██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝${NC}"
echo -e "  ${YELLOW}██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗${NC}"
echo -e "  ${YELLOW}╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
echo ""
echo "  Autonomous Next.js Development"
echo ""

# --- Step 1: Ensure git is available (install Apple CLT if needed) ---

if ! command -v git &>/dev/null; then
    echo -e "${BLUE}Installing Apple Command Line Tools (includes git)...${NC}"
    xcode-select --install 2>/dev/null
    echo ""
    echo "  A system dialog should have appeared."
    echo "  Click ${BOLD}Install${NC} and wait for it to finish."
    echo ""

    timeout=300
    elapsed=0
    while ! xcode-select -p &>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo -e "${RED}Error:${NC} Timed out waiting for Command Line Tools."
            echo "  Install manually: xcode-select --install"
            echo "  Then re-run this installer."
            exit 1
        fi
    done

    echo -e "${GREEN}Command Line Tools installed.${NC}"
fi

# --- Step 2: Clone or update the Forge repository ---

if [ -d "$FORGE_REPO/.git" ]; then
    echo -e "${BLUE}Updating Forge...${NC}"
    retry git -C "$FORGE_REPO" fetch --quiet
    git -C "$FORGE_REPO" reset --hard origin/main --quiet
    echo -e "${GREEN}Forge updated.${NC}"
else
    echo -e "${BLUE}Installing Forge...${NC}"
    mkdir -p "$FORGE_HOME"
    retry git clone --quiet "$FORGE_REMOTE" "$FORGE_REPO"
    echo -e "${GREEN}Forge installed to $FORGE_REPO${NC}"
fi

# --- Step 3: Create the forge command ---

mkdir -p "$FORGE_BIN"

cat > "$FORGE_BIN/forge" <<'FORGE_CMD'
#!/usr/bin/env bash
set -euo pipefail

FORGE_REPO="$HOME/.forge/repo"

# Colors
RED='\033[0;31m'
BOLD='\033[1m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

if [ ! -d "$FORGE_REPO" ]; then
    echo "Error: Forge is not installed. Run:"
    echo '  curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash'
    exit 1
fi

case "${1:-}" in
    init)
        FORGE_RESUME=false
        if [ "${2:-}" = "--resume" ]; then
            FORGE_RESUME=true
        fi

        FORGE_VERSION=$(git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD)

        echo ""
        echo -e "  ${YELLOW}███████╗ ██████╗ ██████╗  ██████╗ ███████╗${NC}"
        echo -e "  ${YELLOW}██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝${NC}"
        echo -e "  ${YELLOW}█████╗  ██║   ██║██████╔╝██║  ███╗█████╗${NC}"
        echo -e "  ${YELLOW}██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝${NC}"
        echo -e "  ${YELLOW}██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗${NC}"
        echo -e "  ${YELLOW}╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
        echo ""
        echo -e "  Autonomous Next.js Development      ${DIM}${FORGE_VERSION}${NC}"
        echo ""

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
        curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash
        exit $?
        ;;
    upgrade)
        # Colors for upgrade output
        GREEN='\033[0;32m'
        RED='\033[0;31m'

        # 1. Verify inside a Forge project
        if [ ! -d ".claude/skills" ]; then
            echo -e "${RED}Error:${NC} Not a Forge project."
            echo "  Run this command from inside a Forge project directory."
            exit 1
        fi

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
        # Colors for doctor output
        GREEN='\033[0;32m'
        RED='\033[0;31m'

        # 1. Verify inside a Forge project
        if [ ! -d ".claude/skills" ]; then
            echo -e "${RED}Error:${NC} Not a Forge project."
            echo "  Run this command from inside a Forge project directory."
            exit 1
        fi

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

        # 6. Check disk space
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
    status)
        GREEN='\033[0;32m'
        RED='\033[0;31m'
        BLUE='\033[0;34m'

        if [ ! -d ".claude/skills" ]; then
            echo -e "${RED}Error:${NC} Not a Forge project."
            exit 1
        fi

        echo ""
        echo "Forge Status"
        echo "============"
        echo ""

        if [ -f .forge-temp/status.json ]; then
            python3 -c "
import json
with open('.forge-temp/status.json') as f:
    d = json.load(f)
ts = d.get('timestamp', 'unknown')
iss = d.get('issues', {})
print(f'  Last sync: {ts}')
print(f'  Total issues: {iss.get("total", 0)}')
print(f'  Closed: {iss.get("closed", 0)}')
print(f'  Ready: {iss.get("ready", 0)}')
print(f'  In progress: {iss.get("in_progress", 0)}')
print(f'  Blocked: {iss.get("blocked", 0)}')
print(f'  Needs human: {iss.get("needs_human", 0)}')
print(f'  Revision needed: {iss.get("revision_needed", 0)}')
print(f'  Awaiting merge: {iss.get("done_awaiting_merge", 0)}')
total = iss.get('total', 0)
closed = iss.get('closed', 0)
if total > 0:
    pct = int(closed / total * 100)
    print(f'\n  Progress: {closed}/{total} ({pct}%)')
"
        else
            echo "  No status file found. Run a Forge session first."
            echo "  Start with: claude"
        fi

        if [ -f .forge-temp/exit-status ]; then
            echo ""
            echo "  Last exit status: $(cat .forge-temp/exit-status)"
        fi
        echo ""
        ;;
    run)
        shift

        # Verify inside a Forge project
        if [ ! -d ".claude/skills" ]; then
            echo -e "${RED}Error: Not a Forge project.${NC}"
            echo "  Run this command from inside a Forge project directory."
            exit 1
        fi

        # Parse flags
        max_budget=""
        timeout_secs=""

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max-budget)   max_budget="$2"; shift 2 ;;
                --timeout)      timeout_secs="$2"; shift 2 ;;
                -h|--help)
                    echo "Usage: forge run [--max-budget N] [--timeout N]"
                    echo ""
                    echo "  --max-budget N     Max API spend per stage in USD"
                    echo "  --timeout N        Wall-clock timeout per stage in seconds"
                    exit 0
                    ;;
                *) echo "Unknown flag: $1. Run 'forge run --help' for usage."; exit 1 ;;
            esac
        done

        # Validate numeric flags
        if [ -n "$max_budget" ] && ! [[ "$max_budget" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "Error: --max-budget must be a number"; exit 1
        fi
        if [ -n "$timeout_secs" ] && ! [[ "$timeout_secs" =~ ^[0-9]+$ ]]; then
            echo "Error: --timeout must be a positive integer (seconds)"; exit 1
        fi

        # Resolve timeout command (GNU coreutils installs as gtimeout on macOS)
        timeout_cmd=""
        if [ -n "$timeout_secs" ]; then
            if command -v timeout &>/dev/null; then
                timeout_cmd="timeout"
            elif command -v gtimeout &>/dev/null; then
                timeout_cmd="gtimeout"
            else
                echo "Error: --timeout requires GNU coreutils."
                echo "  Install with: brew install coreutils"
                exit 1
            fi
        fi

        echo ""
        echo -e "  ${YELLOW}forge run${NC} — pipeline orchestrator"
        [ -n "$max_budget" ] && echo "  Budget per stage: \$$max_budget"
        [ -n "$timeout_secs" ] && echo "  Timeout per stage: ${timeout_secs}s"
        echo ""

        # --- Auth pre-check ---
        check_auth() {
            if ! command -v gh &>/dev/null; then
                echo "[forge] GitHub CLI (gh) not found in PATH."; exit 1
            elif ! gh auth status &>/dev/null; then
                echo "[forge] GitHub auth expired. Run: gh auth refresh"; exit 1
            fi
            if ! command -v claude &>/dev/null; then
                echo "[forge] Claude CLI not found in PATH."; exit 1
            fi
        }

        # --- Run a single stage ---
        # Usage: run_stage <skill-name> <issue-number> <stage-header>
        # Returns 0 on success (comment with header found), 1 on failure
        run_stage() {
            local skill="$1" issue="$2" header="$3"
            local attempt=0 max_attempts=2

            while [ "$attempt" -lt "$max_attempts" ]; do
                attempt=$((attempt + 1))
                echo "[forge]   Stage: $skill (attempt $attempt/$max_attempts)"

                check_auth

                local cmd=(claude -p "/forge-${skill} ${issue}")
                [ -n "$max_budget" ] && cmd+=(--max-budget-usd "$max_budget")

                local exit_code=0
                if [ -n "$timeout_cmd" ]; then
                    "$timeout_cmd" "$timeout_secs" "${cmd[@]}" || exit_code=$?
                else
                    "${cmd[@]}" || exit_code=$?
                fi

                # Verify stage output: comment with matching header exists
                if gh issue view "$issue" --json comments \
                    --jq ".comments[].body" 2>/dev/null | grep -q "## \[Stage: ${header}\]"; then

                    # Check for BLOCKED status
                    local last_comment
                    last_comment=$(gh issue view "$issue" --json comments \
                        --jq "[.comments[].body | select(contains(\"## [Stage: ${header}]\"))] | last")
                    if echo "$last_comment" | grep -q "### Status: BLOCKED"; then
                        echo "[forge]   Stage $skill: BLOCKED"
                        return 2
                    fi
                    echo "[forge]   Stage $skill: COMPLETE"
                    return 0
                fi

                if [ "$attempt" -lt "$max_attempts" ]; then
                    echo "[forge]   Stage output not found. Retrying..."
                fi
            done

            echo "[forge]   Stage $skill: FAILED after $max_attempts attempts"
            return 1
        }

        # --- Set stage label on an issue ---
        set_stage_label() {
            local issue="$1" label="$2"
            # Remove any existing stage: labels
            local existing
            existing=$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(startswith("stage:"))] | .[]' 2>/dev/null || true)
            for old_label in $existing; do
                gh issue edit "$issue" --remove-label "$old_label" 2>/dev/null || true
            done
            # Ensure label exists and add it
            gh label create "$label" --color "1d76db" --force 2>/dev/null || true
            gh issue edit "$issue" --add-label "$label" 2>/dev/null || true
        }

        # --- Escalate to human ---
        escalate() {
            local issue="$1" reason="$2"
            gh issue comment "$issue" --body "## Agent Question

$reason

*Escalated automatically by the Forge pipeline orchestrator.*"
            gh label create "agent:needs-human" --color "d93f0b" --force 2>/dev/null || true
            gh issue edit "$issue" --add-label "agent:needs-human" 2>/dev/null || true
            # Remove stage labels
            local existing
            existing=$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(startswith("stage:"))] | .[]' 2>/dev/null || true)
            for old_label in $existing; do
                gh issue edit "$issue" --remove-label "$old_label" 2>/dev/null || true
            done
        }

        # --- Creating Pipeline ---
        run_creating_pipeline() {
            local project_name
            project_name=$(basename "$(pwd)")
            echo "[forge] Starting creating pipeline for: $project_name"

            # Create planning issue
            local plan_issue
            plan_issue=$(gh issue create \
                --title "Planning: $project_name" \
                --body "Forge creating pipeline. Stages will post their analysis as comments on this issue." \
                --label "ai-generated" 2>/dev/null | grep -o '[0-9]*$')

            if [ -z "$plan_issue" ]; then
                echo "[forge] Failed to create planning issue."
                return 1
            fi
            echo "[forge] Planning issue: #$plan_issue"

            # Stage definitions: skill-suffix stage-header
            local stages=(
                "project-researcher:Researcher"
                "project-architect:Architect"
                "project-designer:Designer"
                "project-stacker:Stacker"
                "project-assessor:Assessor"
                "project-planner:Planner"
                "project-advocate:Advocate"
                "project-filer:Filer"
            )

            for stage_def in "${stages[@]}"; do
                local skill="${stage_def%%:*}"
                local header="${stage_def##*:}"

                set_stage_label "$plan_issue" "stage:$skill"

                local result=0
                run_stage "$skill" "$plan_issue" "$header" || result=$?

                if [ "$result" -eq 1 ]; then
                    # Terminal failure
                    escalate "$plan_issue" "Stage **$skill** failed after 2 attempts. No stage output was produced. Manual intervention required."
                    echo "[forge] Creating pipeline failed at stage: $skill"
                    return 1
                elif [ "$result" -eq 2 ]; then
                    # BLOCKED status
                    if [ "$skill" = "project-advocate" ]; then
                        # Check for ESCALATE verdict
                        local advocate_comment
                        advocate_comment=$(gh issue view "$plan_issue" --json comments \
                            --jq '[.comments[].body | select(contains("## [Stage: Advocate]"))] | last')
                        if echo "$advocate_comment" | grep -q "### Verdict: ESCALATE"; then
                            escalate "$plan_issue" "The advocate stage escalated this plan to a human.

$(echo "$advocate_comment" | sed -n '/### Challenges/,/### Verdict/p')"
                            echo "[forge] Advocate escalated. Waiting for human input."
                            return 2
                        fi
                    fi
                    escalate "$plan_issue" "Stage **$skill** reported BLOCKED status. Check the stage comment for details."
                    echo "[forge] Creating pipeline blocked at stage: $skill"
                    return 2
                fi

                # Special: Advocate REVISE verdict → re-run planner then advocate (max 1 cycle)
                if [ "$skill" = "project-advocate" ]; then
                    local advocate_comment
                    advocate_comment=$(gh issue view "$plan_issue" --json comments \
                        --jq '[.comments[].body | select(contains("## [Stage: Advocate]"))] | last')
                    if echo "$advocate_comment" | grep -q "### Verdict: REVISE"; then
                        echo "[forge]   Advocate verdict: REVISE. Re-running planner..."
                        set_stage_label "$plan_issue" "stage:project-planner"
                        run_stage "project-planner" "$plan_issue" "Planner" || true
                        echo "[forge]   Re-running advocate..."
                        set_stage_label "$plan_issue" "stage:project-advocate"
                        run_stage "project-advocate" "$plan_issue" "Advocate" || true
                        # After revision cycle, proceed regardless
                        echo "[forge]   Revision cycle complete. Proceeding to filer."
                    fi
                fi
            done

            # Remove stage label after completion
            local existing
            existing=$(gh issue view "$plan_issue" --json labels --jq '[.labels[].name | select(startswith("stage:"))] | .[]' 2>/dev/null || true)
            for old_label in $existing; do
                gh issue edit "$plan_issue" --remove-label "$old_label" 2>/dev/null || true
            done

            echo "[forge] Creating pipeline complete."
            return 0
        }

        # --- Resolving Pipeline ---
        # Usage: run_resolving_pipeline <issue-number>
        run_resolving_pipeline() {
            local issue="$1"
            echo "[forge] Starting resolving pipeline for issue #$issue"

            local stages=(
                "issue-researcher:Researcher"
                "issue-planner:Planner"
                "issue-implementor:Implementor"
                "issue-tester:Tester"
                "issue-reviewer:Reviewer"
                "issue-opener:Opener"
            )

            for stage_def in "${stages[@]}"; do
                local skill="${stage_def%%:*}"
                local header="${stage_def##*:}"

                set_stage_label "$issue" "stage:$skill"

                local result=0
                run_stage "$skill" "$issue" "$header" || result=$?

                if [ "$result" -eq 1 ]; then
                    escalate "$issue" "Stage **$skill** failed after 2 attempts. No stage output was produced. Manual intervention required."
                    echo "[forge] Resolving pipeline failed at stage: $skill"
                    return 1
                elif [ "$result" -eq 2 ]; then
                    escalate "$issue" "Stage **$skill** reported BLOCKED status. Check the stage comment for details."
                    echo "[forge] Resolving pipeline blocked at stage: $skill"
                    return 2
                fi
            done

            # Mark as done
            gh label create "agent:done" --color "0e8a16" --force 2>/dev/null || true
            gh issue edit "$issue" --add-label "agent:done" 2>/dev/null || true
            # Remove stage labels
            local existing
            existing=$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(startswith("stage:"))] | .[]' 2>/dev/null || true)
            for old_label in $existing; do
                gh issue edit "$issue" --remove-label "$old_label" 2>/dev/null || true
            done

            echo "[forge] Resolving pipeline complete for issue #$issue"
            return 0
        }

        # --- Revise stage (on demand) ---
        run_revise_stage() {
            local issue="$1"
            echo "[forge] Running reviser for issue #$issue"

            set_stage_label "$issue" "stage:issue-reviser"

            local result=0
            run_stage "issue-reviser" "$issue" "Reviser" || result=$?

            # Remove stage label
            gh issue edit "$issue" --remove-label "stage:issue-reviser" 2>/dev/null || true

            if [ "$result" -eq 1 ]; then
                escalate "$issue" "Reviser stage failed after 2 attempts."
                return 1
            elif [ "$result" -eq 2 ]; then
                # BLOCKED = revision limit or quality check failure
                escalate "$issue" "Reviser reported BLOCKED status. Check the stage comment for details."
                return 2
            fi

            return 0
        }

        # --- Determine next action ---
        # Prints one of: create, resolve:<issue>, revise:<issue>, wait, done
        determine_next_action() {
            # Check for needs-human issues with responses
            local needs_human_json
            if needs_human_json=$(gh issue list --state open --label "agent:needs-human" \
                --json number,comments -L 200 2>/dev/null); then
                local responded_issue
                responded_issue=$(echo "$needs_human_json" | python3 -c "
import json, sys, re
issues = json.load(sys.stdin)
agent_header = re.compile(r'^## (Agent Question|Build Failed|Revision Limit Reached|Merge Conflict|Acknowledged|\[Stage:)', re.MULTILINE)
for issue in issues:
    comments = issue.get('comments', [])
    q_idx = -1
    for i, c in enumerate(comments):
        if agent_header.search(c.get('body', '')):
            q_idx = i
    if q_idx >= 0:
        for c in comments[q_idx + 1:]:
            if not agent_header.search(c.get('body', '')):
                print(issue['number'])
                sys.exit(0)
# Check 24h timeout
from datetime import datetime, timezone
now = datetime.now(timezone.utc)
for issue in issues:
    comments = issue.get('comments', [])
    for c in reversed(comments):
        if agent_header.search(c.get('body', '')):
            created = c.get('createdAt', '')
            if created:
                t = datetime.fromisoformat(created.replace('Z', '+00:00'))
                if (now - t).total_seconds() >= 86400:
                    print(issue['number'])
                    sys.exit(0)
            break
" 2>/dev/null)
                if [ -n "$responded_issue" ]; then
                    # Remove needs-human label, add back to backlog for resolving
                    gh issue edit "$responded_issue" --remove-label "agent:needs-human" 2>/dev/null || true
                    echo "resolve:$responded_issue"
                    return
                fi
            fi

            # Check for agent:done issues needing revision (CHANGES_REQUESTED on PR)
            local done_issues
            done_issues=$(gh issue list --state open --label "agent:done" --json number -L 200 --jq '.[].number' 2>/dev/null || true)
            for done_issue in $done_issues; do
                local pr_review
                pr_review=$(gh pr list --search "closes #$done_issue" --json reviewDecision --jq '.[0].reviewDecision' 2>/dev/null || true)
                if [ "$pr_review" = "CHANGES_REQUESTED" ]; then
                    echo "revise:$done_issue"
                    return
                fi
                # Check for CI failures
                local pr_number
                pr_number=$(gh pr list --search "closes #$done_issue" --json number --jq '.[0].number' 2>/dev/null || true)
                if [ -n "$pr_number" ]; then
                    local ci_status
                    ci_status=$(gh pr checks "$pr_number" 2>/dev/null | grep -c "fail" || true)
                    if [ "$ci_status" -gt 0 ]; then
                        echo "revise:$done_issue"
                        return
                    fi
                fi
            done

            # Check for in-progress stage issues (resume interrupted pipeline)
            local stage_issues
            stage_issues=$(gh issue list --state open --json number,labels -L 200 --jq '
                [.[] | select(.labels | map(.name) | any(startswith("stage:")))] | sort_by(.number) | .[0].number // empty
            ' 2>/dev/null || true)
            if [ -n "$stage_issues" ]; then
                # Determine which pipeline based on the stage label
                local stage_label
                stage_label=$(gh issue view "$stage_issues" --json labels --jq '[.labels[].name | select(startswith("stage:"))] | .[0]' 2>/dev/null || true)
                if echo "$stage_label" | grep -q "project-"; then
                    # Creating pipeline was interrupted — but we can't easily resume mid-pipeline
                    # Remove stale label and let it re-create
                    gh issue edit "$stage_issues" --remove-label "$stage_label" 2>/dev/null || true
                    echo "create"
                    return
                elif echo "$stage_label" | grep -q "issue-"; then
                    echo "resolve:$stage_issues"
                    return
                fi
            fi

            # Check for backlog issues (no agent:* or stage:* labels)
            local backlog_issue
            backlog_issue=$(gh issue list --state open --json number,labels -L 200 --jq '
                [.[] | select(.labels | map(.name) | all(
                    (startswith("agent:") | not) and (startswith("stage:") | not)
                ))] | sort_by(.number) | .[0].number // empty
            ' 2>/dev/null || true)
            if [ -n "$backlog_issue" ]; then
                echo "resolve:$backlog_issue"
                return
            fi

            # Check if PROMPT.md exists and no issues have been filed yet (need planning)
            if [ -f "PROMPT.md" ]; then
                local total_issues
                total_issues=$(gh issue list --state all --json number -L 1 --jq 'length' 2>/dev/null || true)
                if [ "${total_issues:-0}" -eq 0 ]; then
                    echo "create"
                    return
                fi
                # Check for graveyard — if PROMPT.md exists but hasn't been archived, might need re-planning
                if [ ! -d "graveyard" ]; then
                    # PROMPT.md exists, issues exist, no graveyard — could be mid-planning
                    # Check if any planning issues exist
                    local planning_issues
                    planning_issues=$(gh issue list --state all --search "Planning:" --json number -L 1 --jq 'length' 2>/dev/null || true)
                    if [ "${planning_issues:-0}" -eq 0 ]; then
                        echo "create"
                        return
                    fi
                fi
            fi

            # Check if all issues are closed
            local open_count
            open_count=$(gh issue list --state open --json number -L 200 --jq 'length' 2>/dev/null || true)
            if [ "${open_count:-0}" -eq 0 ]; then
                # Check for audit mode (graveyard exists, all closed)
                if [ -d "graveyard" ]; then
                    echo "done"
                    return
                fi
            fi

            # Needs-human issues still open with no response, or agent:done PRs awaiting merge
            if [ -n "$done_issues" ] || [ -n "$needs_human_json" ]; then
                echo "wait"
                return
            fi

            echo "done"
        }

        # --- Main orchestrator loop ---
        check_auth

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
    help)
        case "${2:-}" in
            init)
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
                ;;
            run)
                echo "forge run — Pipeline orchestrator"
                echo ""
                echo "Usage: forge run [--max-budget N] [--timeout N]"
                echo ""
                echo "Bash-orchestrated pipeline manager. Determines the next action"
                echo "from GitHub state and runs stage-by-stage pipelines:"
                echo ""
                echo "  Creating pipeline: 8 stages (research → architect → design → stack → assess → plan → advocate → file)"
                echo "  Resolving pipeline: 6 stages (research → plan → implement → test → review → open PR)"
                echo "  Revision: on-demand (handles PR review feedback and CI failures)"
                echo ""
                echo "Each stage is a fresh claude -p session. Bash manages labels,"
                echo "verifies stage output, and advances the pipeline."
                echo ""
                echo "Options:"
                echo "  --max-budget N     API spend cap per stage in USD"
                echo "  --timeout N        Wall-clock timeout per stage in seconds"
                ;;
            status)
                echo "forge status — Show current project progress"
                echo ""
                echo "Usage: forge status"
                echo ""
                echo "Reads .forge-temp/status.json (written by /forge after each /sync)"
                echo "and displays issue counts, completion percentage, and last exit status."
                ;;
            update)
                echo "forge update — Update Forge itself"
                echo ""
                echo "Usage: forge update"
                echo ""
                echo "Pulls the latest version of Forge from GitHub and regenerates"
                echo "the CLI. Run 'forge upgrade' inside a project to update its artifacts."
                ;;
            upgrade)
                echo "forge upgrade — Update project artifacts"
                echo ""
                echo "Usage: forge upgrade"
                echo ""
                echo "Updates skills, hooks, and CLAUDE.md in the current Forge project"
                echo "to match the installed Forge version. Creates a backup first."
                echo ""
                echo "Backs up to .forge-backup-YYYY-MM-DD-HHMMSS/"
                ;;
            doctor)
                echo "forge doctor — Health check"
                echo ""
                echo "Usage: forge doctor"
                echo ""
                echo "Checks tool versions, authentication, disk space, and whether"
                echo "project artifacts are up-to-date with the installed Forge version."
                ;;
            uninstall)
                echo "forge uninstall — Remove Forge"
                echo ""
                echo "Usage: forge uninstall"
                echo ""
                echo "Removes ~/.forge (repo + CLI binary) and PATH entries from"
                echo "shell config files. Does NOT affect existing Forge projects."
                ;;
            "")
                echo "Usage: forge help <command>"
                echo ""
                echo "Commands: init, run, status, update, upgrade, doctor, uninstall, version"
                ;;
            *)
                echo "Unknown command: $2"
                echo "Run 'forge help' for available commands."
                ;;
        esac
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
    version)
        echo "Forge $(git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD)"
        ;;
    *)
        FORGE_VERSION=$(git -C "$FORGE_REPO" describe --tags 2>/dev/null || git -C "$FORGE_REPO" rev-parse --short HEAD)

        echo ""
        echo -e "  ${YELLOW}███████╗ ██████╗ ██████╗  ██████╗ ███████╗${NC}"
        echo -e "  ${YELLOW}██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝${NC}"
        echo -e "  ${YELLOW}█████╗  ██║   ██║██████╔╝██║  ███╗█████╗${NC}"
        echo -e "  ${YELLOW}██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝${NC}"
        echo -e "  ${YELLOW}██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗${NC}"
        echo -e "  ${YELLOW}╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
        echo ""
        echo -e "  Autonomous Next.js Development      ${DIM}${FORGE_VERSION}${NC}"
        echo ""
        echo "Usage: forge <command>"
        echo ""
        echo "Commands:"
        echo "  init             Bootstrap a new Forge project (requires PROMPT.md)"
        echo "  init --resume    Resume a failed or interrupted bootstrap"
        echo "  run              Run the autonomous build loop (headless, with restarts)"
        echo "  status           Show current project progress"
        echo "  update           Update Forge to the latest version"
        echo "  upgrade          Update Forge artifacts in the current project"
        echo "  doctor           Check tool versions and project health"
        echo "  uninstall        Remove Forge from your system"
        echo "  version          Show installed version"
        echo "  help <command>   Show detailed help for a command"
        echo ""
        echo "Run flags:"
        echo "  --max-budget N     Max API spend per stage in USD"
        echo "  --timeout N        Wall-clock timeout per stage in seconds"
        echo ""
        echo "Quick start:"
        echo "  1. mkdir my-app && cd my-app"
        echo "  2. Write a PROMPT.md describing your app"
        echo "  3. forge init"
        echo "  4. claude"
        ;;
esac
FORGE_CMD

chmod +x "$FORGE_BIN/forge"

# --- Step 4: Add to PATH ---

SHELL_RC=""
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "bash" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q '\.forge/bin' "$SHELL_RC" 2>/dev/null; then
        echo '' >> "$SHELL_RC"
        echo '# Forge' >> "$SHELL_RC"
        echo 'export PATH="$HOME/.forge/bin:$PATH"' >> "$SHELL_RC"
        echo -e "${GREEN}Added Forge to PATH in $SHELL_RC${NC}"
    fi
fi

# --- Done ---

echo ""
echo -e "${GREEN}Forge is installed.${NC}"
echo ""
echo "  To start a new project:"
echo ""
echo "    mkdir my-app && cd my-app"
echo "    # Describe your app in PROMPT.md"
echo "    forge init"
echo "    claude"
echo ""
# Fish shell support
FISH_CONFIG="$HOME/.config/fish/conf.d/forge.fish"
if [ "$(basename "${SHELL:-}")" = "fish" ] || [ -d "$HOME/.config/fish" ]; then
    if [ ! -f "$FISH_CONFIG" ]; then
        mkdir -p "$(dirname "$FISH_CONFIG")"
        echo '# Forge' > "$FISH_CONFIG"
        echo 'fish_add_path -g $HOME/.forge/bin' >> "$FISH_CONFIG"
        echo -e "${GREEN}Added Forge to PATH for fish shell${NC}"
    fi
fi

if [ -n "$SHELL_RC" ]; then
    echo -e "  ${YELLOW}Note:${NC} Restart your terminal or run ${BOLD}source $SHELL_RC${NC} to use the forge command."
    echo ""
fi
