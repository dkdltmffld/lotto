extends Control

# 첫 시작 튜토리얼 안내 배너 (상단). ⚠️ 입력을 막지 않는다(MOUSE_FILTER_IGNORE) —
# 복권 긁기·강화 버튼은 그대로 동작해야 하므로 전체를 덮는 오버레이가 아니라 상단 배너다.
# 단계 진행은 game.gd의 튜토리얼 상태머신이 게임 이벤트(카드 완성·처치·강화 클릭)로 처리하고,
# 여기엔 set_text()로 현재 안내 문구만 바꾼다. (코드 빌드, 임시 placeholder — 추후 스프라이트)

var _label: Label = null


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 배너가 게임 입력을 가리지 않음

	# 상단 안내 배너 (상태바 안전영역 아래, 복권/캐릭터를 가리지 않는 윗부분)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 14.0
	panel.offset_right = -14.0
	panel.offset_top = 78.0
	panel.offset_bottom = 158.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.92, 0.3, 0.9)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)


func set_text(msg: String) -> void:
	if _label != null:
		_label.text = msg
