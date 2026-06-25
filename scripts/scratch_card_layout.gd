class_name ScratchCardLayout
extends RefCounted

# 스크래치 카드 영역(ScratchCardArea)의 화면상 위치·크기·스케일을 한 곳에서 관리.
# `game.gd._ready()`에서 이 값들을 영역 노드에 적용한다.
# 영역의 anchor는 main.tscn에서 화면 하단·좌우 가득(anchor_top=1, anchor_bottom=1, anchor_right=1)으로 잡혀 있으며,
# 아래 값들은 그 anchor 안에서 offset/scale을 결정한다.

# 영역의 세로 높이 (px)
const HEIGHT: float = 240.0

# 화면 바닥에서 영역 하단까지의 여백 (px). 양수일수록 영역이 위로 올라옴.
# 2026-06-05: 내비 도크를 스크래치 위(전투-내비-스크래치 순)로 옮김 → 스크래치는 다시 바닥(38)으로.
const BOTTOM_MARGIN: float = 38.0

# 영역 너비 (px). 양수면 명시 너비, 0(또는 음수)이면 화면 가로 가득.
# 좌측 정렬이 기본이며, X_OFFSET으로 가로 위치 조정 가능.
const WIDTH: float = 260.0

# 영역 전체 스케일. 자식인 CardBackground와 ScratchCard도 함께 확대·축소된다. 초기값 1
# 2026-05-29: 0.6 → 0.528. 티켓+스크래치를 하나의 단위로 ~12% 축소+중앙정렬해
# 좌우 크롭에도 양쪽 가장자리가 안 잘리게 함(티켓/스크래치에 동일 변환 적용 → 정렬 유지).
const SCALE: float = 0.528

# X 위치 미세 조정 (px). 양수 = 오른쪽으로, 음수 = 왼쪽으로.
const X_OFFSET: float = 195.0

# Y 위치 미세 조정 (px). 양수 = 아래쪽으로, 음수 = 위쪽으로.
# 2026-06-05: 69 → 88 (#16 스크래치 배경 안에서 콘텐츠가 위로 몰려 보여 아래로 내림. 티켓도 같이).
const Y_OFFSET: float = 88.0


# --- 티켓 배경(TicketBackground) 설정 ---
# TicketBackground는 ScratchCardArea와 독립된 노드(Main 자식)이며 화면 좌상단 기준 절대 좌표로 표시된다.
# 영역의 SCALE/X_OFFSET/Y_OFFSET 영향을 받지 않으므로 별도로 자유롭게 위치·크기 조정 가능.

# 티켓 배경 스케일 (원본 993×463 기준)
# 2026-05-29: 0.36 → 0.317 (스크래치와 동일 ~12% 축소). 폭 ~315px로 좁혀 좌우 여백 확보.
const TICKET_BG_SCALE: float = 0.317

# 티켓 배경 X 위치 (화면 좌상단 기준, px). 축소 후 화면 중앙 정렬(좌우 여백 ~22px 대칭).
const TICKET_BG_X: float = 23.0

# 티켓 배경 Y 위치 (화면 좌상단 기준, px)
# 2026-06-05: 560 → 579 (스크래치 콘텐츠 아래로 내림 — 그리드 Y_OFFSET과 동일량 이동, 정렬 유지).
const TICKET_BG_Y: float = 579.0
