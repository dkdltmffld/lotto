class_name RedDot
extends Control

# 공용 빨간 점(red dot) 배지 — "받을 게 있음/새 알림" 표시. (기획: 우편함 §9-1, 리텐션 공유)
# 부모(버튼/아이콘)의 우상단 모서리에 작은 점으로 붙는다. 소유자가 set_active(bool)로만 토글.
# NotificationManager(토스트 전용)·UIManager(열고닫기 전용)에 상시 배지의 집이 없어 별도 컴포넌트로 둔다.
#
# 사용:
#   var dot := RedDot.new()
#   button.add_child(dot)       # 부모 우상단에 자동 정렬
#   dot.set_active(Mailbox.has_claimable(...))

const RADIUS: float = 5.0
const DOT_COLOR: Color = Color(0.92, 0.16, 0.16)
const RING_COLOR: Color = Color(0, 0, 0, 0.55)  # 어두운 테두리(밝은 배경에서도 보이게)

var _active: bool = false


func _ready() -> void:
	# 부모 우상단 모서리에 고정(점이 모서리에 살짝 걸침). 입력은 통과(버튼 클릭 방해 X).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	var d := RADIUS * 2.0 + 2.0
	offset_left = -d + 3.0   # 모서리에 살짝 걸치게
	offset_right = 3.0
	offset_top = -3.0
	offset_bottom = d - 3.0
	visible = _active


func set_active(on: bool) -> void:
	_active = on
	visible = on


func is_active() -> bool:
	return _active


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	draw_circle(c, RADIUS + 1.0, RING_COLOR)  # 테두리
	draw_circle(c, RADIUS, DOT_COLOR)         # 빨간 점
