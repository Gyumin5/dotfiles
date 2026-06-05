# 포맷/재설치 복구 (disaster recovery)

머신을 포맷해도 복구할 수 있게, 머신 로컬 "비밀"을 암호화 번들로 백업한다.
설계 결정: ai-debate 2026-06-05 (B+C 하이브리드). repo 에는 비밀을 평문도 암호문도
넣지 않는다. 스크립트/문서만 repo, 실제 비밀은 repo 밖 암호화 번들로 보관.

## 무엇이 어디서 오나

| 자산 | 복구 경로 |
|------|-----------|
| dotfiles(유닛, 설정, 훅, 스킬, CLI) | `git clone` + `install.sh` (자동) |
| 세션별 봇 토큰, 유저봇(.env/세션), 컨트롤봇 토큰 | 암호화 번들 → `restore-secrets.sh` |
| Anthropic 자격증명(.credentials.json) | `claude login` (백업 안 함 — 재취득 쉬움) |
| ~/.claude/userbot/targets.json | 토큰에서 재생성(토큰→getMe). 백업 불필요 |
| ~/.claude.json | 백업 안 함(상태 파일). 필요 비민감 설정만 수동 |

## 백업 (평소, 주기적 + 세션/봇 추가 시)

```
bin/backup-secrets.sh
```
- 대상: `~/.claude/userbot/.env`, `~/.claude/userbot/userbot.session`(raion 제외),
  `~/.claude/control-bot/.env`, `machines/<machine>.list` 각 세션의
  `<WorkingDirectory>/.claude/telegram/.env`.
- 암호화: gpg `--symmetric` AES256 (패스프레이즈만, 키링 없음).
  (age 선호였으나 설치 제약으로 gpg 대칭 사용. 둘 다 AES256.)
- 산출: `~/claude-secrets-backup/claude-secrets-<machine>-<ts>.tar.gz.gpg` (+ `.meta`).
- 첫 실행 시 패스프레이즈 자동 생성: `~/.config/claude-secrets/passphrase` (600).

### 반드시 할 것 (안 하면 복구 불가)
1. 패스프레이즈를 비밀번호관리자에 복사: `cat ~/.config/claude-secrets/passphrase`
2. 번들(.tar.gz.gpg)을 repo 밖 안전한 곳(비번관리자 첨부/외장/프라이빗 저장소)으로 이동.
   - 패스프레이즈와 번들을 같은 단일 보관처에만 두지 말 것(둘 다 잃으면 끝).

## 복구 (포맷 후)

```
# 1. dotfiles
git clone git@github.com:Gyumin5/dotfiles.git ~/dotfiles
echo home > ~/.config/claude-machine-id        # 또는 raion
# 2. 패스프레이즈 복원 (비번관리자 → 파일)
mkdir -p ~/.config/claude-secrets && chmod 700 ~/.config/claude-secrets
printf '%s' '<비번관리자의 패스프레이즈>' > ~/.config/claude-secrets/passphrase
chmod 600 ~/.config/claude-secrets/passphrase
# 3. 번들 가져와 복원 (+install 이 자동 호출하게 하려면 CLAUDE_SECRETS_BUNDLE 지정)
~/dotfiles/bin/restore-secrets.sh <번들.tar.gz.gpg>
# 4. 설치 (CLAUDE_SECRETS_BUNDLE 주면 3을 install 이 대신 함)
CLAUDE_SECRETS_BUNDLE=<번들> ~/dotfiles/install.sh
# 5. Anthropic 로그인
claude login
# 6. 세션 enable (install 이 토큰 있는 세션만 enable). 필요시 SETUP.md 참고.
```

### restore-secrets.sh 옵션
- `--dry-run` 복원 목록만 출력
- `--force` 기존 파일 백업 없이 덮어씀(기본은 `.pre-restore.<ts>` 백업)
- `--passfile PATH` 패스프레이즈 파일 경로 지정
- `--include-userbot-session` raion 등에서 userbot.session 강제 복원(기본 제외)

## 주의/미검증
- userbot.session(MTProto) 이동성: 새 머신에 복원해도 재로그인 없이 동작하는지
  미검증. 안 되면 `claude-userbot-login`(SMS/2FA) 재실행. 확인법:
  유저봇 중지 후 다른 HOME 에 복원→ `is_user_authorized`/`getMe` 성공 여부.
- raion(회사 머신)엔 개인 텔레그램 userbot.session 을 기본 복원하지 않는다
  (회사 머신에 개인 계정 세션 보관 위험). 필요 시 명시 플래그.
- 번들/패스프레이즈/메타는 절대 git 에 커밋하지 말 것(.gitignore 로 방어).
