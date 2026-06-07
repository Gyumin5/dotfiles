# 미사용 capability 근거 리포트 (2026-06-07)

- 생성: 2026-06-07T22:59:44.841526+00:00  (KST 변환은 +9h)
- 윈도우: 최근 90일
- telemetry: skill-calls=있음, ai-calls=있음
- ⚠️ 삭제/비활성화 판단 금지. 이건 읽기전용 근거 리포트일 뿐. 정리는 사람이 ADR + 복구경로 남기고 결정.
- status: observed=윈도우 내 사용, stale=윈도우 밖 마지막 사용, unused=기록 없음, no_telemetry=수집 안 됨, def_not_found=정의 미발견.

| kind | name | count(win) | last_seen | status | def_location |
|---|---|---|---|---|---|
| skill | ai-collaborate | 29 | 2026-06-04T01:56:22+00:00 | observed | /home/gmoh/dotfiles/claude/skills/ai-collaborate; /home/gmoh/.claude/skills/ai-collaborate |
| skill | handoff | 0 | - | unused(근거없음) | /home/gmoh/dotfiles/claude/skills/handoff; /home/gmoh/.claude/skills/handoff |
| skill | handoff-verify | 0 | - | unused(근거없음) | /home/gmoh/dotfiles/claude/skills/handoff-verify; /home/gmoh/.claude/skills/handoff-verify |
| skill | paper-fit | 3 | 2026-06-04T03:41:11+00:00 | observed | /home/gmoh/dotfiles/claude/skills/paper-fit; /home/gmoh/.claude/skills/paper-fit |
| skill | plan | 0 | - | unused(근거없음) | /home/gmoh/dotfiles/claude/skills/plan; /home/gmoh/.claude/skills/plan |
| skill | project-init | 0 | - | unused(근거없음) | /home/gmoh/dotfiles/claude/skills/project-init; /home/gmoh/.claude/skills/project-init |
| skill | project-review | 0 | - | unused(근거없음) | /home/gmoh/dotfiles/claude/skills/project-review; /home/gmoh/.claude/skills/project-review |
| skill | claude-scientific-writer:generate-image | 4 | 2026-05-04T05:12:26+00:00 | def_not_found | (정의 미발견 — 플러그인?) |
| skill | deep-research | 1 | 2026-06-04T08:27:08+00:00 | def_not_found | (정의 미발견 — 플러그인?) |
| skill | loop | 1 | 2026-05-21T02:17:49+00:00 | def_not_found | (정의 미발견 — 플러그인?) |
| mcp | academic-search | - | - | no_telemetry | /home/gmoh/dotfiles/claude/mcp.json; /home/gmoh/.claude/mcp.json |
| mcp | arxiv-latex | - | - | no_telemetry | /home/gmoh/dotfiles/claude/mcp.json; /home/gmoh/.claude/mcp.json |

## AI provider 사용(참고, ai-calls.jsonl)
| provider | count(win) | last_seen |
|---|---|---|
| codex | 2413 | 2026-06-07T22:58:03+00:00 |
| gemini | 1040 | 2026-06-07T01:00:32+00:00 |
| test | 1 | 2026-04-27T09:16:28+00:00 |

_근거가 부족하면(예: telemetry 비어있음) 미사용으로 단정하지 말 것._
