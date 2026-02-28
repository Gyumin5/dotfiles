#!/bin/bash
# dotfiles installer
# Usage:
#   Local:  ~/dotfiles/install.sh
#   Remote: curl -fsSL https://raw.githubusercontent.com/Gyumin5/dotfiles/master/install.sh | bash
set -euo pipefail

REPO="https://github.com/Gyumin5/dotfiles.git"
DOTFILES_DIR="$HOME/dotfiles"

# Resolve real path of this script (handles symlinks, works on macOS+Linux)
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SOURCE="${BASH_SOURCE[0]}"
  while [ -L "$SOURCE" ]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
fi

# Detect if run from local clone or via curl|bash
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/claude/settings.json" ]; then
  DOTFILES_DIR="$SCRIPT_DIR"
else
  echo "Cloning dotfiles..."
  if [ -d "$DOTFILES_DIR" ]; then
    echo "Updating existing dotfiles..."
    git -C "$DOTFILES_DIR" pull --ff-only
  else
    git clone "$REPO" "$DOTFILES_DIR"
  fi
fi

# Check dependencies
for cmd in jq git; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "WARNING: '$cmd' is not installed. Some features may not work."
  fi
done

mkdir -p ~/.claude/hooks ~/.local/bin

# Claude global config
ln -sf "$DOTFILES_DIR/claude/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$DOTFILES_DIR/claude/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES_DIR/claude/mcp.json" ~/.claude/mcp.json

# Claude hooks
for hook in "$DOTFILES_DIR"/claude/hooks/*.sh; do
  ln -sf "$hook" ~/.claude/hooks/"$(basename "$hook")"
done

# Custom scripts
ln -sf "$DOTFILES_DIR/bin/gemini-ask" ~/.local/bin/gemini-ask
chmod +x ~/.local/bin/gemini-ask

# Install Claude Code
if ! command -v claude &>/dev/null; then
  if command -v npm &>/dev/null; then
    echo "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code 2>/dev/null || echo "WARNING: Claude Code install failed"
  elif command -v node &>/dev/null; then
    echo "Installing Claude Code (via corepack/npx)..."
    npx -y @anthropic-ai/claude-code --version 2>/dev/null || echo "WARNING: Claude Code install failed"
  else
    echo "WARNING: Node.js not found. Install Node.js first, then run: npm install -g @anthropic-ai/claude-code"
  fi
fi

# Install uv (Python package manager for MCP servers)
if ! command -v uv &>/dev/null; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null || echo "WARNING: uv install failed"
  export PATH="$HOME/.local/bin:$PATH"
fi

# Install MCP servers
MCP_DIR="$HOME/.local/share/mcp"
mkdir -p "$MCP_DIR"

for mcp_repo in \
  "takashiishida/arxiv-latex-mcp" \
  "afrise/academic-search-mcp-server:academic-search-mcp"; do
  # Parse repo:dirname format
  REPO_URL="${mcp_repo%%:*}"
  DIR_NAME="${mcp_repo##*:}"
  [ "$DIR_NAME" = "$REPO_URL" ] && DIR_NAME="$(basename "$REPO_URL")"

  if [ ! -d "$MCP_DIR/$DIR_NAME" ]; then
    echo "Installing MCP: $DIR_NAME..."
    git clone "https://github.com/$REPO_URL.git" "$MCP_DIR/$DIR_NAME" 2>/dev/null && \
    (cd "$MCP_DIR/$DIR_NAME" && uv sync 2>/dev/null) || \
    echo "WARNING: $DIR_NAME install failed"
  fi
done

# Install Claude Squad (if not already installed)
if ! command -v cs &>/dev/null; then
  echo "Installing Claude Squad..."
  curl -fsSL https://raw.githubusercontent.com/smtg-ai/claude-squad/main/install.sh | bash 2>/dev/null || echo "WARNING: Claude Squad install failed (needs internet)"
fi

# Auto-install Claude Code plugins (if claude command available)
if command -v claude &>/dev/null; then
  echo "Installing Claude Code plugins..."
  # Add plugin marketplaces
  claude plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode 2>/dev/null || true
  claude plugin marketplace add https://github.com/K-Dense-AI/claude-scientific-writer 2>/dev/null || true
  # Install plugins
  claude plugin install oh-my-claudecode 2>/dev/null || echo "WARNING: oh-my-claudecode install failed"
  claude plugin install claude-scientific-writer 2>/dev/null || echo "WARNING: claude-scientific-writer install failed"
else
  echo ""
  echo "NOTE: Claude Code CLI not found. Install plugins manually after installing Claude Code:"
  echo "  /plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode"
  echo "  /plugin install oh-my-claudecode"
  echo "  /plugin marketplace add https://github.com/K-Dense-AI/claude-scientific-writer"
  echo "  /plugin install claude-scientific-writer"
fi

# Check PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "WARNING: ~/.local/bin is not in your PATH."
  echo "  Add this to your shell rc file: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Dotfiles installed successfully!"
echo "  ~/.claude/CLAUDE.md -> $DOTFILES_DIR/claude/CLAUDE.md"
echo "  ~/.claude/settings.json -> $DOTFILES_DIR/claude/settings.json"
echo "  ~/.claude/mcp.json -> $DOTFILES_DIR/claude/mcp.json"
echo "  ~/.claude/hooks/ -> $DOTFILES_DIR/claude/hooks/"
echo "  ~/.local/bin/gemini-ask -> $DOTFILES_DIR/bin/gemini-ask"
echo ""
echo "Tools: cs (Claude Squad), npx ccusage (usage tracking)"
echo "Plugins: oh-my-claudecode, claude-scientific-writer"
echo ""
if ! claude --version &>/dev/null 2>&1; then
  echo "Next step: Install Node.js, then re-run this script"
else
  echo "Next step: claude login"
fi
