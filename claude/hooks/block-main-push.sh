#!/bin/bash
# Prevent direct push to main/master branch
BRANCH=$(git branch --show-current 2>/dev/null)
COMMAND=$(jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q 'git push' && ([ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]); then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "main/master 브랜치에 직접 push하려고 합니다. 확인이 필요합니다"
    }
  }'
else
  exit 0
fi
