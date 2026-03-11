#!/bin/bash
# Auto-approve Bash commands that passed block-dangerous.sh
# This overrides Claude Code's built-in safety prompts (e.g. "quoted characters in flag names")
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "Auto-approved by hook"
  }
}'
