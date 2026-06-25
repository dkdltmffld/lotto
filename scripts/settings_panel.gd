extends Control

# 설정 오버레이. 방치형이라 일시정지는 없고, 사운드 + 계정 관련(메인 메뉴/로그아웃/계정 탈퇴)을 모은다.
# 코드로 UI를 빌드(임시 placeholder — 추후 UI 스프라이트). 기획서: docs/design/설정 시스템 정리본.md
# 사운드 옵션은 autoload Audio(scripts/audio_manager.gd)를 직접 호출 — 변경 즉시 반영·저장된다.

signal main_menu_pressed
signal logout_pressed
signal delete_account_pressed
signal closed

var _account_label: Label = null
var _mute_check: CheckButton = null
var _bgm_slider: HSlider = null
var _sfx_slider: HSlider = null
var _dungeon_auto_check: CheckButton = null


func _ready() -> void:
	# 전체 화면 오버레이 + 어두운 배경 + 가운데 VBox(제목/계정표시/메인메뉴·로그아웃·계정탈퇴·닫기).
	var vbox := UISkin.build_dim_center(self, 0.7, 14, 280.0)

	var title := Label.new()
	title.text = "설정"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_account_label = Label.new()
	_account_label.add_theme_font_size_override("font_size", 16)
	_account_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 0.9))
	_account_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_account_label)

	# --- 사운드 섹션 ---
	vbox.add_child(_make_section_label("사운드"))
	_mute_check = CheckButton.new()
	_mute_check.text = "음소거"
	_mute_check.add_theme_font_size_override("font_size", 18)
	_mute_check.toggled.connect(func(on: bool): Audio.set_muted(on))
	vbox.add_child(_mute_check)
	_bgm_slider = _make_volume_row(vbox, "배경음", func(v: float): Audio.set_bgm_volume(v))
	_sfx_slider = _make_volume_row(vbox, "효과음", func(v: float): Audio.set_sfx_volume(v))

	# --- 던전 섹션 ---
	# 자동 등반(기본 켜짐): 던전 입장 시 실패 전까지 자동으로 다음 층 진행. 끄면 층마다 결과 화면(수동).
	vbox.add_child(_make_section_label("던전"))
	_dungeon_auto_check = CheckButton.new()
	_dungeon_auto_check.text = "자동 등반"
	_dungeon_auto_check.add_theme_font_size_override("font_size", 18)
	_dungeon_auto_check.toggled.connect(func(on: bool): BackendService.set_dungeon_auto(on))
	vbox.add_child(_dungeon_auto_check)

	# --- 계정 섹션 ---
	vbox.add_child(_make_section_label("계정"))
	vbox.add_child(_make_button("메인 메뉴 (계정 변경)", func(): main_menu_pressed.emit()))
	vbox.add_child(_make_button("로그아웃", func(): logout_pressed.emit()))
	var del := _make_button("계정 탈퇴", func(): delete_account_pressed.emit())
	del.add_theme_color_override("font_color", Color(1, 0.55, 0.55))
	vbox.add_child(del)
	vbox.add_child(_make_button("닫기", func(): closed.emit()))


func open() -> void:
	# UIManager.open_overlay() 통일 인터페이스 — 계정·사운드 표시 갱신 후 표시.
	refresh()
	visible = true


func _make_button(text: String, cb: Callable) -> Button:
	# 공통 버튼 생성 헬퍼 (텍스트 + 눌렀을 때 콜백).
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _make_section_label(text: String) -> Label:
	# 섹션 구분용 소제목.
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _make_volume_row(parent: VBoxContainer, label_text: String, cb: Callable) -> HSlider:
	# [라벨] [0~1 슬라이더] 한 줄. 슬라이더 값 변경 시 cb(value) 호출.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 36)
	slider.value_changed.connect(cb)
	row.add_child(slider)
	parent.add_child(row)
	return slider


func refresh() -> void:
	# 패널 열 때 game.gd가 호출: 계정 표시 + 사운드 컨트롤을 현재 Audio 상태로 동기화.
	if _account_label != null:
		if BackendService.is_guest():
			_account_label.text = "게스트"
		else:
			var nm: String = BackendService.user_name
			_account_label.text = "%s (%s)" % [nm if nm != "" else "?", BackendService.account_type]
	# 사운드 컨트롤 동기화 (set_block_signals로 동기화 중 콜백 재진입 방지)
	if _mute_check != null:
		_mute_check.set_block_signals(true)
		_mute_check.button_pressed = Audio.muted
		_mute_check.set_block_signals(false)
	if _bgm_slider != null:
		_bgm_slider.set_block_signals(true)
		_bgm_slider.value = Audio.bgm_volume
		_bgm_slider.set_block_signals(false)
	if _sfx_slider != null:
		_sfx_slider.set_block_signals(true)
		_sfx_slider.value = Audio.sfx_volume
		_sfx_slider.set_block_signals(false)
	if _dungeon_auto_check != null:
		_dungeon_auto_check.set_block_signals(true)
		_dungeon_auto_check.button_pressed = BackendService.get_dungeon_auto()
		_dungeon_auto_check.set_block_signals(false)
