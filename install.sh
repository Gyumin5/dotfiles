#!/bin/bash
# dotfiles installer - symlink config files to their expected locations
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p ~/.claude ~/.local/bin

# Claude global config
ln -sf "$DOTFILES_DIR/claude/CLAUDE.md" ~/.claude/CLAUDE.md

# Custom scripts
ln -sf "$DOTFILES_DIR/bin/gemini-ask" ~/.local/bin/gemini-ask
chmod +x ~/.local/bin/gemini-ask

echo "Dotfiles installed successfully!"
echo "  ~/.claude/CLAUDE.md -> $DOTFILES_DIR/claude/CLAUDE.md"
echo "  ~/.local/bin/gemini-ask -> $DOTFILES_DIR/bin/gemini-ask"
