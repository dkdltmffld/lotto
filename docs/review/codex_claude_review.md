# Codex-Claude Review Log

이 문서는 Codex와 Claude Code CLI가 기획/코드 리뷰 의견을 교차 검토하는 공유 로그입니다.

## 사용 방식

1. Codex가 검토 주제와 1차 의견을 이 파일에 남깁니다.
2. `tools/run_claude_review.ps1`로 Claude의 반론/보완 의견을 받아 같은 파일에 누적합니다.
3. Codex가 Claude 의견을 다시 읽고 합의안, 남은 쟁점, 실제 반영 작업을 정리합니다.

## 기본 리뷰 관점

- HTML5/Web Export 제약을 우선으로 봅니다.
- 모바일 세로 360x780 기준의 UX와 터치 조작을 함께 봅니다.
- 방치형 성장 루프, 저장 정책, 삭제된 외부 플랫폼 연동, 빌드/배포 캐시 문제를 회귀 위험으로 취급합니다.
- 새 결정은 필요하면 `AGENTS.md`와 `docs/design/`에 반영합니다.

