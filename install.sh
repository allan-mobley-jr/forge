#!/usr/bin/env bash
set -euo pipefail

# Forge Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

FORGE_HOME="$HOME/.forge"
FORGE_REPO="$FORGE_HOME/repo"
FORGE_BIN="$FORGE_HOME/bin"
FORGE_REMOTE="https://github.com/allan-mobley-jr/forge.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;208m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Retry helper
retry() {
    local max_attempts=3 delay=2 attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        if "$@"; then return 0; fi
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
echo ""
echo "  Autonomous Next.js Development"
echo ""

# --- Step 1: Check git ---

if ! command -v git &>/dev/null; then
    echo -e "${RED}Error:${NC} git is required but not installed."
    echo ""
    echo "  Install git for your platform:"
    echo "    macOS:   xcode-select --install"
    echo "    Ubuntu:  sudo apt install git"
    echo "    Fedora:  sudo dnf install git"
    echo "    Windows: https://git-scm.com/downloads"
    echo ""
    echo "  Then re-run this installer."
    exit 1
fi

# --- Step 2: Clone or update ---

if [ -d "$FORGE_REPO/.git" ]; then
    echo -e "${BLUE}Updating Forge...${NC}"
    retry git -C "$FORGE_REPO" fetch --quiet --tags
else
    echo -e "${BLUE}Installing Forge...${NC}"
    mkdir -p "$FORGE_HOME"
    retry git clone --quiet "$FORGE_REMOTE" "$FORGE_REPO"
fi

# Checkout highest semver tag (release) if available, otherwise use main
latest_tag=$(git -C "$FORGE_REPO" tag -l 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
if [ -n "$latest_tag" ]; then
    git -C "$FORGE_REPO" checkout "$latest_tag" --quiet 2>/dev/null || {
        echo -e "${RED}Error:${NC} Failed to checkout $latest_tag."
        echo "  Check for issues in $FORGE_REPO and re-run the installer."
        exit 1
    }
    echo -e "${GREEN}Forge installed ($latest_tag).${NC}"
else
    git -C "$FORGE_REPO" reset --hard origin/main --quiet
    echo -e "${GREEN}Forge installed ($(git -C "$FORGE_REPO" rev-parse --short HEAD)).${NC}"
fi

# --- Step 3: Symlink the forge CLI ---

mkdir -p "$FORGE_BIN"

# Remove old generated CLI if it exists (upgrade from heredoc to symlink)
[ -f "$FORGE_BIN/forge" ] && [ ! -L "$FORGE_BIN/forge" ] && rm -f "$FORGE_BIN/forge"

ln -sf "$FORGE_REPO/bin/forge.sh" "$FORGE_BIN/forge"

# --- Step 4: Install Forge plugin + dependencies ---

if command -v claude &>/dev/null; then
    echo -e "${BLUE}Setting up Forge plugin...${NC}"

    # Add the Forge repo as a marketplace (idempotent)
    if ! claude plugin marketplace list 2>/dev/null | grep -q "forge"; then
        claude plugin marketplace add "$FORGE_REPO" 2>/dev/null \
            && echo -e "  ${GREEN}[x]${NC} Forge marketplace registered" \
            || echo -e "  ${YELLOW}[!]${NC} Marketplace registration failed. Run manually: claude plugin marketplace add $FORGE_REPO"
    fi

    # Install plugins unconditionally (install is idempotent and re-enables disabled plugins)
    claude plugin install forge@forge 2>/dev/null \
        && echo -e "  ${GREEN}[x]${NC} Forge plugin installed" \
        || echo -e "  ${YELLOW}[!]${NC} Plugin install failed. Run manually: claude plugin install forge@forge"

    claude plugin install vercel@claude-plugins-official 2>/dev/null \
        && echo -e "  ${GREEN}[x]${NC} Vercel plugin installed" \
        || echo -e "  ${YELLOW}[!]${NC} Vercel plugin failed. Run manually: claude plugin install vercel@claude-plugins-official"

    claude plugin install playwright@claude-plugins-official 2>/dev/null \
        && echo -e "  ${GREEN}[x]${NC} Playwright plugin installed" \
        || echo -e "  ${YELLOW}[!]${NC} Playwright plugin failed. Run manually: claude plugin install playwright@claude-plugins-official"

    claude plugin install pr-review-toolkit@claude-plugins-official 2>/dev/null \
        && echo -e "  ${GREEN}[x]${NC} PR Review Toolkit plugin installed" \
        || echo -e "  ${YELLOW}[!]${NC} PR Review Toolkit plugin failed. Run manually: claude plugin install pr-review-toolkit@claude-plugins-official"
else
    echo -e "${RED}Error:${NC} Claude Code is required but not found in PATH."
    echo "  Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
    echo "  Then re-run this installer."
    exit 1
fi

echo ""

# --- Step 5: Add to PATH ---

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

# --- Done ---

echo ""
echo -e "${GREEN}Forge is installed.${NC}"
echo ""
echo "  To start a new project:"
echo ""
echo "    mkdir my-app && cd my-app"
echo "    forge init"
echo ""

if [ -n "$SHELL_RC" ]; then
    echo -e "  ${YELLOW}Note:${NC} Restart your terminal or run ${BOLD}source $SHELL_RC${NC} to use the forge command."
    echo ""
fi
