extends "res://scripts/panel_overlay_base.gd"

# 던전 "시련의 탑" 진입 패널 — 내비 "던전" 탭. 강화/장비/유물/상점과 동일 밴드(스크래치 영역).
# 데일리 던전(2026-06-18): 입장권(일일 무료) 소모 입장 / 클리어 층 재도전(반복 보상) / 자동 등반 토글.
# 층 리스트(재도전✓ / 도전 / 잠금) + 룰 + 보상. "도전/재도전" → Events.dungeon_enter_requested(floor)
# → game.gd 가 입장권 소모 후 던전 전투 모드로 진입(전투·결과는 game.gd 소유).
# 다음 도전 가능 층 = 최고 클리어 층 + 1(순차 게이트). 깬 층은 재도전(반복 보상) 가능.
# 기획서: docs/design/던전 시스템 정리본.md §7
# closed/스캐폴드/닫기/_toast = panel_overlay_base 공용.

const DungeonDataScript = preload("res://scripts/dungeon_data.gd")

const CLEARED_COLOR := Color(0.55, 0.85, 0.5)   # 클리어(초록, 재도전 가능)
const CURRENT_COLOR := Color(1.0, 0.85, 0.4)    # 도전 가능(호박)
const LOCKED_COLOR := Color(0.5, 0.5, 0.55)     # 잠금(회색)

var _header: Label = null
var _auto_note: Label = null  # 자동 등반 상태(읽기 전용 — 끄기는 설정에서)
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	var vbox := _build_scaffold()

	# Row 1: 제목(입장권·최고층) + 닫기
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 15)
	_header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_header)
	header.add_child(make_close_button(_on_close_pressed))
	vbox.add_child(header)

	# Row 2: 자동 등반 상태(읽기 전용). 자동 등반은 기본 상시 동작 — 끄기는 설정에서만(2026-06-18 결정).
	_auto_note = Label.new()
	_auto_note.add_theme_font_size_override("font_size", 11)
	_auto_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_auto_note)

	# 층 리스트
	_scroll = UISkin.make_vlist_scroll()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	vbox.add_child(_scroll)


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	var prev_scroll: int = _scroll.scroll_vertical if _scroll != null else 0  # 재진입 시 스크롤 위치 보존
	var cleared: int = BackendService.get_dungeon_max_cleared()
	var tickets: int = BackendService.get_dungeon_tickets()
	var auto_on: bool = BackendService.get_dungeon_auto()
	_header.text = "시련의 탑   입장권 %d   (최고 %d층)" % [tickets, cleared]
	_auto_note.text = "자동 등반 켜짐 (설정에서 끄기)" if auto_on else "자동 등반 꺼짐 (층마다 수동)"
	_auto_note.add_theme_color_override("font_color", Color(0.9, 0.8, 0.45) if auto_on else Color(0.7, 0.7, 0.72))
	UISkin.clear_children(_list)
	var n: int = DungeonDataScript.floor_count()
	var has_ticket: bool = tickets > 0
	for f in range(1, n + 1):
		_list.add_child(_build_row(f, cleared, has_ticket))
	# 스크롤 복원은 다음 프레임(재레이아웃 후 max_value 확정)에 — 즉시 설정하면 안 먹힘.
	if prev_scroll > 0:
		_scroll.set_deferred("scroll_vertical", prev_scroll)


func _build_row(floor: int, cleared: int, has_ticket: bool) -> Control:
	var is_cleared: bool = floor <= cleared
	var is_current: bool = floor == cleared + 1
	var col: Color = CLEARED_COLOR if is_cleared else (CURRENT_COLOR if is_current else LOCKED_COLOR)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.inset_row_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "%d층" % floor
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", col)
	info.add_child(title)

	var rule := Label.new()
	rule.text = DungeonDataScript.rule_text(floor)
	rule.add_theme_font_size_override("font_size", 11)
	rule.add_theme_color_override("font_color", Color(0.82, 0.82, 0.78))
	rule.clip_text = true
	info.add_child(rule)

	var reward_txt: String = _reward_text(floor, is_cleared)
	if reward_txt != "":
		var reward := Label.new()
		reward.text = reward_txt
		reward.add_theme_font_size_override("font_size", 11)
		reward.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		reward.clip_text = true
		info.add_child(reward)
	row.add_child(info)

	# 버튼: 도전(미클리어 다음 층) / 재도전(클리어 층) — 입장권 필요. 잠금(미해금).
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72, 38)
	btn.add_theme_font_size_override("font_size", 12)
	if is_cleared or is_current:
		btn.text = (("재도전" if is_cleared else "도전") if has_ticket else "입장권 부족")
		btn.disabled = not has_ticket
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
		UISkin.skin_button(btn, "buy", 4)
		if has_ticket:
			btn.pressed.connect(func() -> void: _challenge(floor))
	else:
		btn.text = "잠금"
		btn.disabled = true
		UISkin.skin_button(btn, "subtab", 4)
	row.add_child(btn)
	return panel


func _reward_text(floor: int, is_cleared: bool) -> String:
	# 미클리어 = 첫 돌파 보상(다이아·가루) / 클리어 = 재도전 보상(골드·소량가루). ⚠️ 가운데점(·) 금지 → " / ".
	var parts: Array = []
	if is_cleared:
		var rg: float = Balance.gold_reward(DungeonDataScript.stage_equiv(floor)) * Balance.DUNGEON_REPEAT_GOLD_MULT
		var rd: int = int(DungeonDataScript.dust(floor) * Balance.DUNGEON_REPEAT_DUST_RATIO)
		if rg > 0.0:
			parts.append("골드 %s" % UISkin.fmt_currency(rg))
		if rd > 0:
			parts.append("가루 %d" % rd)
		if parts.is_empty():
			return ""
		return "재도전: " + " / ".join(parts)
	var d: float = DungeonDataScript.dia(floor)
	var du: float = DungeonDataScript.dust(floor)
	if d > 0.0:
		parts.append("다이아 %d" % int(d))
	if du > 0.0:
		parts.append("가루 %d" % int(du))
	if parts.is_empty():
		return ""
	return "첫 돌파: " + " / ".join(parts)


func _challenge(floor: int) -> void:
	Audio.play_sfx("button")
	Events.dungeon_enter_requested.emit(floor)
