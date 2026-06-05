#!/bin/bash
# restore-secrets.sh — backup-secrets.sh 가 만든 암호화 번들을 복원.
#
# 포맷/재설치 복구 흐름: dotfiles clone → install.sh → (이 스크립트로) 비밀 복원
#   → claude login (.credentials.json 은 백업 대상 아님) → 세션 enable.
#
# 번들은 $HOME 상대경로로 저장돼 있어 원래 절대경로로 복원된다(부모 디렉터리 자동 생성).
# 권한: 디렉터리 700, 파일 600.
#
# 사용법:
#   restore-secrets.sh BUNDLE.tar.gz.gpg [--passfile PATH] [--dry-run] [--force]
#                      [--include-userbot-session]
#   --dry-run                 복원할 파일 목록만 출력
#   --force                   기존 파일을 백업 없이 덮어씀 (기본은 .pre-restore 백업)
#   --include-userbot-session raion 등에서 userbot.session 도 강제 복원(기본 제외)
set -uo pipefail

HOME_DIR="${HOME}"
MACHINE_FILE="$HOME_DIR/.config/claude-machine-id"
PASSFILE="$HOME_DIR/.config/claude-secrets/passphrase"
DRYRUN=false
FORCE=false
INCLUDE_UBS=false
BUNDLE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --passfile) PASSFILE="$2"; shift 2 ;;
        --dry-run) DRYRUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --include-userbot-session) INCLUDE_UBS=true; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        -*) echo "unknown arg: $1" >&2; exit 2 ;;
        *) BUNDLE="$1"; shift ;;
    esac
done

[ -n "$BUNDLE" ] && [ -f "$BUNDLE" ] || { echo "번들 경로 필요(존재해야 함): $BUNDLE" >&2; exit 2; }
command -v gpg >/dev/null || { echo "gpg 없음." >&2; exit 1; }
[ -s "$PASSFILE" ] || { echo "패스프레이즈 파일 없음: $PASSFILE (--passfile 로 지정, 비번관리자에서 복원)" >&2; exit 1; }

MACHINE="$(cat "$MACHINE_FILE" 2>/dev/null || echo unknown)"

TARPLAIN="$(mktemp "${TMPDIR:-/tmp}/cs-r-XXXXXX.tar.gz")"
cleanup() { rm -f "$TARPLAIN"; }
trap cleanup EXIT

gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
    --decrypt -o "$TARPLAIN" "$BUNDLE" 2>/dev/null \
    || { echo "복호화 실패(패스프레이즈 불일치?)." >&2; exit 1; }

mapfile -t entries < <(tar -tzf "$TARPLAIN")

# userbot.session: 회사 머신(raion)에서만 기본 제외 (개인 텔레그램 세션 보관 위험).
# home 등에서는 기본 복원. --include-userbot-session 이면 어디서나 복원.
skip_ubs() {
    case "$1" in
        *".claude/userbot/userbot.session")
            [ "$INCLUDE_UBS" = true ] && return 1
            [ "$MACHINE" = "raion" ] && return 0
            return 1 ;;
    esac
    return 1
}

echo "복원 대상 (머신=$MACHINE, dry-run=$DRYRUN, force=$FORCE):"
to_restore=()
for e in "${entries[@]}"; do
    [ -z "$e" ] && continue
    case "$e" in */) continue ;; esac
    if skip_ubs "$e"; then
        echo "  SKIP  $e  (userbot.session 기본 제외; --include-userbot-session 로 강제)"
        continue
    fi
    echo "  REST  $e"
    to_restore+=("$e")
done

if [ "$DRYRUN" = true ]; then
    echo "(dry-run: 변경 없음)"
    exit 0
fi
[ ${#to_restore[@]} -eq 0 ] && { echo "복원할 항목 없음."; exit 0; }

TS="$(date '+%Y%m%d-%H%M%S')"
restored=0
for e in "${to_restore[@]}"; do
    target="$HOME_DIR/$e"
    parent="$(dirname "$target")"
    mkdir -p "$parent"
    if [ -f "$target" ] && [ "$FORCE" != true ]; then
        cp -p "$target" "${target}.pre-restore.${TS}"
    fi
    tar -C "$HOME_DIR" -xzf "$TARPLAIN" "$e"
    chmod 600 "$target" 2>/dev/null || true
    restored=$((restored+1))
done

# 권한 정리: 비밀 디렉터리 700
for d in "$HOME_DIR/.claude/userbot" "$HOME_DIR/.claude/control-bot"; do
    [ -d "$d" ] && chmod 700 "$d"
done
# 세션별 telegram 디렉터리 700
while IFS= read -r f; do
    d="$(dirname "$HOME_DIR/$f")"
    [ -d "$d" ] && chmod 700 "$d"
done < <(printf '%s\n' "${to_restore[@]}" | grep '\.claude/telegram/\.env$')

echo "복원 완료: ${restored}개 파일."
echo "다음: claude login (자격증명 백업 대상 아님) → systemctl --user daemon-reload → 세션 enable."
