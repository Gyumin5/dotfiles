# Claude Code + tmux aliases
# source this file from ~/.bashrc

cl() {
  local name=$(basename "$PWD")
  if tmux has-session -t "$name" 2>/dev/null; then
    tmux attach -t "$name"
  else
    tmux new -s "$name" \; send-keys "claude -c --remote-control" Enter
  fi
}

cls() { tmux ls 2>/dev/null || echo "실행 중인 세션 없음"; }

cla() {
  if [ -z "$1" ]; then cls; echo ""; echo "사용법: cla 세션이름"; else tmux attach -t "$1"; fi
}

clr() {
  for session in $(tmux ls -F '#{session_name}' 2>/dev/null); do
    tmux send-keys -t "$session" "/remote-control" Enter
    sleep 1
    tmux send-keys -t "$session" Up Up Enter
    sleep 2
    tmux send-keys -t "$session" "/remote-control" Enter
  done
  echo "전체 세션 리모트 컨트롤 재연결 완료"
}
