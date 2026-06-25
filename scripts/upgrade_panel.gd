extends "res://scripts/panel_overlay_base.gd"

# 강화(업그레이드) 오버레이 — 레퍼런스 "키우기"식 하단 시트.
# 구조: 하단 ~60% 덮는 시트(전투는 위에 계속 보임) + 서브탭(강화/성장/승급) + 스크롤 행 리스트.
# 각 행: [아이콘] 이름 / Lv·현재값→다음값 / [비용 버튼 or MAX]. 골드를 써서 레벨업.
# 강화 외 서브탭(성장/승급)은 아직 미구현 → "준비 중" 안내. 기획서: docs/design/강화 시스템 정리본.md

# 구매 성공 통지 = Events.upgrade_purchased(전역 버스) — game.gd 가 구독해 스탯 즉시 반영.
# closed 시그널(닫기 버튼)은 베이스(panel_overlay_base.gd)에서 상속.

# 값→다음값 화살표. 번들 폰트(한글 전용)가 유니코드 화살표를 못 그리면 "->" 로 교체.
const ARROW := "→"
const GOLD_ICON := preload("res://assets/ui/icon/icon_gold.png")  # 강화 비용 골드 아이콘

# 트랙 종류별 아이콘(placeholder 색칠 사각형) 색. char=캐릭터/card=복권/util=저장소.
const KIND_COLOR := {
	"char": Color(0.85, 0.4, 0.4),
	"card": Color(0.4, 0.58, 0.92),
	"util": Color(0.45, 0.78, 0.5),
}

# 값 표기를 소수 2자리로 하는 트랙(배율·초당 속도). 나머지는 정수 축약.
const DECIMAL_TRACKS := ["card_mult", "auto_speed"]

# 서브탭 비활성 글자색 — 흐린 회갈색(베이지 버튼 위). 활성색은 베이스 TAB_ACTIVE(진한 호박).
const SUBTAB_IDLE := Color(0.72, 0.7, 0.66)

# 롱프레스 연타: 버튼을 RAPID_DELAY초 이상 누르면 RAPID_INTERVAL 간격으로 연속 구매.
const RAPID_DELAY: float = 1.0
const RAPID_INTERVAL: float = 0.06
var _held_id: String = ""
var _hold_time: float = 0.0
var _rapid_accum: float = 0.0

# 드래그/스와이프 스크롤 (ScrollContainer는 마우스 드래그로 스크롤 안 됨 → 직접 처리, 터치도 동일).
const DRAG_THRESHOLD: float = 8.0  # 이만큼 세로로 움직이면 스크롤로 간주(작은 움직임은 탭 유지)
var _touching: bool = false
var _dragging: bool = false
var _drag_start_y: float = 0.0
var _drag_last_y: float = 0.0

var _gold_label: Label = null
var _rows: Dictionary = {}        # id -> { name, sub, buy, icon }
var _rows_scroll: ScrollContainer = null
var _stub: Label = null           # 성장/승급 "준비 중" 안내
var _subtabs: Dictionary = {}     # key -> Button
var _active_tab: String = "upgrade"


func _ready() -> void:
	# 공통 스캐폴드(앵커 fill + 배경 + 마진 + VBox)는 베이스가 생성.
	# 위치(상하 밴드)는 game.gd가 지정 — 전투/내비는 안 가리고 스크래치 영역만 덮음.
	var vbox := _build_scaffold()

	vbox.add_child(_build_header())

	# 보유 골드 (상단 HUD에도 있지만, 강화 중 비교 편의로 패널 안에도 표시). 베이지 위라 진한 호박색.
	# 보유 골드: [금화 아이콘] + 숫자 (HUD와 동일 스타일)
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 5)
	var gold_ic := TextureRect.new()
	gold_ic.texture = GOLD_ICON
	gold_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	gold_ic.custom_minimum_size = Vector2(22, 22)
	gold_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(gold_ic)
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_row.add_child(_gold_label)
	vbox.add_child(gold_row)

	# 강화 트랙 행 스크롤 (h flag 미설정 원형 보존 → h_expand=false)
	_rows_scroll = UISkin.make_vlist_scroll(false)
	vbox.add_child(_rows_scroll)
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 6)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.add_child(rows_box)
	for id in Upgrades.all_ids():
		rows_box.add_child(_build_row(id))

	# 성장/승급 미구현 안내 (강화 탭이 아닐 때 표시)
	_stub = UISkin.make_stub_label(Color(0.75, 0.73, 0.7))
	vbox.add_child(_stub)

	_select_tab("upgrade")


func _build_header() -> Control:
	# 서브탭(강화/성장/승급) + 닫기 버튼.
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)

	for t in [{"id": "upgrade", "name": "강화"}, {"id": "growth", "name": "성장"}, {"id": "promote", "name": "승급"}]:
		var id: String = String(t["id"])
		var b := make_tab_button(String(t["name"]), func() -> void: _select_tab(id))
		hb.add_child(b)
		_subtabs[id] = b

	# 닫기: 레드 스킨 버튼. (기존대로 sfx 없이 closed만 emit — 베이스 _on_close_pressed 미사용)
	var close_btn := make_close_button(func() -> void: closed.emit())
	hb.add_child(close_btn)
	return hb


func open() -> void:
	# UIManager.open() 통일 인터페이스 — 최신값 갱신 후 표시.
	refresh()
	visible = true


func _select_tab(tab: String) -> void:
	_active_tab = tab
	var is_upgrade: bool = tab == "upgrade"
	_gold_label.visible = is_upgrade
	_rows_scroll.visible = is_upgrade
	_stub.visible = not is_upgrade
	# 활성 탭 강조 — 베이지 버튼 위, 활성=진한 호박(베이스 TAB_ACTIVE)·비활성=흐린 회갈색.
	set_tab_highlight(_subtabs, tab, SUBTAB_IDLE, 0.85)
	if is_upgrade:
		refresh()


func _build_row(id: String) -> Control:
	# 트랙 1행(카드 느낌): [아이콘] [이름 / Lv·값→다음] [비용 버튼].
	var d: Dictionary = Upgrades.def(id)
	var panel := PanelContainer.new()
	# 다크 우드 패널 위 인셋(살짝 더 어둡게 — 행 구분)
	panel.add_theme_stylebox_override("panel", UISkin.inset_row_style())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(row)

	# 아이콘 슬롯 = #13 프레임 배경 + 안에 종류색 placeholder(추후 실제 아이콘으로 교체)
	var icon_slot := PanelContainer.new()
	icon_slot.custom_minimum_size = Vector2(44, 44)
	icon_slot.add_theme_stylebox_override("panel", UISkin.icon_slot())
	var icon := ColorRect.new()
	icon.color = KIND_COLOR.get(String(d.get("kind", "")), Color(0.5, 0.5, 0.5))
	icon_slot.add_child(icon)
	row.add_child(icon_slot)

	# 이름 + Lv/값→다음 (2줄). clip_text=true → 라벨이 행 최소폭을 키워 오른쪽으로 넘치는 것 방지.
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(0, 0)
	var name_lbl := Label.new()
	name_lbl.text = String(d.get("name", id))
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.82))  # 다크 우드 위 밝은 크림
	name_lbl.clip_text = true
	info.add_child(name_lbl)
	var sub_lbl := Label.new()
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))  # 값→다음(밝은 초록)
	sub_lbl.clip_text = true
	info.add_child(sub_lbl)
	row.add_child(info)

	# 비용 버튼 (탭/롱프레스). 블루 스킨 + 흰 글자. 폭 고정으로 행이 패널 안에 들어오게.
	var buy := UISkin.make_buy_button(Vector2(88, 44), 14, 4, true, true, Color(0.45, 0.45, 0.5))
	buy.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	buy.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	buy.add_theme_constant_override("icon_max_width", 18)
	buy.button_down.connect(_on_buy_down.bind(id))
	buy.button_up.connect(_on_buy_up)
	row.add_child(buy)

	_rows[id] = { "name": name_lbl, "sub": sub_lbl, "buy": buy, "icon": icon, "track_name": String(d.get("name", id)) }
	return panel


func _on_buy_down(id: String) -> void:
	_do_buy(id)        # 누르는 즉시 1회 (탭 반응성)
	_held_id = id
	_hold_time = 0.0
	_rapid_accum = 0.0


func _on_buy_up() -> void:
	_held_id = ""
	# 구매 묶음이 끝나는 시점에 1회만 영속화 (연타마다 flush하면 클라우드 폭주 → 금지)
	BackendService.flush()


func _process(delta: float) -> void:
	# 버튼을 누른 채 RAPID_DELAY 경과하면 RAPID_INTERVAL 간격으로 연타 구매(다라라락).
	if _held_id == "":
		return
	_hold_time += delta
	if _hold_time < RAPID_DELAY:
		return
	_rapid_accum += delta
	while _rapid_accum >= RAPID_INTERVAL:
		_rapid_accum -= RAPID_INTERVAL
		if not _do_buy(_held_id):
			break  # 골드 부족/MAX면 중단


func _input(event: InputEvent) -> void:
	# 강화 리스트 드래그/스와이프 스크롤. (구매 버튼은 그대로 — 빈 영역을 끌면 스크롤)
	if not visible or _rows_scroll == null or not _rows_scroll.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_begin(event.position)
		else:
			_drag_end()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_drag_begin(event.position)
		else:
			_drag_end()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag_move(event.position)
	elif event is InputEventScreenDrag:
		_drag_move(event.position)


func _drag_begin(pos: Vector2) -> void:
	if not _rows_scroll.get_global_rect().has_point(pos):
		_touching = false
		return
	# 스크롤바(VScrollBar) 핸들 위에서 시작한 드래그는 커스텀(natural: 콘텐츠 잡고 밀기)을 쓰지 않고
	# VScrollBar 기본 동작(traditional: 아래로 끌면 아래로)에 맡긴다 — 둘이 겹치면 반대로 움직이는 버그.
	var vbar: VScrollBar = _rows_scroll.get_v_scroll_bar()
	if vbar != null and vbar.visible and vbar.get_global_rect().has_point(pos):
		_touching = false
		return
	_touching = true
	_dragging = false
	_drag_start_y = pos.y
	_drag_last_y = pos.y


func _drag_move(pos: Vector2) -> void:
	if not _touching:
		return
	var dy: float = pos.y - _drag_last_y
	_drag_last_y = pos.y
	if not _dragging and absf(pos.y - _drag_start_y) > DRAG_THRESHOLD:
		_dragging = true
		_held_id = ""  # 드래그로 판정 → 진행 중인 연타 구매는 취소(스크롤 우선)
	if _dragging:
		_rows_scroll.scroll_vertical -= int(dy)
		# 이벤트 소비 → 터치 기기에서 ScrollContainer 네이티브 스크롤과 이중 적용되는 것 방지
		get_viewport().set_input_as_handled()


func _drag_end() -> void:
	_touching = false
	_dragging = false
	# 손을 떼면 연타 구매 무조건 종료. button_up에만 의존하면, 골드 부족으로 버튼이
	# disabled 된 채 release 될 때 button_up이 안 나와 _held_id가 남고 → 방치 수입이
	# 차는 족족 "지멋대로" 자동 구매되는 버그가 생긴다. _input release는 항상 들어오므로 여기서 정리.
	if _held_id != "":
		_held_id = ""
		BackendService.flush()


func _do_buy(id: String) -> bool:
	# 1회 구매 시도(탭/연타 공용). 성공 시 시그널 + 행 갱신. 실패(골드부족/MAX) 시 false.
	if Upgrades.buy(id):
		Audio.play_sfx("upgrade")
		BackendService.add_stat("upgrades_bought", 1)  # 강화 구매 통계(퀘스트 "강화 N회" — 전체 합산)
		BackendService.add_stat("upgrades_bought_" + id, 1)  # 트랙별 통계(퀘스트 "공격력/체력/체력재생 강화 N회" 등 — stat = upgrades_bought_<track>)
		Events.upgrade_purchased.emit()
		refresh()
		return true
	return false


func refresh() -> void:
	# 보유 골드 + 모든 트랙 행(레벨/현재값→다음값/비용, 구매가능 여부에 따른 버튼 활성)을 최신화.
	if _active_tab != "upgrade":
		return
	if _gold_label != null:
		_gold_label.text = UISkin.fmt_currency(BackendService.get_gold())
	for id in _rows:
		var lv: int = Upgrades.get_level(id)
		var name_lbl: Label = _rows[id]["name"]
		var sub_lbl: Label = _rows[id]["sub"]
		var buy: Button = _rows[id]["buy"]
		var ml: int = Upgrades.max_level(id)
		var max_txt: String = "Max Lv.%d" % ml if ml >= 0 else ""
		name_lbl.text = "%s   Lv.%d   %s" % [_rows[id]["track_name"], lv, max_txt]
		if Upgrades.is_maxed(id):
			sub_lbl.text = _fmt_val_at(id, lv)
			buy.text = "MAX"
			buy.icon = null
			buy.disabled = true
		else:
			sub_lbl.text = "%s %s %s" % [_fmt_val_at(id, lv), ARROW, _fmt_val_at(id, lv + 1)]
			buy.icon = GOLD_ICON
			buy.text = UISkin.fmt_currency(Upgrades.cost(id))
			buy.disabled = not Upgrades.can_afford(id)


func _fmt_val_at(id: String, level: int) -> String:
	# 특정 레벨에서의 트랙 값(value = base_val + per_level*level).
	var d: Dictionary = Upgrades.def(id)
	var v: float = float(d.get("base_val", 0.0)) + float(d.get("per_level", 0.0)) * level
	if id in DECIMAL_TRACKS:
		return "%.2f" % v  # 소수 트랙(배율·초당 속도)은 소수 2자리
	return UISkin.fmt_currency(v)  # 큰 수 축약 표기(1.2K/3.4M/5.6B)는 공용 헬퍼로
