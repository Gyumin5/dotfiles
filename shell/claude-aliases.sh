# Claude Code aliases
cl() {
  if [ -d ".claude/telegram" ]; then
    claude -c --remote-control --channels plugin:telegram@claude-plugins-official
  else
    claude -c --remote-control
  fi
}
