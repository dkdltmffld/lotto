extends "res://scripts/panel_overlay_base.gd"

# 유물 인벤토리 오버레이 — 내비 "유물" 탭. 강화/장비/상점 패널과 동일 밴드(스크래치 영역).
# 구성: 가루 잔액 + 장착 5슬롯 + 보유 목록(장착/해제). 기획: 족보 스킬 시스템 정리본 §5.
# 뽑기(가루 가챠)는 상점 > 소환 > 유물로 이전(2026-06-10) — 여기는 보유/장착 관리 전용.
# 데이터: BackendService.get_relics()/get_relic_slots()/equip·unequip, 효과/등급은 Relics 헬퍼.
# closed 시그널·스캐폴드·닫기 버튼·_toast 는 panel_overlay_base, 등급색/이름·_fmt 류는 UISkin 공용.

# 장착/해제 효과 변동 통지 = Events.relics_changed(전역 버스) — game.gd 가 구독해 분포·HUD 갱신.

const RelicsScript = preload("res://scripts/relics.gd")

var _dust_label: Label = null
var _slots_box: HBoxContainer = null
var _slots_title: Label = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _empty: Label = null


func _ready() -> void:
	var vbox := _build_scaffold()

	# Row 1: 가루 잔액(좌) + 닫기(우)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	_dust_label = Label.new()
	_dust_label.add_theme_font_size_override("font_size", 13)
	_dust_label.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	_dust_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dust_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_dust_label)
	header.add_child(make_close_button(_on_close_pressed))
	vbox.add_child(header)

	# Row 3: 장착 슬롯 타이틀 + 슬롯
	_slots_title = Label.new()
	_slots_title.add_theme_font_size_override("font_size", 12)
	_slots_title.add_theme_color_override("font_color", Color(0.88, 0.85, 0.76))
	vbox.add_child(_slots_title)
	_slots_box = HBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_slots_box)

	# 보유 목록
	_scroll = UISkin.make_vlist_scroll()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	vbox.add_child(_scroll)

	_empty = UISkin.make_empty_label("보유한 유물이 없습니다.\n상점 > 소환 > 유물에서 뽑아 보세요!")
	vbox.add_child(_empty)

	# 외부 가루 변동(보스 처치 등)도 열려 있으면 즉시 반영. (autoload→씬노드 연결은 free 시 자동 해제)
	Events.currency_changed.connect(_on_currency_changed)


func _on_currency_changed() -> void:
	# 가루 변동 시 열려 있으면 잔액만 즉시 갱신(보유 목록은 재화와 무관 → 재구성 불필요).
	if visible:
		_refresh_dust_label()


func _refresh_dust_label() -> void:
	if _dust_label != null:
		_dust_label.text = "유물 가루: %s" % UISkin.fmt_currency(BackendService.get_dust())


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	_refresh_dust_label()

	# 장착 슬롯 (n/5)
	var equipped: Array = BackendService.get_equipped_relics()
	var slot_n: int = BackendService.relic_slot_count()
	_slots_title.text = "장착 (%d/%d) - 누르면 해제" % [equipped.size(), slot_n]  # ASCII 하이픈(em-dash는 번들폰트에 없어 웹서 깨짐)
	UISkin.clear_children(_slots_box)
	for inst in equipped:
		_slots_box.add_child(_slot_chip(inst as Dictionary))
	for i in range(equipped.size(), slot_n):
		_slots_box.add_child(_empty_slot())

	# 보유 목록 (등급 높은 순)
	UISkin.clear_children(_list)
	var relics: Array = BackendService.get_relics().duplicate()
	relics.sort_custom(_compare_inst)
	_empty.visible = relics.is_empty()
	_scroll.visible = not relics.is_empty()
	var slots_full: bool = equipped.size() >= slot_n
	for inst in relics:
		_list.add_child(_build_row(inst as Dictionary, slots_full))


func _slot_chip(inst: Dictionary) -> Button:
	var grade: String = str(inst.get("grade", "common"))
	var col: Color = UISkin.GRADE_COLOR.get(grade, Color(0.8, 0.8, 0.8))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", col)
	b.clip_text = true
	b.text = RelicsScript.relic_name(str(inst.get("effect", "")))
	# ⚠️ 칩은 content margin 미설정(-1 = StyleBox 기본값) — 기본 마진(6,6,4,4) 전달 시 레이아웃 변경
	var sb := UISkin.grade_row_style(col, 0.18, 5, 1, 0.7, Vector4i(-1, -1, -1, -1))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	var uid: String = str(inst.get("uid", ""))
	b.pressed.connect(func() -> void: _do_unequip(uid))
	return b


func _empty_slot() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, 34)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.2)
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.5, 0.5, 0.55, 0.4)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = "빈 슬롯"
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _build_row(inst: Dictionary, slots_full: bool) -> Control:
	var uid: String = str(inst.get("uid", ""))
	var effect: String = str(inst.get("effect", ""))
	var grade: String = str(inst.get("grade", "common"))
	var col: Color = UISkin.GRADE_COLOR.get(grade, Color(0.8, 0.8, 0.8))
	var equipped: bool = BackendService.is_relic_equipped(uid)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.grade_row_style(col))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = "[%s] %s" % [UISkin.GRADE_NAME.get(grade, grade), RelicsScript.relic_name(effect)]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", col)
	name_lbl.clip_text = true
	info.add_child(name_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = RelicsScript.relic_desc(effect, grade)
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.78))
	desc_lbl.clip_text = true
	info.add_child(desc_lbl)
	row.add_child(info)

	# 장착/해제
	var eq_btn := Button.new()
	eq_btn.focus_mode = Control.FOCUS_NONE
	eq_btn.custom_minimum_size = Vector2(52, 30)
	eq_btn.add_theme_font_size_override("font_size", 12)
	eq_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	eq_btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))
	if equipped:
		eq_btn.text = "해제"
		UISkin.skin_button(eq_btn, "subtab", 4)
		eq_btn.pressed.connect(func() -> void: _do_unequip(uid))
	else:
		eq_btn.text = "장착"
		UISkin.skin_button(eq_btn, "nav", 4)
		eq_btn.disabled = slots_full
		eq_btn.pressed.connect(func() -> void: _do_equip(uid))
	row.add_child(eq_btn)

	return panel


func _do_equip(uid: String) -> void:
	if BackendService.equip_relic(uid):
		Audio.play_sfx("button")
		Events.relics_changed.emit()
		refresh()
	else:
		Audio.play_sfx("button")
		_toast("슬롯이 가득 찼습니다 (해제 후 장착)")


func _do_unequip(uid: String) -> void:
	Audio.play_sfx("button")
	BackendService.unequip_relic(uid)
	Events.relics_changed.emit()
	refresh()


# (뽑기·결과 팝업은 상점 > 소환 > 유물로 이전 — shop_panel._do_relic_pull/_show_gacha_result)


func _compare_inst(a: Variant, b: Variant) -> bool:
	var ga: String = str((a as Dictionary).get("grade", ""))
	var gb: String = str((b as Dictionary).get("grade", ""))
	var ia: int = RelicsScript.grade_index(ga)
	var ib: int = RelicsScript.grade_index(gb)
	return ia > ib
