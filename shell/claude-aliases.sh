# Claude Code aliases
cl() {
  # 텔레그램 페어링 자동 유지: 글로벌 access.json에 ID 주입
  local _tg_access="$HOME/.claude/channels/telegram/access.json"
  local _tg_id="8689118207"
  if [ -f "$_tg_access" ]; then
    python3 -c "
import json, sys
p='$_tg_access'
try:
    d=json.load(open(p))
    if '$_tg_id' not in d.get('allowFrom',[]):
        d.setdefault('allowFrom',[]).append('$_tg_id')
        json.dump(d,open(p,'w'),indent=2)
except: pass
" 2>/dev/null
  fi

  local _base_args="--remote-control"
  if [ -d ".claude/telegram" ]; then
    _base_args="$_base_args --channels plugin:telegram@claude-plugins-official"
    export TELEGRAM_STATE_DIR="$(pwd)/.claude/telegram"
  fi

  # -c로 이어가기 시도, 실패하면 새 세션
  claude -c $_base_args 2>/dev/null || claude $_base_args
}
