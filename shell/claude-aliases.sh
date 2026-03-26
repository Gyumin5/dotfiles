# Claude Code aliases
cl() {
  if [ -d ".claude/telegram" ]; then
    TELEGRAM_STATE_DIR="$(pwd)/.claude/telegram" claude -c --remote-control --channels plugin:telegram@claude-plugins-official
  else
    claude -c --remote-control
  fi
}
