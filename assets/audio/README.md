# 오디오 에셋

사운드 인프라는 `scripts/audio_manager.gd`(autoload `Audio`)에 구축돼 있습니다.
여기 파일을 넣기만 하면 코드 수정 없이 자동으로 재생됩니다. (없으면 조용히 skip)

## 포맷
- **Ogg Vorbis (`.ogg`) 권장** — 웹(HTML5) 호환·라이선스 안전. MP3는 피할 것.
- 효과음은 짧게(클릭/타격 0.1~0.5초), 배경음은 루프 가능하게.

## 넣을 위치 / 파일명 (카탈로그와 일치해야 함)
`audio_manager.gd`의 `SFX` / `BGM` 딕셔너리 key → 경로 그대로:

### sfx/
| 파일 | 언제 |
|---|---|
| `scratch.ogg` | 칸 한 개 긁힘 |
| `hand.ogg` | 카드 완성(족보) |
| `jackpot.ogg` | 잭팟(9칸 동일) |
| `attack.ogg` | 플레이어 공격 |
| `hit.ogg` | 적 타격 |
| `kill.ogg` | 적 처치 |
| `boss.ogg` | 보스 등장 |
| `player_hit.ogg` | 플레이어 피격(보스전) |
| `player_dead.ogg` | 플레이어 사망 |
| `upgrade.ogg` | 강화 구매 |
| `reward.ogg` | 보상 수령(오프라인/리텐션) |
| `button.ogg` | 버튼 클릭 |

### bgm/
| 파일 | 언제 |
|---|---|
| `main.ogg` | 평상시 |
| `boss.ogg` | 보스전(선택) |

## 볼륨/음소거
인게임 **설정 패널**에서 BGM/SFX 볼륨·음소거 조절(저장됨). 버스 = `Master → BGM/SFX`.

## 카탈로그 추가/변경
새 효과음이 필요하면 `audio_manager.gd`의 `SFX`/`BGM`에 key를 추가하고,
코어 코드에서 `Audio.play_sfx("key")` / `Audio.play_bgm("key")`로 호출하면 됩니다.
