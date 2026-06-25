extends "res://scripts/panel_overlay_base.gd"

# 상점 오버레이 — 레퍼런스 "소환" 화면(슬레이어 키우기). 코드 빌드(다른 패널과 일관).
# 구조: 카테고리 탭(소환/패키지/재화) + 서브탭(장비/유물) + 좌측 캐릭터·안내 + 우측 소환 리스트.
#   - 소환 > 장비 = 장비 뽑기(1회 / 11연차, 다이아 소모). 결과는 중앙 팝업으로.
#   - 소환 > 유물 = 유물 뽑기(1회 / 11연, 가루 소모 — 유물 패널에서 이전, 2026-06-10). 결과 팝업 공용.
#   - 나머지 카테고리(패키지·재화) = "준비 중" placeholder.
#   - 광고 소환 버튼 / 소환 레벨·진행바 = 시각 placeholder(동작은 보류 — 광고 SDK 없음, 마일리지 미설계).
# 풀 위치(상하 밴드)는 game.gd 가 offset_top/bottom 으로 지정. 여기선 좌우 가득만.
# 기획서: docs/design/UI 시스템 정리본.md, docs/design/BM 시스템 정리본.md
# closed 시그널은 베이스(panel_overlay_base.gd) 소유.

# 소환 재화/장비 변동 통지 = Events.currency_changed(전역 버스) — game.gd 가 구독해 HUD 갱신.

const GachaScript = preload("res://scripts/gacha.gd")  # class_name 직접참조 대신 preload(에디터 캐시 stale 회피)
const RelicsScript = preload("res://scripts/relics.gd")  # 유물 소환(가루 가챠) — 소환 > 유물 서브탭
# 좌측 캐릭터 일러스트 — 전용 경로(있으면 사용, 없으면 빈 프레임). 컷인(cutin.png) 재사용은 어색해서 미사용.
const SHOP_CHAR_PATH := "res://assets/shop/summon_char.png"

const DIA_COLOR := Color(0.45, 0.8, 1.0)  # 다이아 = 하늘색(게임 HUD 와 통일)
const DIA_ICON := preload("res://assets/ui/icon/icon_dia.png")  # 소환 비용 다이아 아이콘
const DUST_COLOR := Color(0.7, 0.95, 1.0)  # 유물 가루 = 옅은 하늘색(유물 패널 잔액 표기와 통일)

# 카테고리 탭(소환만 동작). / 서브탭(장비만 동작).
const CATEGORIES := [
	{"id": "summon", "name": "소환"},
	{"id": "package", "name": "패키지"},
	{"id": "currency", "name": "재화"},
]
const SUBTABS := [
	{"id": "equip", "name": "장비"},
	{"id": "relic", "name": "유물"},
]

# 희귀도 → 표시색 / 한글명 (소환 결과 카드) = UISkin.GRADE_COLOR / GRADE_NAME 공용 상수 사용.

# 탭 강조색 (다크 우드 패널 위). 활성색은 베이스 TAB_ACTIVE.
const CAT_IDLE := Color(0.90, 0.86, 0.76)
const SUB_IDLE := Color(0.72, 0.70, 0.66)

var _cat: String = "summon"   # 현재 카테고리
var _sub: String = "equip"    # 현재 서브탭

var _cat_buttons: Dictionary = {}   # id -> Button
var _sub_buttons: Dictionary = {}   # id -> Button
var _subtab_row: Control = null
var _summon_view: Control = null    # 소환 > 장비 (캐릭터 + 소환 리스트)
var _relic_view: Control = null     # 소환 > 유물 (가루 가챠 — 유물 패널에서 이전)
var _currency_view: Control = null  # 재화 (유물 가루 구매 — 다이아 결제)
var _currency_bal: Label = null     # 재화 탭 보유 다이아/가루 표시
var _dust_label: Label = null       # 유물 소환 행의 가루 잔액
var _relic_free_row: Control = null # 무료 확정 소환 행(남은 횟수 있을 때만 노출)
var _relic_free_info: Label = null  # 다음 무료 확정 소환이 줄 유물(사전 설정) 안내
var _stub: Label = null             # "준비 중" (그 외)
var _result_overlay: Control = null # 소환 결과 팝업(있으면)


func _ready() -> void:
	# 공통 스캐폴드(좌우 가득 + 다크 우드 bg + Margin + VBox) — 베이스 참조.
	var vbox := _build_scaffold()

	vbox.add_child(_build_category_row())
	vbox.add_child(_build_subtab_row())

	_summon_view = _build_summon_equip_view()
	_summon_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_summon_view)

	_relic_view = _build_summon_relic_view()
	_relic_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_relic_view)

	_currency_view = _build_currency_view()
	_currency_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_currency_view)

	_stub = UISkin.make_stub_label(Color(0.86, 0.82, 0.72))  # "준비 중입니다"
	vbox.add_child(_stub)

	_refresh_view()

	# 패널이 숨겨지면(닫기/계정전환 등) 떠 있던 결과 팝업도 함께 정리.
	visibility_changed.connect(_on_visibility_changed)
	# 외부 재화 변동(보스 처치 가루 등)도 열려 있으면 즉시 반영. (autoload→씬노드 연결은 free 시 자동 해제)
	Events.currency_changed.connect(_on_currency_changed)


func _on_visibility_changed() -> void:
	if not visible:
		_close_result()


func _on_currency_changed() -> void:
	# 보스 처치 등 외부 재화 변동 시, 열려 있으면 가루 잔액·재화 탭 잔액 즉시 갱신.
	if visible:
		_refresh_relic_costs()
		_refresh_currency()


# 외부(게임)에서 열 때: 잔여 결과 팝업 정리 + 최신화 + 표시.
func open() -> void:
	_close_result()
	_cat = "summon"
	_sub = "equip"
	_refresh_view()
	visible = true


# ---------- 탭 ----------

func _build_category_row() -> Control:
	# 카테고리 탭(소환/패키지/재화) + 닫기. 버튼 크기는 강화 패널과 동일(높이40·폰트16).
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for c in CATEGORIES:
		var id: String = String(c["id"])
		var b := make_tab_button(String(c["name"]), func() -> void: _select_category(id), "nav")
		hb.add_child(b)
		_cat_buttons[id] = b

	hb.add_child(make_close_button(_on_close_pressed))
	return hb


func _build_subtab_row() -> Control:
	# 서브탭(장비/유물) + 보유 다이아(오른쪽).
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for t in SUBTABS:
		var id: String = String(t["id"])
		# 고정폭 70·expand/clip 미설정(원형 보존 — make_tab_button 의 skip 시멘틱).
		var b := make_tab_button(String(t["name"]), func() -> void: _select_sub(id), "subtab", Vector2(70, 40), false, false)
		hb.add_child(b)
		_sub_buttons[id] = b

	# 보유 다이아는 상단 HUD에 상시 표시되므로 패널 안에는 중복 표기하지 않음(레퍼런스도 동일).
	_subtab_row = hb
	return hb


func _select_category(cat: String) -> void:
	Audio.play_sfx("button")
	_cat = cat
	_refresh_view()


func _select_sub(sub: String) -> void:
	# 유물 서브탭은 스테이지 10 클리어 전 잠금(음영). 진입 시도 시 안내 토스트(전역, nav 탭과 통일) 후 장비 서브탭 유지.
	if sub == "relic" and not BackendService.relic_unlocked():
		Audio.play_sfx("button")
		NotificationManager.info("스테이지 10을 클리어하면 열립니다")
		return
	Audio.play_sfx("button")
	_sub = sub
	_refresh_view()


func _refresh_view() -> void:
	var is_summon: bool = _cat == "summon"
	var show_equip: bool = is_summon and _sub == "equip"
	var show_relic: bool = is_summon and _sub == "relic"
	var show_currency: bool = _cat == "currency"
	# 소환일 때만 서브탭 노출. 장비=장비 소환 / 유물=가루 가챠 / 재화=가루 구매 / 패키지=준비 중.
	_subtab_row.visible = is_summon
	_summon_view.visible = show_equip
	_relic_view.visible = show_relic
	_currency_view.visible = show_currency
	_stub.visible = not (show_equip or show_relic or show_currency)
	if show_relic:
		_refresh_relic_costs()
	if show_currency:
		_refresh_currency()

	set_tab_highlight(_cat_buttons, _cat, CAT_IDLE, 0.82)
	set_tab_highlight(_sub_buttons, _sub, SUB_IDLE, 0.82)
	# 유물 서브탭 잠금 음영(첫 보스 처치 전). highlight 와 별개 속성(modulate)이라 덮이지 않음.
	var relic_btn: Button = _sub_buttons.get("relic", null)
	if relic_btn != null:
		relic_btn.modulate = Color(1, 1, 1, 1) if BackendService.relic_unlocked() else Color(0.5, 0.5, 0.52, 0.6)


# ---------- 소환 뷰 (장비 / 유물 공용 레이아웃) ----------

func _build_summon_layout(info_text: String) -> Dictionary:
	# 좌측 캐릭터 영역(고정) + 우측 소환 리스트(세로 스크롤) 공용 골격. {"root": HBox, "list": VBox} 반환.
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)

	# 좌측: 캐릭터(프레임) + 안내 — 고정. 프레임이 패널(밴드) 높이를 채우고, 행 수가 늘어도 안 움직임.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(96, 0)
	left.add_theme_constant_override("separation", 6)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL  # 좌측 칼럼(=밴드) 높이에 맞춰 채움
	frame.add_theme_stylebox_override("panel", UISkin.icon_slot())
	var char_rect := TextureRect.new()
	char_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	char_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(SHOP_CHAR_PATH):
		char_rect.texture = load(SHOP_CHAR_PATH)  # 파일 없으면 빈 프레임(placeholder)
	frame.add_child(char_rect)
	left.add_child(frame)

	var info := Label.new()
	info.text = info_text
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(info)

	hb.add_child(left)

	# 우측: 소환 리스트만 세로 스크롤(행이 늘어도 좌측 고정).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	hb.add_child(scroll)

	return {"root": hb, "list": list}


func _build_summon_equip_view() -> Control:
	# 소환 > 장비: 데이터(pools)의 풀마다 1행 — 풀 추가 시 행이 자동으로 늘어 스크롤됨.
	var layout := _build_summon_layout("장비를 소환해\n캐릭터를 강화하세요!")
	for pid in GachaScript.pool_ids():
		(layout["list"] as VBoxContainer).add_child(_build_summon_row(str(pid)))
	return layout["root"]


func _build_summon_relic_view() -> Control:
	# 소환 > 유물: 가루(dust) 가챠 — 유물 패널에서 이전(2026-06-10). 인벤토리/장착은 유물 탭에 잔류.
	var layout := _build_summon_layout("유물을 소환해\n족보를 커스텀하세요!")
	(layout["list"] as VBoxContainer).add_child(_build_relic_summon_row())
	return layout["root"]


func _build_relic_summon_row() -> Control:
	# 유물 소환 1행: [제목 (효과)] / [가루 잔액] / [1회][11연]. (광고·소환레벨 placeholder는 장비 전용 — BM 미설계)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.inset_row_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title_row := _make_title_eff_row("유물 소환", "(족보 커스텀)")
	_dust_label = Label.new()
	_dust_label.add_theme_font_size_override("font_size", 12)
	_dust_label.add_theme_color_override("font_color", DUST_COLOR)
	_dust_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(_dust_label)
	vb.add_child(title_row)

	# 무료 확정 소환(초반 부트스트랩) — 남은 횟수 있을 때만 노출(_refresh_relic_costs 에서 토글).
	_relic_free_row = _build_relic_free_pull_row()
	vb.add_child(_relic_free_row)

	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 8)
	opt_row.add_child(_build_relic_pull_option("1회 소환", 1))
	opt_row.add_child(_build_relic_pull_option("11연 소환", 11))
	vb.add_child(opt_row)

	return panel


func _build_relic_free_pull_row() -> Control:
	# 무료 확정 소환 버튼 + 안내(보장 등급, 무료). 초반 부트스트랩 — 남은 횟수 0이면 숨김.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var b := UISkin.make_buy_button(Vector2(0, 44), 14, 4, true, true, Color(0, 0, 0, 0), true)
	b.text = "무료 확정 소환"
	b.pressed.connect(_do_free_relic_pull)
	col.add_child(b)
	_relic_free_info = Label.new()  # 다음 지급 유물 안내(사전 설정) — _refresh_relic_costs 에서 갱신
	_relic_free_info.add_theme_font_size_override("font_size", 12)
	_relic_free_info.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_relic_free_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_relic_free_info)
	return col


func _build_relic_pull_option(label: String, count: int) -> Control:
	# 유물 1회/11연 1개: [버튼] + [가루 비용](아이콘 에셋 없음 → 텍스트, 가루색).
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var b := UISkin.make_buy_button(Vector2(0, 44), 14, 4, true, true, Color(0, 0, 0, 0), true)
	b.text = label
	b.pressed.connect(func() -> void: _do_relic_pull(count))
	col.add_child(b)

	var cost_lbl := Label.new()
	var cost: int = RelicsScript.gacha_cost() if count == 1 else RelicsScript.gacha_cost_11()
	cost_lbl.text = "가루 %d" % cost
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", DUST_COLOR)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cost_lbl)

	return col


func _refresh_relic_costs() -> void:
	# 유물 서브탭 표시/뽑기 후 가루 잔액 + 무료 확정 소환 노출 갱신.
	if _dust_label != null:
		_dust_label.text = "보유 가루 %s" % UISkin.fmt_currency(BackendService.get_dust())
	if _relic_free_row != null:
		var left: int = BackendService.relic_free_pulls_left()
		_relic_free_row.visible = left > 0
		if left > 0 and _relic_free_info != null:
			var g: Dictionary = BackendService.next_free_relic_grant()
			var gr: String = str(g.get("grade", ""))
			_relic_free_info.text = "무료 [%s] %s 확정" % [UISkin.GRADE_NAME.get(gr, gr), g.get("name", "?")]


func _do_free_relic_pull() -> void:
	# 무료 확정 소환: 보장 등급 유물 1개(효과 랜덤) 무료 획득 → 결과 팝업.
	Audio.play_sfx("button")
	var res: Dictionary = BackendService.do_free_relic_pull()
	if res.is_empty():
		_shop_toast("무료 확정 소환을 모두 사용했습니다")
		_refresh_relic_costs()
		return
	Audio.play_sfx("reward")
	Events.relics_changed.emit()  # 분포·HUD 재적용
	_refresh_relic_costs()        # 남은 횟수 0 되면 버튼 숨김
	_show_gacha_result([res])


# ---------- 재화 (유물 가루 구매, 다이아 결제) ----------

func _build_currency_view() -> Control:
	# 상점 > 재화: 유물 가루를 다이아로 구매(일단 다이아 — placeholder). 보유 표시 + 구매 팩 리스트.
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	_currency_bal = Label.new()
	_currency_bal.add_theme_font_size_override("font_size", 13)
	_currency_bal.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	_currency_bal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_currency_bal)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(RelicsScript.dust_shop_count()):
		list.add_child(_build_dust_pack_row(i))
	scroll.add_child(list)
	vb.add_child(scroll)
	return vb


func _build_dust_pack_row(index: int) -> Control:
	# 가루 구매 1행: [유물 가루 +N] ... [다이아 아이콘 비용] [구매].
	var pack: Dictionary = RelicsScript.dust_shop_pack(index)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.inset_row_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = "유물 가루 +%d" % int(pack.get("amount", 0))
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", DUST_COLOR)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	var gem := _make_dia_cost_icon()
	row.add_child(gem)
	var cost_lbl := Label.new()
	cost_lbl.text = str(int(pack.get("cost", 0)))
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", DIA_COLOR)
	cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cost_lbl)

	var b := UISkin.make_buy_button(Vector2(64, 40), 13, 4, true, true, Color(0, 0, 0, 0), true)
	b.text = "구매"
	b.pressed.connect(func() -> void: _buy_dust(index))
	row.add_child(b)
	return panel


func _make_dia_cost_icon() -> TextureRect:
	# 다이아 비용 아이콘(소환/가루팩 행 공용 — 동일 스펙 속성 중복 제거).
	var gem := TextureRect.new()
	gem.texture = DIA_ICON
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	gem.custom_minimum_size = Vector2(15, 15)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return gem


func _shop_toast(text: String) -> void:
	# 상점 패널 토스트 — 베이스 _toast 의 상점 고유값(34.0, 15, Color(1.0,0.85,0.5), 1.0) 단일화.
	# ⚠️ 가루 획득 토스트(_buy_dust, 443)는 DUST_COLOR라 _shop_toast 미사용(별도 _toast).
	_toast(text, 34.0, 15, Color(1.0, 0.85, 0.5), 1.0)


func _refresh_currency() -> void:
	# 재화 탭 보유 표시(다이아·가루) 갱신.
	if _currency_bal != null:
		_currency_bal.text = "보유   다이아 %s   가루 %s" % [UISkin.fmt_currency(BackendService.get_dia()), UISkin.fmt_currency(BackendService.get_dust())]


func _buy_dust(index: int) -> void:
	# 유물 가루 구매(다이아 결제). 부족하면 토스트, 성공하면 가루 지급 + 잔액 갱신.
	Audio.play_sfx("button")
	var pack: Dictionary = RelicsScript.dust_shop_pack(index)
	var cost: int = int(pack.get("cost", 0))
	var amount: int = int(pack.get("amount", 0))
	if BackendService.get_dia() < float(cost):
		_shop_toast("다이아가 부족합니다 (필요 %d)" % cost)
		return
	if not BackendService.buy_dust_with_dia(float(amount), float(cost)):
		_shop_toast("구매 실패")
		return
	Audio.play_sfx("reward")
	Events.currency_changed.emit()  # HUD 다이아 + 다른 패널 가루 갱신
	_refresh_currency()
	_toast("유물 가루 +%d 획득!" % amount, 34.0, 15, DUST_COLOR, 1.0)


func _make_title_eff_row(title_text: String, eff_text: String) -> HBoxContainer:
	# 소환 행 제목+효과 라벨 쌍(장비/유물 소환 공용). 트레일링 위젯(가루 라벨/광고 버튼)은 호출부가 append.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.90, 0.82))
	title_row.add_child(title)
	var eff := Label.new()
	eff.text = eff_text
	eff.add_theme_font_size_override("font_size", 12)
	eff.add_theme_color_override("font_color", Color(0.66, 0.85, 0.62))
	eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eff.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(eff)
	return title_row


func _build_summon_row(pool_id: String) -> Control:
	# 소환 종류 1행: [제목 (효과) | 광고] / [1회 소환][11회 소환] / [소환 레벨 + 진행바].
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.inset_row_style())  # 다크 우드 위 인셋(행 구분)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	# 제목 행
	var eff_txt: String = GachaScript.pool_effect(pool_id)
	var title_row := _make_title_eff_row(GachaScript.pool_name(pool_id), ("(%s)" % eff_txt) if eff_txt != "" else "")
	# 광고 소환(placeholder, 비활성 — 광고 SDK 도입 후 활성화). white=false(흰 font_color 미설정, 원형 보존).
	var ad := UISkin.make_buy_button(Vector2(52, 30), 12, 4, true, false, Color(0.6, 0.6, 0.62))
	ad.text = "광고"
	ad.disabled = true
	ad.tooltip_text = "광고 소환 준비 중"
	title_row.add_child(ad)
	vb.add_child(title_row)

	# 소환 버튼 행 (1회 / 11연차)
	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 8)
	opt_row.add_child(_build_pull_option("1회 소환", GachaScript.cost(pool_id), pool_id, 1))
	opt_row.add_child(_build_pull_option("11회 소환", GachaScript.cost_11(pool_id), pool_id, 11))
	vb.add_child(opt_row)

	# 소환 레벨 + 진행바 (placeholder — 마일리지 미설계)
	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 8)
	var lvl := Label.new()
	lvl.text = "소환 레벨 1"
	lvl.add_theme_font_size_override("font_size", 12)
	lvl.add_theme_color_override("font_color", Color(0.80, 0.78, 0.70))
	lvl_row.add_child(lvl)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_placeholder_bar(bar)
	lvl_row.add_child(bar)
	vb.add_child(lvl_row)

	return panel


func _build_pull_option(label: String, cost: int, pool_id: String, count: int) -> Control:
	# 1회/11회 소환 1개: [버튼] + [다이아 placeholder 아이콘 + 비용].
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var b := UISkin.make_buy_button(Vector2(0, 44), 14, 4, true, true, Color(0, 0, 0, 0), true)
	b.text = label
	b.pressed.connect(func() -> void: _do_pull(pool_id, count))
	col.add_child(b)

	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 3)
	var gem := _make_dia_cost_icon()
	cost_row.add_child(gem)
	var cost_lbl := Label.new()
	cost_lbl.text = str(cost)
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", DIA_COLOR)
	cost_row.add_child(cost_lbl)
	col.add_child(cost_row)

	return col


func _style_placeholder_bar(bar: ProgressBar) -> void:
	# 단순 진행바 스타일(어두운 트랙 + 초록 채움). 소환 레벨 마일리지 placeholder.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.14)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.78, 0.50)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


# ---------- 뽑기 실행 ----------

func _do_pull(pool_id: String, count: int) -> void:
	Audio.play_sfx("button")
	var c: int = GachaScript.cost(pool_id) if count == 1 else GachaScript.cost_11(pool_id)
	if BackendService.get_dia() < float(c):
		_shop_toast("다이아가 부족합니다 (필요 %d)" % c)
		return
	BackendService.spend_dia(float(c))
	var results: Array = GachaScript.roll_many(pool_id, count)
	if results.is_empty():
		BackendService.add_dia(float(c))  # 롤 실패 → 환불
		_shop_toast("소환 풀이 비어 있습니다")
		return
	for r in results:
		BackendService.add_equip(pool_id, str((r as Dictionary).get("item", "")))
	BackendService.add_stat("equipment_pulls", count)  # 장비 소환 통계(메인 퀘 main_equip_pull)
	BackendService.add_stat("summon_pulls", count)  # 통합 소환 통계(daily_summon — 장비+유물 공통, Codex #15 P2)
	BackendService.flush()  # 소환 = 이산 이벤트 → 즉시 저장
	Audio.play_sfx("reward")
	Events.currency_changed.emit()  # 전역 버스 → game HUD 갱신(다이아/장비)
	_show_gacha_result(results)


func _do_relic_pull(count: int) -> void:
	# 유물 소환(가루) — 유물 패널에서 이전(2026-06-10). 획득은 acquire_relic(같은 효과 최고 등급 1개,
	# 중복/하위 = 자동 가루 환급) → 결과 팝업이 신규/업그레이드/중복을 구분 표시.
	Audio.play_sfx("button")
	var c: int = RelicsScript.gacha_cost() if count == 1 else RelicsScript.gacha_cost_11()
	if int(BackendService.get_dust()) < c:
		_shop_toast("유물 가루가 부족합니다 (필요 %d)" % c)
		return
	BackendService.spend_dust(float(c))
	var rolled: Array = RelicsScript.roll_many(count)
	if rolled.is_empty():
		BackendService.add_dust(float(c))  # 풀 비면 환불
		_shop_toast("유물 풀이 비어 있습니다")
		return
	var outcomes: Array = []
	for r in rolled:
		var rd := r as Dictionary
		var res: Dictionary = BackendService.acquire_relic(str(rd.get("effect", "")), str(rd.get("grade", "")))
		res["name"] = rd.get("name", "?")  # 결과 카드 표기용(acquire 반환엔 name 없음)
		outcomes.append(res)
	BackendService.add_stat("relic_pulls", count)  # 유물 소환 통계(메인 퀘 main_relic_pull)
	BackendService.add_stat("summon_pulls", count)  # 통합 소환 통계(daily_summon — 장비+유물 공통, Codex #15 P2)
	BackendService.flush()
	Audio.play_sfx("reward")
	Events.relics_changed.emit()  # 전역 버스 → game 이 분포·와일드 재적용 + HUD
	_refresh_relic_costs()
	_show_gacha_result(outcomes)


# 패널 상단 토스트(다이아 부족 등) = 베이스 _toast — 상점 고유값(34.0, 15, Color(1.0,0.85,0.5), 1.0)을 호출부에서 명시.


# ---------- 소환 결과 팝업 ----------

func _show_gacha_result(results: Array) -> void:
	_close_result()
	# 결과 팝업 = 전체 화면 모달. 상점 패널은 하단 밴드라, 부모(게임 루트)에 올려 화면 전체를 덮는다.
	var overlay := Control.new()
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var host: Node = get_parent()
	if host == null:
		host = self
	host.add_child(overlay)
	_result_overlay = overlay

	# 딤 배경(탭하면 닫힘)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_result_dim_input)
	overlay.add_child(dim)

	# 중앙 카드 — 폭은 스크롤바 예약분까지 수용(320). 혹시 콘텐츠 최소폭이 더 커져도
	# grow BOTH 라 좌우 대칭으로 자라 중앙 유지(기본 END면 오른쪽으로만 자라 중앙이 깨짐 — 11연차 버그).
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UISkin.panel())
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -160.0
	card.offset_right = 160.0
	card.offset_top = -150.0
	card.offset_bottom = 150.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	m.add_child(vb)

	var title := Label.new()
	title.text = "소환 결과"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 세로 스크롤바 자리 상시 예약 — 바가 나타나도(11연차) 최소 폭이 안 변해 카드 크기/중앙 유지.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 3 if results.size() > 1 else 1
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for r in results:
		grid.add_child(_build_result_chip(r as Dictionary))
	scroll.add_child(grid)
	vb.add_child(scroll)

	var ok := UISkin.make_buy_button(Vector2(0, 40), 15, 6, true, true, Color(0, 0, 0, 0))  # content=6(다른 buy 와 다름)
	ok.text = "확인"
	ok.pressed.connect(_close_result)
	vb.add_child(ok)


func _on_result_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		_close_result()
	elif e is InputEventScreenTouch and e.pressed:
		_close_result()


func _close_result() -> void:
	if _result_overlay != null:
		_result_overlay.queue_free()
		_result_overlay = null


func _build_result_chip(r: Dictionary) -> Control:
	# 장비: {grade, name} / 유물: {grade, name, outcome(new/upgrade/dust), dust} — outcome 따라 표기 차등.
	var rarity: String = str(r.get("grade", "common"))
	var outcome: String = str(r.get("outcome", ""))
	var is_dust: bool = outcome == "dust"  # 중복/하위 → 자동 가루 환급(회색 카드)
	var col: Color = Color(0.7, 0.72, 0.75) if is_dust else UISkin.GRADE_COLOR.get(rarity, Color(0.8, 0.8, 0.8))
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(82, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.20)
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(2)
	sb.border_color = col
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	chip.add_child(vb)
	var rl := Label.new()
	if is_dust:
		rl.text = "중복"
	elif outcome == "upgrade":
		rl.text = "%s ↑" % UISkin.GRADE_NAME.get(rarity, rarity)  # 보유 유물 등급 상승
	else:
		rl.text = str(UISkin.GRADE_NAME.get(rarity, rarity))
	rl.add_theme_font_size_override("font_size", 11)
	rl.add_theme_color_override("font_color", col)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(rl)
	var nl := Label.new()
	nl.text = ("가루 +%d" % int(r.get("dust", 0))) if is_dust else str(r.get("name", "?"))
	nl.add_theme_font_size_override("font_size", 12)
	nl.add_theme_color_override("font_color", Color(0.96, 0.93, 0.85))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(nl)
	return chip
