class_name NavDock
extends Control

# 하단 고정 내비게이션 도크 (레퍼런스 "키우기" UI). 코드 빌드(다른 패널과 일관).
# 탭을 누르면 tab_selected(id) emit → game.gd 가 해당 패널 오버레이를 띄운다.
# 스크래치 카드는 이 도크 위에 상주하고, 메뉴 패널은 그 위로 겹쳐 뜬다.
# 아이콘은 더미 단계라 텍스트만(번들 폰트가 한글 전용 → 이모지 깨짐). Phase 2에서 스프라이트 교체.

signal tab_selected(id: String)

const HEIGHT: float = 58.0

# id / 표시명. 강화만 실제 동작, 나머지는 준비중(placeholder) — 레퍼런스식 5탭 구조.
const TABS: Array = [
	{"id": "upgrade", "name": "강화"},
	{"id": "equip", "name": "장비"},
	{"id": "relic", "name": "유물"},
	{"id": "dungeon", "name": "던전"},
	{"id": "shop", "name": "상점"},
]

const RedDotScript = preload("res://scripts/red_dot.gd")

var _buttons: Dictionary = {}  # id -> Button
var _red_dots: Dictionary = {} # id -> RedDot (가이드 배지 — 무료 소환/미장착 유물 등)


func _ready() -> void:
	# 화면 하단 가득, 고정 높이.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -HEIGHT
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP  # 도크 영역 입력이 뒤(스크래치)로 새지 않게

	# 배경 = Kenney 9-slice 패널 스킨 (회청 패널, 약간 어둡게 틴트)
	var bg := Panel.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UISkin.nav_bg())
	add_child(bg)

	var hb := HBoxContainer.new()
	hb.anchor_right = 1.0
	hb.anchor_bottom = 1.0
	hb.offset_left = 4.0
	hb.offset_right = -4.0
	hb.offset_top = 4.0
	hb.offset_bottom = -4.0
	hb.add_theme_constant_override("separation", 3)
	add_child(hb)

	for t in TABS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.text = String(t["name"])
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Color(0.9, 0.86, 0.76))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
		b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.7))
		UISkin.skin_button(b, "nav", 2)  # Kenney 9-slice 버튼 스킨
		var id: String = String(t["id"])
		b.pressed.connect(func() -> void: tab_selected.emit(id))
		hb.add_child(b)
		_buttons[id] = b


func get_button(id: String) -> Button:
	return _buttons.get(id, null)


func set_locked(id: String, locked: bool) -> void:
	# 잠금 = 버튼 음영(딤). 누름은 막지 않는다(진입 시도 시 game 이 안내 토스트를 띄움 → disabled 대신 modulate).
	var b: Button = _buttons.get(id, null)
	if b == null:
		return
	b.modulate = Color(0.5, 0.5, 0.52, 0.6) if locked else Color(1, 1, 1, 1)


func set_red_dot(id: String, on: bool) -> void:
	# 탭 버튼 우상단 빨간 점 토글(가이드 — 무료 확정 소환 대기/미장착 유물 등). 처음 켤 때만 생성.
	var b: Button = _buttons.get(id, null)
	if b == null:
		return
	var dot = _red_dots.get(id, null)
	if dot == null:
		if not on:
			return
		dot = RedDotScript.new()
		b.add_child(dot)
		_red_dots[id] = dot
	dot.set_active(on)
