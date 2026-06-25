class_name EnemyData
extends RefCounted

# 적 등장 위치 (Arena 좌표 기준).
# 횡스크롤 시뮬레이션: 적은 화면 우측 밖에서 등장하여 PC의 RUN_SPEED에 맞춰 좌로 흘러온다.
# 즉 적 자체는 정지 상태이고, 시각상 PC가 우측으로 이동하는 효과를 시뮬레이션.

# 화면 우측 끝에서 외부로 N px (스폰 위치).
# ⚠️ [2026-06-19 빠른 이동감] 새 웨이브/보스 진입 거리 = (arena폭 360 + 이 값) − STOP_X(220).
#   RUN_SPEED를 ×1.5 했으므로 진입 '시간'(=호흡) 불변하려면 이 거리도 ×1.5 해야 함:
#   원래 D=360+50−220=190 → ×1.5=285 → 이 값 = 285 − 360 + 220 = 145. (PlayerData.RUN_SPEED·game.gd WAVE_SPACING와 한 묶음)
const SPAWN_OFFSET_FROM_RIGHT: float = 145.0  # = 50 → 진입거리 190→285(×1.5)

# 적의 화면상 y (Arena 하단 기준 위로 N px).
const SPAWN_Y_FROM_BOTTOM: float = 130.0

# 적이 멈추는 화면상 x (좌측 PC와의 거리 = 조우 위치). 적이 이 x에 도달하면 PC는 idle 진입.
const STOP_X: float = 220.0
