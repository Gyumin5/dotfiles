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

# systemd user units 배포 (git=source of truth, 항상 덮어씀) + 머신별 세션 enable.
#
# 머신 식별 (robust 순서):
#   1) ~/.config/claude-machine-id  (명시적 마커 = 진실원천, rename/clone 에도 불변)
#   2) tailscale 노드명               (마커 없을 때 기본값 제안 — 부트스트랩용)
# 식별 못하면 unit 복사만 하고 enable 은 건너뜀 (안전).
#
# 세션 enable 은 machines/<machine>.list 에 적힌 것만. 추가 가드: 그 세션 토큰
# (.claude/telegram/.env)이 이 머신에 실제 있을 때만 enable → 잘못된 머신에서
# 같은 봇 2중 inbound 사고 방지. (unit 자체에도 ConditionPathExists 로 2중 방어.)
# 머신 식별 (unit 복사 전에 필요 — raion 전용 todobot 유닛 필터)
MACHINE_ID=""
MARKER="$HOME/.config/claude-machine-id"
if [ -f "$MARKER" ]; then
  MACHINE_ID=$(tr -d '[:space:]' < "$MARKER")
elif command -v tailscale >/dev/null 2>&1; then
  TS_NAME=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["Self"]["HostName"])
except: pass' 2>/dev/null)
  if [ -n "$TS_NAME" ] && [ -f "$DOTFILES_DIR/machines/${TS_NAME}.list" ]; then
    MACHINE_ID="$TS_NAME"
    echo "machine-id 마커 없음 → tailscale 노드명 '$TS_NAME' 사용. 고정하려면: echo $TS_NAME > $MARKER"
  fi
fi

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
if [ -d "$DOTFILES_DIR/systemd/user" ]; then
  mkdir -p "$SYSTEMD_USER_DIR"
  for f in "$DOTFILES_DIR"/systemd/user/*.service "$DOTFILES_DIR"/systemd/user/*.timer; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    # raion 전용 유닛(todobot, self-auth-watch)은 raion 에만 배포 (다른 머신엔 유닛 자체를 안 심음).
    case "$base" in todobot-*|raion-auth-watch.*) [ "$MACHINE_ID" = "raion" ] || continue;; esac
    cp -f "$f" "$SYSTEMD_USER_DIR/$base"
  done
  systemctl --user daemon-reload 2>/dev/null || true
  echo "Synced systemd units to $SYSTEMD_USER_DIR"

  MANIFEST="$DOTFILES_DIR/machines/${MACHINE_ID}.list"
  if [ -n "$MACHINE_ID" ] && [ -f "$MANIFEST" ]; then
    echo "Machine='$MACHINE_ID' — enabling sessions from machines/${MACHINE_ID}.list"
    while read -r s; do
      case "$s" in ''|\#*) continue;; esac
      unit="claude-${s}.service"
      [ -f "$SYSTEMD_USER_DIR/$unit" ] || { echo "  skip $s (no unit)"; continue; }
      wd=$(sed -n 's/^WorkingDirectory=//p' "$SYSTEMD_USER_DIR/$unit" | head -1)
      if [ -n "$wd" ] && [ -f "$wd/.claude/telegram/.env" ]; then
        systemctl --user enable --now "$unit" 2>/dev/null \
          && echo "  enabled $unit" || echo "  WARN enable failed: $unit"
      else
        echo "  skip $s (token .env 없음: ${wd}/.claude/telegram/.env) — 이 머신 세션 아님"
      fi
    done < "$MANIFEST"
    loginctl enable-linger "$USER" 2>/dev/null || true
  else
    echo "NOTE: machine-id 미식별. 'echo home > $MARKER' (또는 raion) 후 재실행하면 그 머신 세션 자동 enable."
    echo "      또는 SETUP.md 따라 수동 enable. 토큰 .env / control-bot/.env 선행 필요."
  fi
fi

# raion 전용 todo 자동화 자산 설치 (MACHINE_ID=raion 일 때만).
# 범위: 파일자산 + 의존성 + DB init 만. SessionStart 훅/settings/persistence/cron 은 제외
# (cron 무장은 raion 의 살아있는 텔레그램 세션이 별도로 함). raion-todo-arm.sh 도 범위 외.
# 코드(.py/프롬프트/RUNBOOK)=repo 가 source of truth → 항상 덮어씀(cp -f).
# 데이터·비밀(todo.db, bot.token, config.json, last_check.txt …)=raion 로컬 → 절대 안 덮어씀.
if [ "$MACHINE_ID" = "raion" ] && [ -d "$DOTFILES_DIR/raion/todo-sync" ]; then
  TODO_DIR="$HOME/raion/todo-sync"
  mkdir -p "$TODO_DIR/prompts"
  cp -f "$DOTFILES_DIR/raion/todo-sync/todoctl.py"  "$TODO_DIR/"
  cp -f "$DOTFILES_DIR/raion/todo-sync/auth.py"     "$TODO_DIR/"
  # config.json 은 raion 로컬(식별자 포함, repo 엔 .example 만). 없을 때만 템플릿 생성.
  if [ ! -f "$TODO_DIR/config.json" ]; then
    cp "$DOTFILES_DIR/raion/todo-sync/config.json.example" "$TODO_DIR/config.json"
    echo "[install]   config.json 템플릿 생성 — client_id/tenant_id 채워야 메일·Graph 수집 동작"
  fi
  cp    "$DOTFILES_DIR/raion/todo-sync/RUNBOOK.md"  "$TODO_DIR/" 2>/dev/null || true
  cp    "$DOTFILES_DIR"/raion/todo-sync/prompts/*.txt "$TODO_DIR/prompts/" 2>/dev/null || true
  # TODOBot 코드(전용 텔레그램 봇: 마감 리마인더 + 완료/스누즈/일정조정 리스너).
  # 코드는 source-of-truth=repo 이므로 덮어씀. 비밀/상태(bot.token,bot.chat_id,snooze.json)는
  # 운영경로에만 있고 git 제외(repo 의 bot/ 엔 .py 만 존재).
  mkdir -p "$TODO_DIR/bot"
  cp "$DOTFILES_DIR"/raion/todo-sync/bot/*.py "$TODO_DIR/bot/" 2>/dev/null || true
  # 웹UI(Tailscale 전용 폰 접속). 코드만 배포 — .token(secret)·로그는 런타임 생성(git 제외).
  mkdir -p "$TODO_DIR/webui"
  cp "$DOTFILES_DIR/raion/todo-sync/webui/server.py" "$TODO_DIR/webui/" 2>/dev/null || true
  python3 -m pip install --user --quiet msal requests segno 2>/dev/null || true
  [ -f "$TODO_DIR/todo.db" ] || python3 "$TODO_DIR/todoctl.py" init 2>/dev/null || true
  [ -f "$TODO_DIR/last_check.txt" ] || date -u +%FT%TZ > "$TODO_DIR/last_check.txt"
  chmod 700 "$TODO_DIR"
  echo "[install] raion todo 자산 설치 완료. cron 등록은 텔레그램 세션에서 'todo 스케줄 켜줘'."

  # TODOBot 서비스/타이머 enable (유닛은 위 systemd 블록에서 이미 배포됨).
  # 봇 토큰/chat_id 가 있을 때만 — 없으면 기동 실패하므로 생략.
  if [ -f "$TODO_DIR/bot.token" ] && [ -f "$TODO_DIR/bot.chat_id" ]; then
    systemctl --user enable --now todobot-listener.service 2>/dev/null \
      && echo "[install]   enabled todobot-listener.service" \
      || echo "[install]   WARN: todobot-listener enable 실패"
    systemctl --user enable --now todobot-digest.timer 2>/dev/null \
      && echo "[install]   enabled todobot-digest.timer" \
      || echo "[install]   WARN: todobot-digest.timer enable 실패"
  else
    echo "[install]   TODOBot 토큰 없음 → 리스너/타이머 enable 생략. BotFather 토큰 저장 후 재실행."
  fi

  # self-auth-watch: claude.ai 로그인 만료를 raion 스스로 감지 → todobot 으로 알림.
  # 알림 경로가 봇 토큰 curl 이라 claude 인증이 죽어도 동작. 유닛은 위 systemd 블록에서 배포됨.
  ln -sf "$DOTFILES_DIR/bin/raion-claude-auth-watch" ~/.local/bin/raion-claude-auth-watch
  chmod +x "$DOTFILES_DIR/bin/raion-claude-auth-watch"
  systemctl --user enable --now raion-auth-watch.timer 2>/dev/null \
    && echo "[install]   enabled raion-auth-watch.timer" \
    || echo "[install]   WARN: raion-auth-watch.timer enable 실패"
fi

# 비밀 복원 (봇토큰/유저봇/컨트롤봇).
# 권장(키워드 모드): CLAUDE_SECRETS_KEYWORD=1 → PRIVATE repo claude-secrets 에서
#   최신 번들 자동선택 + 키워드 터미널 입력으로 복원(restore 가 repo 자동 clone).
# legacy(번들 경로): CLAUDE_SECRETS_BUNDLE 에 번들 경로. 패스프레이즈는
#   CLAUDE_SECRETS_PASSFILE 또는 비번관리자에서.
# 없으면 생략(실패 안 함).
if [ -n "${CLAUDE_SECRETS_KEYWORD:-}" ] && [ -x "$DOTFILES_DIR/bin/restore-secrets.sh" ]; then
  echo "[install] 비밀 복원(키워드 모드, private repo claude-secrets 최신 번들):"
  "$DOTFILES_DIR/bin/restore-secrets.sh" --keyword --auto-latest \
    || echo "[install] 비밀 복원 실패 — restore-secrets.sh --keyword --auto-latest 수동 실행 필요"
elif [ -n "${CLAUDE_SECRETS_BUNDLE:-}" ] && [ -f "${CLAUDE_SECRETS_BUNDLE}" ]; then
  if [ -x "$DOTFILES_DIR/bin/restore-secrets.sh" ]; then
    echo "[install] 비밀 번들 복원: $CLAUDE_SECRETS_BUNDLE"
    "$DOTFILES_DIR/bin/restore-secrets.sh" "$CLAUDE_SECRETS_BUNDLE" \
      ${CLAUDE_SECRETS_PASSFILE:+--passfile "$CLAUDE_SECRETS_PASSFILE"} \
      || echo "[install] 비밀 복원 실패 — restore-secrets.sh 수동 실행 필요"
  fi
else
  echo "[install] 비밀 미복원 — 세션 봇/유저봇 토큰 없음."
  echo "          복구(권장): CLAUDE_SECRETS_KEYWORD=1 ~/dotfiles/install.sh  (키워드 입력)"
  echo "          또는: bin/restore-secrets.sh --keyword --auto-latest → claude login."
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
