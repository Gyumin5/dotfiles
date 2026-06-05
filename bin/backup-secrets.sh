#!/bin/bash
# backup-secrets.sh — 머신 로컬 비밀을 단일 암호화 번들로 백업.
#
# 설계 (ai-debate 2026-06-05 #B+C): repo 엔 비밀을 암호문으로도 안 넣는다.
# 이 스크립트가 비밀을 모아 gpg(AES256) 대칭암호 단일 tar 로 만든다. 번들은
# repo 밖(~/claude-secrets-backup/)에 떨어지며, 사용자가 비밀번호관리자/외부에
# 옮겨 보관해야 한다. 패스프레이즈도 비밀번호관리자에 보관(없으면 복호화 불가).
#
# 암호화 도구: gpg --symmetric --cipher-algo AES256 (키링/신뢰모델 없음, 패스프레이즈만).
#   age 가 선호였으나 설치가 샌드박스에서 막혀 gpg 대칭으로 대체. 둘 다 AES256.
#
# 백업 대상 (manifest):
#   - ~/.claude/userbot/.env            (Telegram API_ID/HASH)
#   - ~/.claude/userbot/userbot.session (MTProto 세션; raion 머신은 기본 제외)
#   - ~/.claude/control-bot/.env        (컨트롤봇 토큰)
#   - machines/<machine>.list 의 각 세션 <WorkingDirectory>/.claude/telegram/.env (봇 토큰)
# 제외(재취득 가능): ~/.claude/.credentials.json(claude login), ~/.claude.json 전체,
#   ~/.claude/userbot/targets.json(토큰에서 파생).
#
# 사용법: backup-secrets.sh [-o OUTDIR]
set -uo pipefail

HOME_DIR="${HOME}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MACHINE_FILE="$HOME_DIR/.config/claude-machine-id"
PASS_DIR="$HOME_DIR/.config/claude-secrets"
PASSFILE="$PASS_DIR/passphrase"
OUTDIR="$HOME_DIR/claude-secrets-backup"

while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUTDIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

command -v gpg >/dev/null || { echo "gpg 없음. gpg 설치 필요." >&2; exit 1; }

MACHINE="$(cat "$MACHINE_FILE" 2>/dev/null || echo unknown)"

# 패스프레이즈: 없으면 생성(첫 실행). 강력 경고.
mkdir -p "$PASS_DIR"; chmod 700 "$PASS_DIR"
if [ ! -s "$PASSFILE" ]; then
    head -c 32 /dev/urandom | base64 | tr -d '\n' > "$PASSFILE"
    chmod 600 "$PASSFILE"
    echo "!! 새 패스프레이즈 생성: $PASSFILE"
    echo "!! 반드시 비밀번호관리자에 복사해 둬라(이거 없으면 번들 복호화 불가):"
    echo "!!   cat $PASSFILE"
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
LIST="$REPO_DIR/machines/${MACHINE}.list"
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
cleanup() { rm -f "$TARPLAIN"; }
trap cleanup EXIT

tar -C "$HOME_DIR" -czf "$TARPLAIN" "${rel_list[@]}"
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
    --symmetric --cipher-algo AES256 -o "$BUNDLE" "$TARPLAIN"
chmod 600 "$BUNDLE"

# 메타 (파일명/해시만, 내용 평문 없음)
{
    echo "created: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "machine: $MACHINE"
    echo "hostname: $(hostname)"
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
        echo "ⓘ 직전 백업 대비 비밀 파일 목록이 바뀌었다(세션 추가/삭제 등). 새 번들 보관 권장."
    fi
fi

echo "백업 완료:"
echo "  번들: $BUNDLE"
echo "  메타: $META"
echo "  파일 ${#rel_list[@]}개 (세션 ${#sessions[@]}개 + 글로벌)"
echo "→ 이 번들을 repo 밖(비밀번호관리자/외장)으로 옮겨 보관해라. repo 에 두지 마라."
