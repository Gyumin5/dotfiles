#!/bin/bash
# Prevent direct push to main/master branch
# Checks both current branch AND target branch in the command
COMMAND=$(jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q 'git push'; then
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
  # Block if: on main/master, OR command explicitly targets main/master
  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ] || \
     echo "$COMMAND" | grep -qE 'git push\s+\S+\s+.*(main|master)(\s|$)'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: "main/master 브랜치에 직접 push하려고 합니다. 확인이 필요합니다"
      }
    }'
    exit 0
  fi
fi

exit 0
