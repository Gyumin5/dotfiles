#!/bin/bash
# Block dangerous bash commands before execution
# Outputs JSON to ask for confirmation when dangerous patterns are detected
COMMAND=$(jq -r '.tool_input.command')

DANGEROUS=false
REASON=""

# rm with recursive/force flags (handles split options: rm -r -f, rm -rf, rm -fr)
if echo "$COMMAND" | grep -qE '\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+|.*-r\s.*-f|.*-f\s.*-r)'; then
  DANGEROUS=true
  REASON="재귀적 삭제 명령 (rm -rf)"
# sudo (including absolute path)
elif echo "$COMMAND" | grep -qE '(^|\s|/)(sudo)\s'; then
  DANGEROUS=true
  REASON="sudo 명령"
# chmod 777 (including -R flag)
elif echo "$COMMAND" | grep -qE '\bchmod\s+(-[a-zA-Z]*\s+)*777'; then
  DANGEROUS=true
  REASON="chmod 777"
# chown (ownership change)
elif echo "$COMMAND" | grep -qE '(^|\s|/)chown\s'; then
  DANGEROUS=true
  REASON="파일 소유권 변경 (chown)"
# disk/device destructive commands
elif echo "$COMMAND" | grep -qE '\b(mkfs|dd\s+if=)'; then
  DANGEROUS=true
  REASON="디스크/디바이스 파괴 명령"
elif echo "$COMMAND" | grep -qE '>\s*/dev/sd'; then
  DANGEROUS=true
  REASON="디바이스 직접 쓰기"
# git destructive operations
elif echo "$COMMAND" | grep -qE 'git\s+push\s+.*(-f|--force)'; then
  DANGEROUS=true
  REASON="git force push"
elif echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  DANGEROUS=true
  REASON="git reset --hard"
elif echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  DANGEROUS=true
  REASON="git clean -f"
# pipe to shell (remote code execution)
elif echo "$COMMAND" | grep -qE '(curl|wget)\s.*\|\s*(bash|sh|zsh)'; then
  DANGEROUS=true
  REASON="원격 스크립트 실행 (curl|bash)"
fi

if [ "$DANGEROUS" = true ]; then
  jq -n --arg reason "위험한 명령 감지 ($REASON): 실행 전 확인이 필요합니다" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
else
  exit 0
fi
