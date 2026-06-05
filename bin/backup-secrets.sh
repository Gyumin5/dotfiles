#!/bin/bash
# backup-secrets.sh — 머신 로컬 비밀을 단일 암호화 번들로 백업.
#
# 두 가지 패스프레이즈 모드:
#   (기본·legacy) ~/.config/claude-secrets/passphrase (랜덤 32B 자동생성).
#   (--keyword)   사용자 키워드 → scrypt(salt) 파생 패스프레이즈. 키워드는 터미널
#                 에서만 입력(저장 안 함). salt 는 claude-secrets PRIVATE repo 에 보관.
#
# --keyword 모드는 번들을 claude-secrets PRIVATE repo(~/claude-secrets-repo)에
# commit+push 까지 한다(별도 보관 자동화). PUBLIC dotfiles 엔 비밀이 안 들어간다.
#
# 암호화: gpg --symmetric --cipher-algo AES256 (키링 없음, 패스프레이즈만).
#
# 백업 대상 (manifest):
#   - ~/.claude/userbot/.env            (Telegram API_ID/HASH)
#   - ~/.claude/userbot/userbot.session (MTProto 세션; raion 머신은 기본 제외)
#   - ~/.claude/control-bot/.env        (컨트롤봇 토큰)
#   - machines/<machine>.list 의 각 세션 <WorkingDirectory>/.claude/telegram/.env
# 제외(재취득 가능): ~/.claude/.credentials.json, ~/.claude.json, targets.json.
#
# 사용법: backup-secrets.sh [--keyword] [--no-push] [-o OUTDIR] [--secrets-repo DIR]
#   --keyword       키워드 파생 패스프레이즈 사용 + 번들을 private repo 로 push
#   --no-push       --keyword 라도 push 안 함(로컬 repo 에만 commit)
#   -o OUTDIR       로컬 번들 출력 디렉터리(기본 ~/claude-secrets-backup)
#   --secrets-repo  private repo 로컬 클론 경로(기본 ~/claude-secrets-repo)
set -uo pipefail

HOME_DIR="${HOME}"
DOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
BINDIR="$(cd "$(dirname "$0")" && pwd)"
MACHINE_FILE="$HOME_DIR/.config/claude-machine-id"
PASS_DIR="$HOME_DIR/.config/claude-secrets"
PASSFILE="$PASS_DIR/passphrase"
OUTDIR="$HOME_DIR/claude-secrets-backup"
SECRETS_REPO="$HOME_DIR/claude-secrets-repo"
SECRETS_URL_FILE="$PASS_DIR/repo-url"
DEFAULT_SECRETS_URL="git@github.com:Gyumin5/claude-secrets.git"
KEYWORD_MODE=false
PUSH=true

while [ $# -gt 0 ]; do
    case "$1" in
        --keyword) KEYWORD_MODE=true; shift ;;
        --no-push) PUSH=false; shift ;;
        -o) OUTDIR="$2"; shift 2 ;;
        --secrets-repo) SECRETS_REPO="$2"; shift 2 ;;
        -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

command -v gpg >/dev/null || { echo "gpg 없음. gpg 설치 필요." >&2; exit 1; }

MACHINE="$(cat "$MACHINE_FILE" 2>/dev/null || echo unknown)"
mkdir -p "$PASS_DIR"; chmod 700 "$PASS_DIR"

TMPPASS=""
cleanup() { rm -f "${TARPLAIN:-}" "${TMPPASS:-}"; }
trap cleanup EXIT

# private repo 보장(clone 없으면 clone, 있으면 ff-only pull)
ensure_secrets_repo() {
    local url="$DEFAULT_SECRETS_URL"
    [ -s "$SECRETS_URL_FILE" ] && url="$(cat "$SECRETS_URL_FILE")"
    if [ ! -d "$SECRETS_REPO/.git" ]; then
        echo "claude-secrets repo clone: $url → $SECRETS_REPO"
        git clone "$url" "$SECRETS_REPO" || { echo "clone 실패." >&2; return 1; }
    else
        git -C "$SECRETS_REPO" pull --ff-only 2>&1 | tail -1 || true
    fi
    mkdir -p "$SECRETS_REPO/bundles"
}

if [ "$KEYWORD_MODE" = true ]; then
    ensure_secrets_repo || exit 1
    SALT="$SECRETS_REPO/salt"
    [ -s "$SALT" ] || { echo "salt 없음: $SALT (repo 손상?)" >&2; exit 1; }
    TMPPASS="$(mktemp "${TMPDIR:-/tmp}/cs-pass-XXXXXX")"; chmod 600 "$TMPPASS"
    echo "키워드 파생 패스프레이즈 생성(터미널에 직접 입력):"
    "$BINDIR/secrets-keyderive" --salt "$SALT" --out "$TMPPASS" --confirm \
        || { echo "키워드 파생 실패." >&2; exit 1; }
    PASSFILE="$TMPPASS"
else
    # legacy: 랜덤 패스프레이즈 파일
    if [ ! -s "$PASSFILE" ]; then
        head -c 32 /dev/urandom | base64 | tr -d '\n' > "$PASSFILE"
        chmod 600 "$PASSFILE"
        echo "!! 새 패스프레이즈 생성: $PASSFILE"
        echo "!! 반드시 비밀번호관리자에 복사해 둬라(없으면 복호화 불가):"
        echo "!!   cat $PASSFILE"
    fi
fi

# 백업 대상 절대경로 수집 (존재하는 것만)
abs_list=()
add() { [ -f "$1" ] && abs_list+=("$1"); }

add "$HOME_DIR/.claude/userbot/.env"
add "$HOME_DIR/.claude/control-bot/.env"
# userbot.session: 회사 머신(raion)엔 개인 텔레그램 세션 보관 위험 → 기본 제외
if [ "$MACHINE" != "raion" ]; then
    add "$HOME_DIR/.claude/userbot/userbot.session"
fi

# 세션별 봇 토큰: machines/<machine>.list 기준
LIST="$DOTDIR/machines/${MACHINE}.list"
sessions=()
if [ -f "$LIST" ]; then
    while IFS= read -r s; do
        case "$s" in ''|\#*) continue ;; esac
        wd="$(systemctl --user show -p WorkingDirectory --value "claude-${s}.service" 2>/dev/null)"
        [ -n "$wd" ] && add "$wd/.claude/telegram/.env" && sessions+=("$s")
    done < "$LIST"
fi

if [ ${#abs_list[@]} -eq 0 ]; then
    echo "백업할 비밀 파일 없음(머신=$MACHINE). 중단." >&2
    exit 1
fi

# HOME 상대경로로 변환 (전부 $HOME 하위)
rel_list=()
for f in "${abs_list[@]}"; do
    case "$f" in
        "$HOME_DIR"/*) rel_list+=("${f#"$HOME_DIR"/}") ;;
        *) echo "경고: HOME 밖 경로 건너뜀: $f" >&2 ;;
    esac
done

mkdir -p "$OUTDIR"; chmod 700 "$OUTDIR"
TS="$(date '+%Y%m%d-%H%M%S')"
BASE="claude-secrets-${MACHINE}-${TS}"
TARPLAIN="$(mktemp "${TMPDIR:-/tmp}/cs-XXXXXX.tar.gz")"
BUNDLE="$OUTDIR/${BASE}.tar.gz.gpg"
META="$OUTDIR/${BASE}.meta"

tar -C "$HOME_DIR" -czf "$TARPLAIN" "${rel_list[@]}"
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
    --symmetric --cipher-algo AES256 -o "$BUNDLE" "$TARPLAIN"
chmod 600 "$BUNDLE"

# 메타 (파일명/해시만, 내용 평문 없음)
{
    echo "created: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "machine: $MACHINE"
    echo "hostname: $(hostname)"
    echo "passphrase_mode: $([ "$KEYWORD_MODE" = true ] && echo keyword-scrypt || echo random-file)"
    echo "files: ${#rel_list[@]}"
    echo "sha256: $(sha256sum "$BUNDLE" | awk '{print $1}')"
    echo "manifest:"
    for r in "${rel_list[@]}"; do echo "  - $r"; done
} > "$META"
chmod 600 "$META"

# 신선도: 직전 번들 manifest 와 비교해 변경 알림
PREV_META="$(ls -t "$OUTDIR"/claude-secrets-"${MACHINE}"-*.meta 2>/dev/null | sed -n 2p)"
if [ -n "$PREV_META" ]; then
    if ! diff -q <(grep '^  - ' "$PREV_META") <(grep '^  - ' "$META") >/dev/null 2>&1; then
        echo "ⓘ 직전 백업 대비 비밀 파일 목록이 바뀌었다(세션 추가/삭제 등)."
    fi
fi

echo "백업 완료:"
echo "  번들: $BUNDLE"
echo "  메타: $META"
echo "  파일 ${#rel_list[@]}개 (세션 ${#sessions[@]}개 + 글로벌)"

# --keyword: private repo 로 commit+push
if [ "$KEYWORD_MODE" = true ]; then
    cp -p "$BUNDLE" "$SECRETS_REPO/bundles/"
    cp -p "$META"   "$SECRETS_REPO/bundles/"
    git -C "$SECRETS_REPO" add bundles/ >/dev/null 2>&1
    if git -C "$SECRETS_REPO" diff --cached --quiet 2>/dev/null; then
        echo "→ private repo 변경 없음(동일 내용)."
    else
        git -C "$SECRETS_REPO" -c user.name="${GIT_AUTHOR_NAME:-gmoh}" \
            -c user.email="${GIT_AUTHOR_EMAIL:-ogm3614@gmail.com}" \
            commit -q -m "backup: ${BASE} (${MACHINE})" || true
        if [ "$PUSH" = true ]; then
            if git -C "$SECRETS_REPO" push 2>&1 | tail -1; then
                echo "→ private repo push 완료: claude-secrets/bundles/${BASE}.tar.gz.gpg"
            else
                echo "→ push 실패. 나중에 'git -C $SECRETS_REPO push' 재시도." >&2
            fi
        else
            echo "→ commit 만 함(--no-push). 'git -C $SECRETS_REPO push' 로 올려라."
        fi
    fi
    echo "키워드는 어디에도 저장 안 됨. 잊으면 복호화 불가 — 비번관리자에 키워드만 따로 적어둬라."
else
    echo "→ (legacy) 이 번들을 repo 밖(비번관리자/외장)으로 옮겨라. 또는 --keyword 로 private repo 자동화."
fi
