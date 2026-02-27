#!/bin/bash
# Block dangerous bash commands before execution
COMMAND=$(jq -r '.tool_input.command')

if echo "$COMMAND" | grep -qE 'rm -rf /|rm -rf \*|sudo |chmod 777|mkfs\.|dd if=|> /dev/sd|git push --force|git push.*-f |git reset --hard|git clean -fd'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "위험한 명령 감지: 실행 전 확인이 필요합니다"
    }
  }'
else
  exit 0
fi
