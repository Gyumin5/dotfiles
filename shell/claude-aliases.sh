# Claude Code aliases
# cl: 터미널에서 Claude Code 세션 붙기. systemd 서비스가 있으면 자동으로 멈추고
#     종료 시 다시 살림. 없으면 그냥 일반 cl 동작.
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

  local _pwd="$PWD"
  # systemd 서비스가 관리 중이면: failed 자동 복구 + stop → exit 시 auto-start
  # systemd unit 이름 규약상 언더스코어를 대시로 정규화
  local _svc="claude-$(basename "$PWD" | tr '_' '-')"
  if systemctl --user list-unit-files "$_svc.service" 2>/dev/null | grep -q "$_svc"; then
    # failed 상태면 카운터 리셋 (반복 실패로 멈춰있을 수 있음)
    if systemctl --user is-failed --quiet "$_svc" 2>/dev/null; then
      echo "[cl] $_svc failed 상태 감지 → reset-failed"
      systemctl --user reset-failed "$_svc"
    fi
    if systemctl --user is-active --quiet "$_svc" 2>/dev/null; then
      echo "[cl] systemd $_svc stop"
      if ! systemctl --user stop "$_svc"; then
        echo "[cl] stop 실패 → SIGKILL"
        systemctl --user kill -s KILL "$_svc" 2>/dev/null
      fi
    fi
    # trap: 셸 종료 시 같은 경로에 다른 claude 없으면 service 재기동.
    # 다른 cl 세션이 이미 이 프로젝트를 잡고 있으면 service 재기동을 생략해서
    # 충돌/중복 세션 방지.
    trap '
      _pwd_exit='"'$_pwd'"'
      _svc_exit='"'$_svc'"'
      for _pp in $(pgrep -f "^claude.*--remote-control" 2>/dev/null); do
        _cwd_exit=$(readlink /proc/$_pp/cwd 2>/dev/null)
        if [ "$_cwd_exit" = "$_pwd_exit" ]; then
          echo "[cl] 다른 cl 세션($_pp) 살아있음 → service 재기동 생략"
          exit 0
        fi
      done
      echo "[cl] systemd $_svc_exit restart"
      systemctl --user reset-failed "$_svc_exit" 2>/dev/null
      systemctl --user start "$_svc_exit"
    ' EXIT INT
  fi

  # 같은 경로에서 돌아가는 다른 터미널 cl 세션이 있으면 강제 종료 (봇 토큰 경쟁 방지)
  local _p _cwd
  for _p in $(pgrep -f "^claude.*--remote-control" 2>/dev/null); do
    _cwd=$(readlink "/proc/$_p/cwd" 2>/dev/null)
    if [ "$_cwd" = "$_pwd" ]; then
      echo "[cl] 기존 claude 세션 $_p 종료 (같은 경로)"
      kill -TERM "$_p" 2>/dev/null
    fi
  done
  # TERM이 먹었는지 2초 대기 후 살아있으면 KILL
  sleep 2
  for _p in $(pgrep -f "^claude.*--remote-control" 2>/dev/null); do
    _cwd=$(readlink "/proc/$_p/cwd" 2>/dev/null)
    if [ "$_cwd" = "$_pwd" ]; then
      echo "[cl] $_p SIGKILL"
      kill -KILL "$_p" 2>/dev/null
    fi
  done

  # -c로 이어가기 시도
  claude -c $_base_args 2>/dev/null
  local _ec=$?
  # exit 1 (이전 세션 없음)일 때만 새 세션으로 fallback.
  # 시그널로 죽은 경우(128+)는 그대로 종료해야 다른 cl에게 뺏긴 뒤 여기서 또 살아나는 사고 방지.
  if [ "$_ec" -eq 1 ]; then
    claude $_base_args
  fi
}
