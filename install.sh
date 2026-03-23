#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "Error: Forge requires macOS."; exit 1; }

# Forge Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/allan-mobley-jr/forge/main/install.sh | bash

FORGE_HOME="$HOME/.forge"
FORGE_REPO="$FORGE_HOME/repo"
FORGE_BIN="$FORGE_HOME/bin"
FORGE_REMOTE="https://github.com/allan-mobley-jr/forge.git"

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
    retry git -C "$FORGE_REPO" fetch --quiet --tags
else
    echo -e "${BLUE}Installing Forge...${NC}"
    mkdir -p "$FORGE_HOME"
    retry git clone --quiet "$FORGE_REMOTE" "$FORGE_REPO"
fi

# Checkout latest tag (release) if available, otherwise use main
latest_tag=$(git -C "$FORGE_REPO" describe --tags --abbrev=0 2>/dev/null || true)
if [ -n "$latest_tag" ]; then
    git -C "$FORGE_REPO" checkout "$latest_tag" --quiet 2>/dev/null || true
    echo -e "${GREEN}Forge installed ($latest_tag).${NC}"
else
    git -C "$FORGE_REPO" reset --hard origin/main --quiet
    echo -e "${GREEN}Forge installed ($(git -C "$FORGE_REPO" rev-parse --short HEAD)).${NC}"
fi

# --- Step 3: Symlink the forge CLI ---

mkdir -p "$FORGE_BIN"

# Remove old generated CLI if it exists (upgrade from heredoc to symlink)
[ -f "$FORGE_BIN/forge" ] && [ ! -L "$FORGE_BIN/forge" ] && rm -f "$FORGE_BIN/forge"

ln -sf "$FORGE_REPO/cli/forge.sh" "$FORGE_BIN/forge"

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
echo "    forge run"
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
