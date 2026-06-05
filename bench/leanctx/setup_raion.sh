#!/usr/bin/env bash
# Build the isolated A/B environment on raion. Idempotent.
# lean-ctx binary must already be scp'd to /tmp/bench/lean-ctx (see deploy step).
set -euo pipefail

BENCH=/tmp/bench
CRED=/home/gmoh/.claude/.credentials.json
LEANCTX_BIN=$BENCH/lean-ctx

mkdir -p "$BENCH/work" "$BENCH/home-native/.claude" "$BENCH/home-leanctx/.claude" "$BENCH/home-leanctx/.lean-ctx"

# --- credentials symlink into both isolated HOMEs (ai-debate iso pattern) ---
for H in home-native home-leanctx; do
  ln -sf "$CRED" "$BENCH/$H/.claude/.credentials.json"
  cat > "$BENCH/$H/.claude/settings.json" <<'JSON'
{ "env": { "ENABLE_PROMPT_CACHING_1H": "1" } }
JSON
done

# --- regime CLAUDE.md: native arm ---
cat > "$BENCH/home-native/.claude/CLAUDE.md" <<'MD'
# Bench regime: NATIVE
Use only the native tools: Read, Grep, Glob, and Bash (cat/grep/find/wc/sed/awk).
Do NOT use any ctx_* tools. Inspect the real files, then answer.
MD

# --- regime CLAUDE.md: lean-ctx arm (replicates the OLD mandatory policy) ---
cat > "$BENCH/home-leanctx/.claude/CLAUDE.md" <<'MD'
# Bench regime: LEAN-CTX (mandatory)
MANDATORY: use the lean-ctx MCP tools for ALL file reads, searches and listings.
Native Read / Grep / Glob / Bash for reading or searching files are FORBIDDEN.
- Read/cat/head/tail  -> ctx_read(path)
- Grep/rg/search      -> ctx_search(pattern, path)
- ls/find/tree        -> ctx_tree(path, depth)
- shell               -> ctx_shell(command)
Inspect the real files via ctx_* tools, then answer.
MD

# --- lean-ctx config for the bench HOME: hardened (cloud off, autonomy off) ---
cat > "$BENCH/home-leanctx/.lean-ctx/config.toml" <<'TOML'
ultra_compact = false
tee_mode = "failures"
checkpoint_interval = 15
excluded_commands = []
passthrough_urls = []
custom_aliases = []
slow_command_threshold_ms = 5000
theme = "default"

[cloud]
contribute_enabled = false

[autonomy]
enabled = false
auto_preload = false
auto_dedup = false
auto_related = false
silent_preload = false
dedup_threshold = 8
TOML

# --- mcp configs ---
echo '{"mcpServers":{}}' > "$BENCH/empty-mcp.json"
cat > "$BENCH/leanctx-mcp.json" <<JSON
{"mcpServers":{"lean-ctx":{"command":"$LEANCTX_BIN","args":[]}}}
JSON

# --- sanity ---
echo "=== setup check ==="
[ -x "$LEANCTX_BIN" ] && echo "lean-ctx bin: $("$LEANCTX_BIN" --version 2>/dev/null || echo MISSING_VERSION)" || echo "WARN: $LEANCTX_BIN not present/executable"
for H in home-native home-leanctx; do
  echo "$H creds: $(readlink "$BENCH/$H/.claude/.credentials.json")"
done
echo "mcp configs: $(ls "$BENCH"/*.json)"
echo "OK"
