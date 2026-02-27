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

# Install Claude Squad (if not already installed)
if ! command -v cs &>/dev/null; then
  echo "Installing Claude Squad..."
  curl -fsSL https://raw.githubusercontent.com/smtg-ai/claude-squad/main/install.sh | bash 2>/dev/null || echo "WARNING: Claude Squad install failed (needs internet)"
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
echo ""
echo "Optional: install oh-my-claudecode plugin inside Claude Code:"
echo "  /plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode"
echo "  /plugin install oh-my-claudecode"
