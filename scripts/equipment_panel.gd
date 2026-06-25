extends "res://scripts/panel_overlay_base.gd"

# 장비 인벤토리 오버레이 — 내비 "장비" 탭. 강화/상점 패널과 동일 밴드(스크래치 영역).
# 종류 탭(무기/방어구) + 장착 슬롯 표시 + 보유 인스턴스 목록(행마다 장착/강화, 상단 합성).
# 기획: docs/design/장비 시스템 정리본.md
# 데이터: BackendService.get_equips(pool) → [{uid,item,level}], 스탯/등급은 Gacha.item_info / equip_bonus.

# 장착/강화/합성 스탯 변동 통지 = Events.equipment_changed(전역 버스) — game.gd 가 구독해 HUD·최대체력 갱신.

const GachaScript = preload("res://scripts/gacha.gd")
const GOLD_ICON := preload("res://assets/ui/icon/icon_gold.png")  # 강화 비용 골드 아이콘

const STAT_LABEL := {"attack": "공격력", "hp": "체력"}

const TYPES := [{"id": "weapon", "name": "무기"}, {"id": "armor", "name": "방어구"}]
const TAB_IDLE := Color(0.72, 0.70, 0.66)

var _pool: String = "weapon"
var _type_buttons: Dictionary = {}
var _equipped_label: Label = null
var _combine_btn: Button = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _empty: Label = null
# 강화(골드) 버튼 + 비용 추적 — 리스트 재구성 없이 활성 여부만 제자리 갱신(refresh_affordability)용.
var _enh_rows: Array = []  # [{btn: Button, cost: int}]


func _ready() -> void:
	var vbox := _build_scaffold()

	# Row 1: 무기/방어구 탭(강화 패널의 강화/성장 위치·크기와 동일: 헤더, 0×40, font16, subtab) + 닫기
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	for t in TYPES:
		var id: String = String(t["id"])
		var b := make_tab_button(String(t["name"]), func() -> void: _select_type(id))
		header.add_child(b)
		_type_buttons[id] = b
	header.add_child(make_close_button(_on_close_pressed))
	vbox.add_child(header)

	# Row 2: 장착 현황(좌) + 합성(우, 위치 유지) — 같은 줄로 정렬
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	_equipped_label = Label.new()
	_equipped_label.add_theme_font_size_override("font_size", 12)
	_equipped_label.add_theme_color_override("font_color", Color(0.88, 0.85, 0.76))
	_equipped_label.clip_text = true
	_equipped_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipped_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row2.add_child(_equipped_label)
	_combine_btn = UISkin.make_buy_button(Vector2(84, 32), 13, 4, true, true, Color(0.5, 0.5, 0.55))
	_combine_btn.text = "전체 합성"
	_combine_btn.pressed.connect(_on_combine_pressed)
	row2.add_child(_combine_btn)
	vbox.add_child(row2)

	# 보유 목록
	_scroll = UISkin.make_vlist_scroll()
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	vbox.add_child(_scroll)

	# 빈 안내
	_empty = UISkin.make_empty_label("보유한 장비가 없습니다.\n상점 > 소환에서 뽑아 보세요!")
	vbox.add_child(_empty)


func open() -> void:
	_select_type("weapon")
	visible = true


func _select_type(pool: String) -> void:
	_pool = pool
	set_tab_highlight(_type_buttons, pool, TAB_IDLE, 0.82)
	refresh()


func refresh() -> void:
	var stat_lbl: String = str(STAT_LABEL.get(GachaScript.pool_stat(_pool), GachaScript.pool_stat(_pool)))

	# 장착 슬롯
	var eq_uid: String = BackendService.get_equipped(_pool)
	if eq_uid == "":
		_equipped_label.text = "장착: 없음"
	else:
		_equipped_label.text = "장착: %s" % _inst_text(BackendService.get_equip_by_uid(_pool, eq_uid), stat_lbl)

	# 목록(등급 높은 순 → 레벨 높은 순)
	UISkin.clear_children(_list)
	_enh_rows.clear()  # 행 재생성 → 추적 중인 강화 버튼 참조 폐기(아래 _build_row에서 재등록)
	var equips: Array = BackendService.get_equips(_pool).duplicate()
	equips.sort_custom(_compare_inst)
	_empty.visible = equips.is_empty()
	_scroll.visible = not equips.is_empty()
	for inst in equips:
		_list.add_child(_build_row(inst as Dictionary, eq_uid, stat_lbl))

	# 합성 가능 여부
	_combine_btn.disabled = _combinable_grade() == ""


func refresh_affordability() -> void:
	# 실시간 골드 수입 시 강화 버튼 활성 여부만 제자리 갱신(리스트 재구성·스크롤 리셋 없이).
	# game._refresh_hud 가 처치(골드 변동)마다 호출. 패널 닫혀 있으면 game 쪽에서 skip.
	if not visible:
		return
	var gold: float = BackendService.get_gold()
	for r in _enh_rows:
		var btn: Button = r["btn"]
		if is_instance_valid(btn):
			btn.disabled = gold < float(r["cost"])


func _inst_text(inst: Dictionary, stat_lbl: String) -> String:
	if inst.is_empty():
		return "없음"
	var info: Dictionary = GachaScript.item_info(str(inst.get("item", "")))
	var grade: String = str(info.get("grade", ""))
	var lv: int = int(inst.get("level", 0))
	var stars: int = int(inst.get("stars", 0))  # 신화 돌파(별)
	var lv_txt: String = (" +%d" % lv) if lv > 0 else ""
	var star_txt: String = (" %d성" % stars) if stars > 0 else ""  # ★ 은 번들폰트에 없어 웹 깨짐 → "N성"
	var bonus: float = GachaScript.equip_bonus(grade, lv, stars)
	return "[%s] %s%s%s   %s +%d%%" % [UISkin.GRADE_NAME.get(grade, grade), info.get("name", "?"), lv_txt, star_txt, stat_lbl, int(round(bonus * 100.0))]  # 구분=공백(가운데점은 번들폰트에 없어 웹서 깨짐)


func _build_row(inst: Dictionary, eq_uid: String, stat_lbl: String) -> Control:
	var uid: String = str(inst.get("uid", ""))
	var info: Dictionary = GachaScript.item_info(str(inst.get("item", "")))
	var grade: String = str(info.get("grade", "common"))
	var lv: int = int(inst.get("level", 0))
	var stars: int = int(inst.get("stars", 0))  # 신화 돌파(별)
	var col: Color = UISkin.GRADE_COLOR.get(grade, Color(0.8, 0.8, 0.8))
	var bonus: float = GachaScript.equip_bonus(grade, lv, stars)
	var is_equipped: bool = uid == eq_uid

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.grade_row_style(col))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var lv_txt: String = (" +%d" % lv) if lv > 0 else ""
	var star_txt: String = (" %d성" % stars) if stars > 0 else ""  # ★ 대신 "N성"(웹 폰트)
	var info_lbl := Label.new()
	info_lbl.text = "%s%s%s   %s +%d%%" % [info.get("name", "?"), lv_txt, star_txt, stat_lbl, int(round(bonus * 100.0))]
	info_lbl.add_theme_font_size_override("font_size", 13)
	info_lbl.add_theme_color_override("font_color", col)
	info_lbl.clip_text = true
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(info_lbl)

	# 장착 버튼
	var eq_btn := Button.new()
	eq_btn.focus_mode = Control.FOCUS_NONE
	eq_btn.custom_minimum_size = Vector2(50, 30)
	eq_btn.add_theme_font_size_override("font_size", 12)
	eq_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	if is_equipped:
		eq_btn.text = "장착중"
		eq_btn.disabled = true
		UISkin.skin_button(eq_btn, "subtab", 4)
	else:
		eq_btn.text = "장착"
		UISkin.skin_button(eq_btn, "nav", 4)
		eq_btn.pressed.connect(func() -> void: _do_equip(uid))
	row.add_child(eq_btn)

	# 강화 버튼
	var enh_btn := UISkin.make_buy_button(Vector2(92, 30), 11, 4, true, true, Color(0.5, 0.5, 0.55))
	enh_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	enh_btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	enh_btn.add_theme_constant_override("icon_max_width", 15)
	if lv >= GachaScript.enhance_max():
		enh_btn.text = "MAX"
		enh_btn.icon = null
		enh_btn.disabled = true
	else:
		var c: int = GachaScript.enhance_cost(grade, lv)
		enh_btn.icon = GOLD_ICON
		enh_btn.text = "강화 %s" % UISkin.fmt_currency(c)
		enh_btn.disabled = BackendService.get_gold() < float(c)
		enh_btn.pressed.connect(func() -> void: _do_enhance(uid))
		_enh_rows.append({"btn": enh_btn, "cost": c})  # 실시간 골드 수입 시 활성 갱신용(refresh_affordability)
	row.add_child(enh_btn)

	return panel


func _do_equip(uid: String) -> void:
	Audio.play_sfx("button")
	BackendService.set_equipped(_pool, uid)
	Events.equipment_changed.emit()
	refresh()


func _do_enhance(uid: String) -> void:
	if BackendService.enhance_equip(_pool, uid):
		Audio.play_sfx("upgrade")
		Events.equipment_changed.emit()
		refresh()
	else:
		Audio.play_sfx("button")
		_toast("강화 불가 (골드 부족 또는 MAX)")


func _on_combine_pressed() -> void:
	# 전체 합성: 합성 가능한 모든 장비를 한 번에(저등급→고등급 cascade). 신화 결과는 돌파(별)로 흡수될 수 있음.
	if _combinable_grade() == "":
		Audio.play_sfx("button")
		_toast("합성할 장비가 부족합니다 (같은 등급 %d개 필요)" % GachaScript.combine_n())
		return
	var summary: Dictionary = BackendService.combine_all_equips(_pool)
	var n: int = int(summary.get("combines", 0))
	if n <= 0:
		Audio.play_sfx("button")
		_toast("합성 실패")
		return
	Audio.play_sfx("reward")
	Events.equipment_changed.emit()
	refresh()
	# 요약: 합성 횟수 + 생성된 등급별 개수
	var produced: Dictionary = summary.get("produced", {})
	var parts: Array = []
	for g in GachaScript.grade_ids():
		if produced.has(g):
			parts.append("%s %d" % [UISkin.GRADE_NAME.get(g, g), int(produced[g])])
	var made_txt: String = (" → " + ", ".join(parts)) if not parts.is_empty() else ""
	_toast("합성 %d회 완료%s" % [n, made_txt])


func _combinable_grade() -> String:
	# 합성 가능한 가장 낮은 등급(같은 종류 비장착 N개 이상). 없으면 "".
	var n: int = GachaScript.combine_n()
	for g in GachaScript.grade_ids():
		if GachaScript.next_grade(g) == "":
			continue  # 최상위(신화)는 합성 불가
		if BackendService.count_grade(_pool, g) >= n:
			return str(g)
	return ""


func _compare_inst(a: Variant, b: Variant) -> bool:
	# 등급 높은 순 → 레벨 높은 순. (grade_ids는 low→high라 index 큰 게 상위)
	var ga: String = str(GachaScript.item_info(str((a as Dictionary).get("item", ""))).get("grade", ""))
	var gb: String = str(GachaScript.item_info(str((b as Dictionary).get("item", ""))).get("grade", ""))
	var ia: int = GachaScript.grade_ids().find(ga)
	var ib: int = GachaScript.grade_ids().find(gb)
	if ia != ib:
		return ia > ib
	return int((a as Dictionary).get("level", 0)) > int((b as Dictionary).get("level", 0))
