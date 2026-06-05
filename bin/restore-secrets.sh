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
#   restore-secrets.sh [BUNDLE.tar.gz.gpg] [--keyword] [--auto-latest]
#                      [--passfile PATH] [--dry-run] [--force]
#                      [--include-userbot-session] [--secrets-repo DIR]
#   --keyword                 키워드→scrypt 파생 패스프레이즈 사용(터미널 입력).
#                             salt 는 claude-secrets private repo 에서 읽음.
#   --auto-latest             BUNDLE 생략 시 private repo 에서 이 머신 최신 번들 자동선택
#   --dry-run                 복원할 파일 목록만 출력
#   --force                   기존 파일을 백업 없이 덮어씀 (기본은 .pre-restore 백업)
#   --include-userbot-session raion 등에서 userbot.session 도 강제 복원(기본 제외)
#   --secrets-repo DIR        private repo 로컬 클론 경로(기본 ~/claude-secrets-repo)
set -uo pipefail

HOME_DIR="${HOME}"
BINDIR="$(cd "$(dirname "$0")" && pwd)"
MACHINE_FILE="$HOME_DIR/.config/claude-machine-id"
PASS_DIR="$HOME_DIR/.config/claude-secrets"
PASSFILE="$PASS_DIR/passphrase"
SECRETS_REPO="$HOME_DIR/claude-secrets-repo"
SECRETS_URL_FILE="$PASS_DIR/repo-url"
DEFAULT_SECRETS_URL="git@github.com:Gyumin5/claude-secrets.git"
DRYRUN=false
FORCE=false
INCLUDE_UBS=false
KEYWORD_MODE=false
AUTO_LATEST=false
BUNDLE=""
TMPPASS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --passfile) PASSFILE="$2"; shift 2 ;;
        --keyword) KEYWORD_MODE=true; shift ;;
        --auto-latest) AUTO_LATEST=true; shift ;;
        --secrets-repo) SECRETS_REPO="$2"; shift 2 ;;
        --dry-run) DRYRUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --include-userbot-session) INCLUDE_UBS=true; shift ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        -*) echo "unknown arg: $1" >&2; exit 2 ;;
        *) BUNDLE="$1"; shift ;;
    esac
done

command -v gpg >/dev/null || { echo "gpg 없음." >&2; exit 1; }
MACHINE="$(cat "$MACHINE_FILE" 2>/dev/null || echo unknown)"

TARPLAIN="$(mktemp "${TMPDIR:-/tmp}/cs-r-XXXXXX.tar.gz")"
cleanup() { rm -f "$TARPLAIN" "${TMPPASS:-}"; }
trap cleanup EXIT

# private repo 보장 (clone 없으면 clone)
ensure_secrets_repo() {
    local url="$DEFAULT_SECRETS_URL"
    [ -s "$SECRETS_URL_FILE" ] && url="$(cat "$SECRETS_URL_FILE")"
    if [ ! -d "$SECRETS_REPO/.git" ]; then
        echo "claude-secrets repo clone: $url → $SECRETS_REPO"
        git clone "$url" "$SECRETS_REPO" || { echo "clone 실패." >&2; return 1; }
    else
        git -C "$SECRETS_REPO" pull --ff-only 2>&1 | tail -1 || true
    fi
}

# --auto-latest: repo 에서 이 머신 최신 번들 선택
if [ "$AUTO_LATEST" = true ] && [ -z "$BUNDLE" ]; then
    ensure_secrets_repo || exit 1
    BUNDLE="$(ls -t "$SECRETS_REPO"/bundles/claude-secrets-"${MACHINE}"-*.tar.gz.gpg 2>/dev/null | head -1)"
    [ -n "$BUNDLE" ] || { echo "repo 에 ${MACHINE} 번들 없음." >&2; exit 1; }
    echo "자동선택 번들: $BUNDLE"
fi

[ -n "$BUNDLE" ] && [ -f "$BUNDLE" ] || { echo "번들 경로 필요(존재해야 함): '$BUNDLE'  (--auto-latest 로 자동선택 가능)" >&2; exit 2; }

# 패스프레이즈 준비: --keyword 면 salt 로 파생, 아니면 파일
if [ "$KEYWORD_MODE" = true ]; then
    ensure_secrets_repo || exit 1
    SALT="$SECRETS_REPO/salt"
    [ -s "$SALT" ] || { echo "salt 없음: $SALT" >&2; exit 1; }
    TMPPASS="$(mktemp "${TMPDIR:-/tmp}/cs-rpass-XXXXXX")"; chmod 600 "$TMPPASS"
    echo "키워드 입력으로 패스프레이즈 파생(터미널):"
    "$BINDIR/secrets-keyderive" --salt "$SALT" --out "$TMPPASS" \
        || { echo "키워드 파생 실패." >&2; exit 1; }
    PASSFILE="$TMPPASS"
fi
[ -s "$PASSFILE" ] || { echo "패스프레이즈 없음: $PASSFILE (--passfile 또는 --keyword)" >&2; exit 1; }

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
