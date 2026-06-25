extends Control

# 내비 밴드 패널(강화/장비/유물/상점) 공통 베이스 (2026-06-10 리팩토링).
# 공통분모: 스캐폴드(anchor fill + UISkin.panel() bg + Margin 14/14/12/12 + VBox sep8),
# closed 시그널, 헤더 탭/닫기 버튼 팩토리, 탭 활성 강조, 패널 토스트.
# ⚠️ class_name 없음 — 자식은 extends "res://scripts/panel_overlay_base.gd" 경로 기반(stale 캐시 회피).
# ⚠️ 부모 _ready 를 정의하지 않음 — 자식 _ready 첫 줄에서 _build_scaffold() 호출(노드 트리 순서 보존).

signal closed  # 닫기 버튼 → game.gd 가 받아 패널 숨김

const TAB_ACTIVE := Color(1.0, 0.85, 0.35)  # 활성 탭 글자색(다크 우드 위 호박) — 4패널 공통


func _build_scaffold() -> VBoxContainer:
	# 밴드 패널 공통 골격. 위치(상하 밴드)는 game.gd 가 offset_top/bottom 으로 지정 — 여기선 좌우 가득만.
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 배경 = 자체 UI 시트 9-slice 패널(다크 우드). 뒤(스크래치/전투)로 입력 안 샘.
	var bg := Panel.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.add_theme_stylebox_override("panel", UISkin.panel())
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	return vbox


func _on_close_pressed() -> void:
	Audio.play_sfx("button")
	closed.emit()


func make_tab_button(text: String, on_pressed: Callable, kind: String = "subtab", min_size: Vector2 = Vector2(0, 40), expand: bool = true, clip: bool = true) -> Button:
	# 헤더 탭 버튼(강화/장비 서브탭·상점 카테고리 공용). expand=false 면 size_flags 자체를 안 건드림(원형 보존).
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if clip:
		b.clip_text = true
	b.custom_minimum_size = min_size
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 16)
	UISkin.skin_button(b, kind, 4)
	b.pressed.connect(on_pressed)
	return b


func make_close_button(on_pressed: Callable) -> Button:
	# 코너 닫기 버튼 — #26 팔각형 조각 비율(79:74 ≈ 43×40)에 맞춤. 텍스트는 skin_close_icon 이 비움.
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(43, 40)
	UISkin.skin_close_icon(b)
	b.pressed.connect(on_pressed)
	return b


func set_tab_highlight(buttons: Dictionary, active_id: String, idle_color: Color, idle_modulate: float) -> void:
	# 탭 활성 강조 — 활성=TAB_ACTIVE/원색, 비활성=idle_color/살짝 어둡게.
	# idle_modulate 는 패널별로 0.85/0.82 가 다르므로 반드시 인자로(통일 시 시각 변경).
	for key in buttons:
		var b: Button = buttons[key]
		var on: bool = key == active_id
		b.add_theme_color_override("font_color", TAB_ACTIVE if on else idle_color)
		b.modulate = Color(1, 1, 1) if on else Color(idle_modulate, idle_modulate, idle_modulate)


func _toast(text: String, bottom: float = 32.0, font_size: int = 14, color: Color = Color(1.0, 0.88, 0.5), hold: float = 1.2) -> void:
	# 패널 상단에 잠깐 떴다 사라지는 안내. 기본값=장비/유물 패널 값, 상점은 (34.0, 15, Color(1.0,0.85,0.5), 1.0).
	# 표시는 NotificationManager(전역 알림 단일 경로)가 소유 — 패널 글로벌 rect 기준으로 기존 위치 재현.
	NotificationManager.panel_feedback(text, self, bottom, font_size, color, hold)


# 보상 수령 패널(우편함/퀘스트) 공용 위젯 — 두 패널이 같은 베이스를 상속해 그대로 호출.
func _status_badge(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _reward_summary_row(rewards: Array) -> Control:
	# 보상 목록을 "[아이콘]5,000  [아이콘]100" 식으로 한 줄에(재화 = 아이콘+수량, dust 는 텍스트 폴백).
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	for r in rewards:
		var rd := r as Dictionary
		hb.add_child(UISkin.currency_amount(str(rd.get("currency", "")), float(rd.get("amount", 0)), 12))
	return hb
