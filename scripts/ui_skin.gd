class_name UISkin
extends RefCounted

# UI 스킨 헬퍼 — 사용자 자체 UI 시트(단일 PNG에 여러 조각) 기반.
# 시트의 각 조각을 AtlasTexture(region)로 잘라 9-slice StyleBoxTexture로 사용한다.
# 역할→region/margin 만 바꾸면 전체 UI 룩이 바뀐다. 코드빌드 UI(nav_dock·upgrade_panel·스테이지 배너) 공유.
# region 좌표는 tools/scan_sheet.gd 로 추출한 불투명 바운딩 박스 기반(1차값, 인게임 보정).
# 룩: 다크 우드/판타지 → 패널 위 텍스트는 밝게.

const SHEET := "res://assets/ui/UI_sheet.png"
const ICON_CLOSE := "res://assets/ui/icon/icon_close.png"  # 닫기 버튼 아이콘(흰색 X)
const CLOSE_ICON_COLOR := Color(0.95, 0.90, 0.82)  # 닫기 아이콘 틴트 — 패널 텍스트(크림)와 통일. 흰색 아이콘을 modulate로 색입힘

# 역할 → 시트 조각. 좌표 단일 출처 = scripts/sheet_rects.gd (RECTS 인덱스 = scan_sheet 컴포넌트 = 라벨러 #번호).
# ⚠️ 시트 교체 시 sheet_rects.gd RECTS 갱신 후 **여기 인덱스 11개 재검증 + 라이브 시각 확인 필수** —
#    컴포넌트 수·순서가 변해 인덱스가 밀릴 수 있음(실측 27→31개, R_PANEL #13→#15). 2026-06-09 갱신 시트 기준.
const _SR := preload("res://scripts/sheet_rects.gd")
static var R_PANEL: Rect2 = _SR.RECTS[15]       # 사각 프레임 (큰 창 배경)
static var R_NAV_BG: Rect2 = _SR.RECTS[1]       # 긴 가로 바 (하단 바 배경)
static var R_NAV_BTN: Rect2 = _SR.RECTS[6]      # 가로 버튼 (탭)
static var R_BUY: Rect2 = _SR.RECTS[3]          # 초록 버튼 (구매)
static var R_BUY_OFF: Rect2 = _SR.RECTS[2]      # 갈색 버튼 (비활성)
static var R_CLOSE: Rect2 = _SR.RECTS[26]       # 작은 사각 버튼 (닫기, 팔각형)
static var R_BAR_FILL: Rect2 = _SR.RECTS[24]    # 초록 채움 바 (스테이지 게이지·HP 바 공용, AtlasTexture region)
static var R_HEADER: Rect2 = _SR.RECTS[2]       # 버튼형 프레임 (스테이지 제목 배너) — R_BUY_OFF(#2) 의도적 재사용
static var R_ICON_SLOT: Rect2 = _SR.RECTS[13]   # 작은 사각 프레임 (강화 행 아이콘 배경 슬롯)
static var R_SCRATCH_BG: Rect2 = _SR.RECTS[16]  # 사각 프레임 (스크래치 영역 뒤 배경)
static var R_SETTINGS: Rect2 = _SR.RECTS[19]    # 작은 패널/버튼 (설정 버튼)
static var R_TOPBAR: Rect2 = _SR.RECTS[23]      # 상단 바 (가로로 늘려 사용)

# 등급(희귀도) → 표시색/한글명 — 장비·유물·상점 결과 공용(3개 패널 중복 제거, 2026-06-10).
const GRADE_COLOR := {
	"common": Color(0.78, 0.80, 0.84),
	"rare": Color(0.40, 0.62, 1.00),
	"epic": Color(0.74, 0.45, 0.96),
	"legendary": Color(1.00, 0.80, 0.30),
	"mythic": Color(1.00, 0.35, 0.30),
}
const GRADE_NAME := {"common": "일반", "rare": "희귀", "epic": "영웅", "legendary": "전설", "mythic": "신화"}

# 재화 → 아이콘/색/한글명. 규칙: 모든 UI는 재화를 "아이콘 + 수량"으로 표시(이름 텍스트 금지).
# ⚠️ 유물 가루(dust)는 아이콘 에셋이 아직 없어 텍스트 폴백("유물 가루 50"). 가루 아이콘 생기면 여기 추가. (feedback_currency_icons)
const CURRENCY_ICON := {
	"gold": preload("res://assets/ui/icon/icon_gold.png"),
	"dia": preload("res://assets/ui/icon/icon_dia.png"),
}
const CURRENCY_NAME := {"gold": "골드", "dia": "다이아", "dust": "유물 가루"}
const CURRENCY_COLOR := {
	"gold": Color(1.0, 0.84, 0.25),
	"dia": Color(0.45, 0.8, 1.0),
	"dust": Color(0.7, 0.95, 1.0),
}


static func currency_amount(currency: String, amount: float, font_size: int = 12) -> Control:
	# 재화 표시 공용 = 아이콘 + 수량(gold/dia). 아이콘 없는 재화(dust)는 "이름 수량" 텍스트 폴백.
	var col: Color = CURRENCY_COLOR.get(currency, Color(0.9, 0.9, 0.9))
	var icon: Texture2D = CURRENCY_ICON.get(currency, null)
	if icon == null:
		var only := Label.new()
		only.text = "%s %s" % [CURRENCY_NAME.get(currency, currency), fmt_currency(amount)]
		only.add_theme_font_size_override("font_size", font_size)
		only.add_theme_color_override("font_color", col)
		only.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return only
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.texture = icon
	tex.custom_minimum_size = Vector2(font_size + 4, font_size + 4)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tex)
	var lbl := Label.new()
	lbl.text = fmt_currency(amount)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lbl)
	return hb


# 수령 보상 합산 토스트 — 우편함/퀘스트(패널·트래커) 공용. acc = {재화키: 합계}.
# 재화별 합산을 문자열로 조립해 NotificationManager.reward 로(표시는 NotificationManager 소유, 포맷 안 함).
static func reward_toast(acc: Dictionary) -> void:
	if acc.is_empty():
		return
	var lines: Array = ["보상 수령"]
	for cur in acc:
		lines.append("+%s %s" % [fmt_currency(float(acc[cur])), CURRENCY_NAME.get(cur, cur)])
	NotificationManager.reward("\n".join(lines))


static func _atlas(region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = load(SHEET)
	a.region = region
	return a


static func sb(region: Rect2, margin: int, content: int = -1, modulate := Color(1, 1, 1)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _atlas(region)
	s.set_texture_margin_all(float(margin))   # 9-slice 코너 (소스 px)
	s.modulate_color = modulate
	var cm: int = margin if content < 0 else content
	s.content_margin_left = float(cm)
	s.content_margin_right = float(cm)
	s.content_margin_top = float(cm)
	s.content_margin_bottom = float(cm)
	return s


# --- 패널 배경 ---
static func panel() -> StyleBoxTexture:
	return sb(R_PANEL, 28, 18)


static func nav_bg() -> StyleBoxTexture:
	return sb(R_NAV_BG, 20, 6)


static func header() -> StyleBoxTexture:
	return sb(R_HEADER, 16, 8)


static func icon_slot() -> StyleBoxTexture:
	# #13 작은 프레임 — 강화 행 아이콘 배경 슬롯. content_margin이 안쪽 아이콘 여백.
	return sb(R_ICON_SLOT, 16, 8)


static func scratch_bg() -> StyleBoxTexture:
	# #16 프레임 — 스크래치 영역 뒤 배경.
	return sb(R_SCRATCH_BG, 28, 0)


static func top_bar() -> StyleBoxTexture:
	# #23 상단 바 — 가로로 늘려 사용(9-slice). 캡 보존.
	return sb(R_TOPBAR, 24, 6)


static func style_hp_bar(bar: ProgressBar, fill_color: Color) -> void:
	# 머리 위 체력바 공용 스타일: 배경(깎인 부분)=검은색에 가까운 어두운 회색 / 채움=fill_color. PC=녹색, 적=빨강.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.14)
	bg.set_corner_radius_all(2)
	bg.border_color = Color(0, 0, 0, 0.55)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


# --- 버튼 일괄 스킨 (normal/hover/pressed/disabled) ---
# kind: "nav"/"subtab"(탭) / "buy"(구매, 초록) / "close"(닫기)
static func skin_button(btn: Button, kind: String, content: int = 8) -> void:
	var reg := R_NAV_BTN
	var off := R_BUY_OFF
	var m := 13  # 9-slice 코너(테두리 보존) 크기. 버튼 art 모서리 반경(~13px)에 맞춤 — 작은 버튼이 과하게 둥글지 않게.
	match kind:
		"buy":
			reg = R_BUY
			off = R_BUY_OFF
		"close":
			reg = R_CLOSE
			off = R_CLOSE
			m = 16
		"settings":
			reg = R_SETTINGS
			off = R_SETTINGS
			m = 14
	_apply_button_states(btn, reg, off, m, content, Color(0.82, 0.82, 0.82))


# 버튼 5종(normal/hover/pressed/disabled/focus) 스타일박스 일괄 적용 — skin_button/skin_close_icon 공용.
# 비대칭 주의: normal/hover/pressed/focus 는 reg, disabled 만 off 를 쓴다(buy 는 reg≠off, close 등은 reg==off).
static func _apply_button_states(btn: Button, reg: Rect2, off: Rect2, m: int, content: int, pressed_mod: Color) -> void:
	btn.add_theme_stylebox_override("normal", sb(reg, m, content))
	btn.add_theme_stylebox_override("hover", sb(reg, m, content, Color(1.15, 1.15, 1.15)))
	btn.add_theme_stylebox_override("pressed", sb(reg, m, content, pressed_mod))
	btn.add_theme_stylebox_override("disabled", sb(off, m, content, Color(0.7, 0.7, 0.7)))
	btn.add_theme_stylebox_override("focus", sb(reg, m, content, Color(1, 1, 1, 0)))


# 닫기 버튼: #26 조각(팔각형)을 **9-slice 없이 원래 모양 그대로** 배경으로 + close 아이콘 중앙.
# ⚠️ #26은 팔각형 → 9-slice로 늘리면 팔각이 깨짐. texture_margin 0(통짜 스트레치)으로 두고,
#    버튼을 조각 비율(79:74 ≈ 1.07 → 43×40)에 맞춰 호출해야 왜곡 없음.
static func skin_close_icon(btn: Button) -> void:
	_apply_button_states(btn, R_CLOSE, R_CLOSE, 0, 2, Color(0.85, 0.85, 0.85))
	btn.text = ""
	btn.icon = load(ICON_CLOSE)
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("icon_max_width", 20)
	# 흰색 아이콘을 패널 텍스트색(크림)으로 틴트. 상태별로 약간 변주.
	btn.add_theme_color_override("icon_normal_color", CLOSE_ICON_COLOR)
	btn.add_theme_color_override("icon_hover_color", Color(1.0, 0.97, 0.9))
	btn.add_theme_color_override("icon_pressed_color", CLOSE_ICON_COLOR.darkened(0.15))
	btn.add_theme_color_override("icon_focus_color", CLOSE_ICON_COLOR)
	btn.add_theme_color_override("icon_disabled_color", CLOSE_ICON_COLOR.darkened(0.4))


# --- 패널 공용 정적 헬퍼 (2026-06-10 리팩토링 — 패널 간 중복 추출) ---

# 재화 포맷 (단일 출처, HUD·패널 공용) — 재화 정책 "10억(1e9)부터 K".
# 10억 미만은 콤마(2,600,000), 이상은 K/M/B/T/Q 축약하되 접미사 앞 mantissa<10억 유지
# (10억=1,000,000K · 1조=1,000,000M · 1e18=1,000,000T). game.gd._fmt 도 이 함수에 위임(중복 제거).
const FMT_RAW_MAX := 1_000_000_000.0
const FMT_STEP := 1000.0
const FMT_SUFFIXES := ["", "K", "M", "B", "T", "Q"]

static func fmt_currency(n: float) -> String:
	var v: float = floor(n)
	if v < FMT_RAW_MAX:
		return _comma_num(v)
	var tier: int = 0
	var m: float = v
	while m >= FMT_RAW_MAX and tier < FMT_SUFFIXES.size() - 1:
		m /= FMT_STEP
		tier += 1
	return _comma_num(floor(m)) + String(FMT_SUFFIXES[tier])


static func _comma_num(v: float) -> String:
	# 음이 아닌 정수에 천 단위 콤마. "%.0f"로 float→정수 문자열(int(v) 의 int64 한계·부호붕괴 회피).
	var digits: String = "%.0f" % v
	var out: String = ""
	var cnt: int = 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out


# 등급색 틴트 행 스타일(장비/유물 행·슬롯 칩 공용). m 성분이 -1 이면 content margin 미설정(StyleBox 기본값).
static func grade_row_style(col: Color, bg_a: float = 0.16, corner: int = 5, border_w: int = 1, border_a: float = 0.6, m: Vector4i = Vector4i(6, 6, 4, 4)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(col.r, col.g, col.b, bg_a)
	s.set_corner_radius_all(corner)
	s.set_border_width_all(border_w)
	s.border_color = Color(col.r, col.g, col.b, border_a)
	s.content_margin_left = float(m.x)
	s.content_margin_right = float(m.y)
	s.content_margin_top = float(m.z)
	s.content_margin_bottom = float(m.w)
	return s


# 다크 인셋 행 스타일(강화/상점 소환 행 공용) — 다크 우드 패널 위 살짝 더 어두운 행 구분.
static func inset_row_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.22)
	s.set_corner_radius_all(6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


# buy 스킨 버튼 팩토리 — 부재 속성 skip 시멘틱: disabled_col 은 alpha 0 sentinel 이면 오버라이드 미추가,
# white=false 면 font_color 미추가, focus_none=false 면 focus_mode 미설정(기본 FOCUS_ALL 유지).
# text·tooltip·disabled·시그널 연결·아이콘 설정은 호출부 책임.
static func make_buy_button(min_size: Vector2, font_size: int, content: int = 4, focus_none: bool = true, white: bool = true, disabled_col: Color = Color(0, 0, 0, 0), expand: bool = false) -> Button:
	var b := Button.new()
	if focus_none:
		b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", font_size)
	if white:
		b.add_theme_color_override("font_color", Color(1, 1, 1))
	if disabled_col.a > 0.0:
		b.add_theme_color_override("font_disabled_color", disabled_col)
	skin_button(b, "buy", content)
	return b


# 전체화면 dim + CenterContainer + VBox 스캐폴드(설정/치트 패널 공용). root 에 anchor fill + STOP 까지 설정.
static func build_dim_center(root: Control, dim_a: float, sep: int, min_w: float) -> VBoxContainer:
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, dim_a)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	root.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", sep)
	vbox.custom_minimum_size = Vector2(min_w, 0)
	center.add_child(vbox)
	return vbox


# 리스트/안내 공용 소품 — 패널 4종의 자잘한 중복(비우기 루프·빈 안내·준비중 stub·세로 스크롤).

static func clear_children(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


static func make_empty_label(text: String) -> Label:
	# 보유 목록이 비었을 때 안내 라벨(장비/유물 패널 공용).
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.80, 0.77, 0.70))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.visible = false
	return l


static func make_stub_label(color: Color) -> Label:
	# "준비 중입니다" stub(강화/상점 공용 — 색만 패널별 인자).
	var l := Label.new()
	l.text = "준비 중입니다"
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.visible = false
	return l


static func make_vlist_scroll(h_expand: bool = true) -> ScrollContainer:
	# 세로 리스트 스크롤 컨테이너. h_expand=false 면 horizontal flag 미설정(강화 패널 원형 보존).
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if h_expand:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


# (스테이지/HP 게이지는 게임 코드가 AtlasTexture(R_BAR_FILL)+마스크로 직접 구성 — game.gd._build_masked_bar)
