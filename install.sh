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

# Claude hooks (clean stale symlinks, then link current hooks)
find ~/.claude/hooks/ -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null
for hook in "$DOTFILES_DIR"/claude/hooks/*.sh; do
  ln -sf "$hook" ~/.claude/hooks/"$(basename "$hook")"
done

# Claude skills
if [ -d "$DOTFILES_DIR/claude/skills" ]; then
  # Remove existing skills dir if not a symlink, then symlink each skill
  for skill_dir in "$DOTFILES_DIR"/claude/skills/*/; do
    skill_name="$(basename "$skill_dir")"
    mkdir -p ~/.claude/skills/"$skill_name"
    for f in "$skill_dir"*; do
      ln -sf "$f" ~/.claude/skills/"$skill_name/$(basename "$f")"
    done
  done
fi

# Custom scripts
ln -sf "$DOTFILES_DIR/bin/gemini-ask" ~/.local/bin/gemini-ask
ln -sf "$DOTFILES_DIR/bin/codex-ask" ~/.local/bin/codex-ask
ln -sf "$DOTFILES_DIR/bin/claude-userbot-login" ~/.local/bin/claude-userbot-login
ln -sf "$DOTFILES_DIR/bin/claude-userbot-send" ~/.local/bin/claude-userbot-send

# Shell aliases (add source line to bashrc if not present)
if ! grep -q 'claude-aliases.sh' ~/.bashrc 2>/dev/null; then
  echo "" >> ~/.bashrc
  echo "# Claude Code aliases" >> ~/.bashrc
  echo "[ -f \"$DOTFILES_DIR/shell/claude-aliases.sh\" ] && source \"$DOTFILES_DIR/shell/claude-aliases.sh\"" >> ~/.bashrc
fi

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

# Install uv (Python package manager for MCP servers) — pinned + sha256 verified
# 2026-05-14: replaced `curl ... | sh` supply-chain pattern with pinned release tarball + SHA256.
# Bump UV_VERSION when needed and refresh from GitHub releases.
if ! command -v uv &>/dev/null; then
  echo "Installing uv (pinned + sha256 verified)..."
  UV_VERSION="0.11.14"
  UV_ASSET="uv-x86_64-unknown-linux-gnu.tar.gz"
  UV_BASE="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}"
  UV_TMP="$(mktemp -d)"
  if curl -fsSL "${UV_BASE}/${UV_ASSET}" -o "${UV_TMP}/${UV_ASSET}" \
     && curl -fsSL "${UV_BASE}/${UV_ASSET}.sha256" -o "${UV_TMP}/${UV_ASSET}.sha256" \
     && ( cd "${UV_TMP}" && sha256sum -c "${UV_ASSET}.sha256" >/dev/null ); then
    tar -xzf "${UV_TMP}/${UV_ASSET}" -C "${UV_TMP}"
    mkdir -p "$HOME/.local/bin"
    install -m755 "${UV_TMP}"/uv-x86_64-unknown-linux-gnu/uv "$HOME/.local/bin/uv"
    install -m755 "${UV_TMP}"/uv-x86_64-unknown-linux-gnu/uvx "$HOME/.local/bin/uvx" 2>/dev/null || true
    echo "uv ${UV_VERSION} installed to ~/.local/bin"
  else
    echo "WARNING: uv ${UV_VERSION} install failed (download or sha256 mismatch)"
  fi
  rm -rf "${UV_TMP}"
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

# Install Claude Squad (if not already installed) — pinned binary tarball
# 2026-05-14: replaced `curl ... | bash` with pinned GitHub release tarball.
# claude-squad releases ship a Go binary; no .sha256 published, so HTTPS to
# GitHub releases is the trust anchor (TLS + GitHub artifact signing).
if ! command -v cs &>/dev/null; then
  echo "Installing Claude Squad (pinned tarball)..."
  CS_VERSION="1.0.17"
  CS_ARCH="$(uname -m)"
  case "$CS_ARCH" in x86_64) CS_GOARCH=amd64 ;; aarch64|arm64) CS_GOARCH=arm64 ;; *) CS_GOARCH=amd64 ;; esac
  CS_ASSET="claude-squad_${CS_VERSION}_linux_${CS_GOARCH}.tar.gz"
  CS_URL="https://github.com/smtg-ai/claude-squad/releases/download/v${CS_VERSION}/${CS_ASSET}"
  CS_TMP="$(mktemp -d)"
  if curl -fsSL "${CS_URL}" -o "${CS_TMP}/${CS_ASSET}"; then
    tar -xzf "${CS_TMP}/${CS_ASSET}" -C "${CS_TMP}"
    mkdir -p "$HOME/.local/bin"
    # Tarball ships binary named "claude-squad"; install as both names for cs alias compatibility
    if [ -f "${CS_TMP}/claude-squad" ]; then
      install -m755 "${CS_TMP}/claude-squad" "$HOME/.local/bin/claude-squad"
      ln -sfn "$HOME/.local/bin/claude-squad" "$HOME/.local/bin/cs"
      echo "claude-squad ${CS_VERSION} installed to ~/.local/bin"
    else
      echo "WARNING: claude-squad binary not found in tarball"
    fi
  else
    echo "WARNING: Claude Squad install failed (download)"
  fi
  rm -rf "${CS_TMP}"
fi

# Auto-install Claude Code plugins (if claude command available)
if command -v claude &>/dev/null; then
  echo "Installing Claude Code plugins..."
  # Add plugin marketplaces
  claude plugin marketplace add https://github.com/K-Dense-AI/claude-scientific-writer 2>/dev/null || true
  # Install plugins
  claude plugin install claude-scientific-writer 2>/dev/null || echo "WARNING: claude-scientific-writer install failed"
else
  echo ""
  echo "NOTE: Claude Code CLI not found. Install plugins manually after installing Claude Code:"
  echo "  /plugin marketplace add https://github.com/K-Dense-AI/claude-scientific-writer"
  echo "  /plugin install claude-scientific-writer"
fi

# Check PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "WARNING: ~/.local/bin is not in your PATH."
  echo "  Add this to your shell rc file: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# systemd user units 복사 (없으면) + daemon-reload.
# 활성화는 사용자가 SETUP.md 따라 수동으로 — 자동 enable 은 의존 토큰/.env 필요.
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
if [ -d "$DOTFILES_DIR/systemd/user" ]; then
  mkdir -p "$SYSTEMD_USER_DIR"
  copied=0
  for f in "$DOTFILES_DIR"/systemd/user/*.service "$DOTFILES_DIR"/systemd/user/*.timer; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if [ ! -f "$SYSTEMD_USER_DIR/$name" ]; then
      cp "$f" "$SYSTEMD_USER_DIR/$name"
      copied=$((copied + 1))
    fi
  done
  if [ "$copied" -gt 0 ]; then
    echo "Copied $copied systemd unit(s) to $SYSTEMD_USER_DIR"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  echo "NOTE: enable units per SETUP.md after creating .claude/telegram/.env and ~/.claude/control-bot/.env"
fi

echo ""
echo "Dotfiles installed successfully!"
echo "  ~/.claude/CLAUDE.md -> $DOTFILES_DIR/claude/CLAUDE.md"
echo "  ~/.claude/settings.json -> $DOTFILES_DIR/claude/settings.json"
echo "  ~/.claude/mcp.json -> $DOTFILES_DIR/claude/mcp.json"
echo "  ~/.claude/hooks/ -> $DOTFILES_DIR/claude/hooks/"
echo "  ~/.claude/skills/ -> $DOTFILES_DIR/claude/skills/"
echo "  ~/.local/bin/gemini-ask -> $DOTFILES_DIR/bin/gemini-ask"
echo "  ~/.local/bin/codex-ask -> $DOTFILES_DIR/bin/codex-ask"
echo ""
echo "Tools: cs (Claude Squad), npx ccusage (usage tracking)"
echo "Plugins: claude-scientific-writer"
echo ""
if ! claude --version &>/dev/null 2>&1; then
  echo "Next step: Install Node.js, then re-run this script"
else
  echo "Next step: claude login"
fi
