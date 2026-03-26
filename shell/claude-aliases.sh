# Claude Code + tmux aliases
# source this file from ~/.bashrc

# 프로젝트 목록 (clx에서 사용)
CLAUDE_PROJECTS=(
  ~/av-ros
  ~/test_claude
)

# 현재 디렉토리 기반 세션 생성/접속
cl() {
  local name=$(basename "$PWD")
  if tmux has-session -t "$name" 2>/dev/null; then
    tmux attach -t "$name"
  else
    tmux new-session -d -s "$name"
    tmux send-keys -t "$name" "cd $PWD && claude -c --remote-control --channels plugin:telegram@claude-plugins-official" Enter
    tmux attach -t "$name"
  fi
}

# 세션 목록
cls() { tmux ls 2>/dev/null || echo "실행 중인 세션 없음"; }

# 이름으로 붙기
cla() {
  if [ -z "$1" ]; then cls; echo ""; echo "사용법: cla 세션이름"; else tmux attach -t "$1"; fi
}

# 전체 세션 재시작 (폰 SSH용)
clx() {
  # 기존 세션 전부 종료
  for session in $(tmux ls -F '#{session_name}' 2>/dev/null); do
    tmux kill-session -t "$session"
    echo "[$session] 종료"
  done
  sleep 1
  # 프로젝트 목록에서 새로 시작
  for dir in "${CLAUDE_PROJECTS[@]}"; do
    dir="${dir/#\~/$HOME}"
    [ ! -d "$dir" ] && continue
    local name=$(basename "$dir")
    tmux new-session -d -s "$name"
    tmux send-keys -t "$name" "cd $dir && claude -c --remote-control --channels plugin:telegram@claude-plugins-official" Enter
    echo "[$name] 시작"
  done
  echo "전체 세션 재시작 완료"
}
