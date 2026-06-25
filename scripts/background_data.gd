class_name BackgroundData
extends RefCounted

# 배경 텍스처 스케일.
# 원본이 클수록 0.x로 작게 잡아 화면에 맞춤. (예: 원본 3168×1344 × 0.5 = 1584×672)
const SCALE: float = 0.4

# 배경 y 위치 보정 (sprite 좌상단을 화면 상단 기준으로 N px 이동).
# 양수 = 아래로, 음수 = 위로.
const Y_OFFSET: float = -40

# PC RUN_SPEED 대비 배경 스크롤 속도 비율.
# 1.0 = PC 속도와 동기, 1.0보다 작으면 배경이 천천히 (원경 효과).
const SCROLL_SPEED_RATIO: float = 1.0
