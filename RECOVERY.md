# 포맷/재설치 복구 (disaster recovery)

머신을 포맷해도 복구할 수 있게, 머신 로컬 "비밀"을 암호화 번들로 백업한다.
PUBLIC dotfiles 엔 비밀(평문/암호문)을 넣지 않는다 — 스크립트/문서만.
암호화 번들은 별도 PRIVATE repo `claude-secrets`(git@github.com:Gyumin5/claude-secrets.git)
에 보관한다. 패스프레이즈는 사용자 "키워드" 에서 scrypt 로 파생한다(저장 안 함).

2팩터 구조: PRIVATE repo 접근권(1차) + 키워드(2차). 둘 다 있어야 복호화 가능.
salt 는 private repo 에 함께 두지만 비밀이 아니다(키워드 없이는 무용).

## 무엇이 어디서 오나

| 자산 | 복구 경로 |
|------|-----------|
| dotfiles(유닛, 설정, 훅, 스킬, CLI) | `git clone` + `install.sh` (자동) |
| 세션별 봇 토큰, 유저봇(.env/세션), 컨트롤봇 토큰 | PRIVATE repo 번들 → `restore-secrets.sh --keyword` |
| Anthropic 자격증명(.credentials.json) | `claude login` (백업 안 함 — 재취득 쉬움) |
| ~/.claude/userbot/targets.json | 토큰에서 재생성(토큰→getMe). 백업 불필요 |
| ~/.claude.json | 백업 안 함(상태 파일). 필요 비민감 설정만 수동 |

## 백업 (평소, 주기적 + 세션/봇 추가 시) — 권장: 키워드 모드

```
bin/backup-secrets.sh --keyword
```
- 키워드를 터미널에서 입력(화면 표시 안 됨, 2회 확인). 채팅/argv 로 넘기지 말 것.
- 키워드 → scrypt(salt) → 패스프레이즈 → gpg AES256 대칭 암호화.
- 번들을 PRIVATE repo `~/claude-secrets-repo/bundles/` 에 commit + push 자동.
- 대상: `~/.claude/userbot/.env`, `~/.claude/userbot/userbot.session`(raion 제외),
  `~/.claude/control-bot/.env`, `machines/<machine>.list` 각 세션의
  `<WorkingDirectory>/.claude/telegram/.env`.
- 로컬 사본도 `~/claude-secrets-backup/` 에 남는다(즉시 산출물).

### 반드시 할 것 (안 하면 복구 불가)
1. 키워드를 비밀번호관리자에 따로 적어둔다(머릿속/비번관리자에만, repo 엔 없음).
   - 잊으면 번들 복호화 영영 불가. KDF 는 약한 키워드를 강하게 못 만든다 → 단어 여러 개 문구로.
2. PRIVATE repo `claude-secrets` 는 반드시 private 유지(공개 금지).

### legacy(랜덤 패스프레이즈) 모드 — 키워드 없이 쓰던 방식
```
bin/backup-secrets.sh          # ~/.config/claude-secrets/passphrase 자동생성, push 안 함
```
이 경우 패스프레이즈(`cat ~/.config/claude-secrets/passphrase`)와 번들을 각각
머신 밖으로 직접 옮겨 보관해야 한다(서로 다른 곳에). 신규는 --keyword 권장.

## 복구 (포맷 후) — 키워드 모드

```
# 1. dotfiles
git clone git@github.com:Gyumin5/dotfiles.git ~/dotfiles
echo home > ~/.config/claude-machine-id        # 또는 raion
# 2. PRIVATE repo clone (salt + 번들). restore 가 자동 clone 도 하지만 명시 권장.
git clone git@github.com:Gyumin5/claude-secrets.git ~/claude-secrets-repo
# 3. 최신 번들 복원 (키워드 터미널 입력 → salt 로 파생 → 복호화)
~/dotfiles/bin/restore-secrets.sh --keyword --auto-latest
# 4. 설치
~/dotfiles/install.sh
# 5. Anthropic 로그인
claude login
# 6. 세션 enable (install 이 토큰 있는 세션만 enable). 필요시 SETUP.md 참고.
```

### restore-secrets.sh 옵션
- `--keyword` 키워드→scrypt 파생 패스프레이즈(터미널 입력). salt 는 private repo.
- `--auto-latest` 번들 생략 시 private repo 에서 이 머신 최신 번들 자동선택
- `--dry-run` 복원 목록만 출력
- `--force` 기존 파일 백업 없이 덮어씀(기본은 `.pre-restore.<ts>` 백업)
- `--passfile PATH` (legacy) 패스프레이즈 파일 경로 지정
- `--include-userbot-session` raion 등에서 userbot.session 강제 복원(기본 제외)

## 주의
- userbot.session(MTProto) 이동성: 검증됨(2026-06-05, 동일 머신). 라이브 유저봇을
  안 끊고 session 파일을 격리 HOME 에 복사 → Telethon `is_user_authorized`+`get_me`
  통과(재로그인 불필요). 단 이번 검증은 같은 IP. 새 머신(다른 IP)에서 텔레그램이
  드물게 재인증을 요구할 가능성은 0은 아님 → 안 되면 `claude-userbot-login`(SMS/2FA)
  fallback. 재검증법: 유저봇 중지 후 다른 HOME 에 복원→ `is_user_authorized`/`get_me`.
- raion(회사 머신)엔 개인 텔레그램 userbot.session 을 기본 복원하지 않는다
  (회사 머신에 개인 계정 세션 보관 위험). 필요 시 명시 플래그.
- PUBLIC dotfiles repo 엔 번들/패스프레이즈/메타를 절대 커밋하지 말 것(.gitignore 로 방어).
  번들/메타/salt 는 PRIVATE `claude-secrets` repo 에만 둔다. 키워드는 어디에도 안 둔다.
- `claude-secrets` repo 가 실수로 public 이 되면 즉시 private 전환 + 키워드 변경(=salt 재생성
  후 전 머신 재백업). public 노출 시엔 키워드만이 유일한 방어막이라 약하면 위험.
