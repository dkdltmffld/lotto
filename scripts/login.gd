extends Control

# 로그인 게이트 (메인 씬). 구글/게스트 로컬 슬롯 중 택1 → 게임(main.tscn) 진입.
# 두 버튼 모두 외부 인증 없이 즉시 로컬 데이터를 불러온다.
# 설계: docs/design/로그인 시스템 정리본.md

# 로그인 화면 배경: bg_main.png(`$Background` TextureRect, cover=KEEP_ASPECT_COVERED).
# 이미지(9:16)가 화면(9:19.5)보다 가로로 넓어 좌우가 약간 크롭됨. 캔버스는 불투명(배경이 덮음).
# 게임 제목은 텍스트가 아니라 타이포그래피 이미지(Logo). 인스펙터에서 Logo.texture 직접
# 지정하거나, 아래 @export로 교체 가능(있으면 씬 기본값을 덮어씀).
@export var title_logo_texture: Texture2D  # 게임 제목 타이포그래피 이미지

const SceneNav := preload("res://scripts/scene_nav.gd")  # 씬 전환 공용 헬퍼(game.gd와 공유)

@onready var logo: TextureRect = $Logo
@onready var status_label: Label = $Bottom/StatusLabel
@onready var google_button: Button = $Bottom/GoogleButton
@onready var guest_button: Button = $Bottom/GuestButton

var _entering: bool = false  # 로컬 슬롯 로드·게임 씬 진입 중복 방지


func _ready() -> void:
	# 배경 이미지($Background)가 캔버스를 덮으므로 캔버스는 불투명으로 둔다.
	# (게임 씬에서 transparent_bg=true로 켰다가 로그인 복귀 시 잔존할 수 있어 명시적으로 끔)
	get_tree().root.transparent_bg = false
	# @export로 지정한 제목 이미지가 있으면 씬 기본값을 덮어씀
	if title_logo_texture != null:
		logo.texture = title_logo_texture
	_skin_ui()
	google_button.pressed.connect(_on_google_pressed)
	guest_button.pressed.connect(_on_guest_pressed)
	status_label.text = "계정을 선택하세요"


# 배경 일러스트(bg_main)+캐릭터 위에서 또렷하게 읽히도록 하단 UI 스킨.
# 버튼=어두운 반투명 패널+금색 테두리, 상태 라벨=밝은 크림+그림자.
func _skin_ui() -> void:
	for b in [google_button, guest_button]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.09, 0.07, 0.88)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.72, 0.56, 0.28)
		sb.set_corner_radius_all(10)
		var hov := sb.duplicate()
		hov.bg_color = Color(0.20, 0.16, 0.11, 0.94)
		hov.border_color = Color(0.92, 0.74, 0.40)
		var prs := sb.duplicate()
		prs.bg_color = Color(0.07, 0.06, 0.04, 0.94)
		var dis := sb.duplicate()
		dis.bg_color = Color(0.10, 0.09, 0.08, 0.55)
		dis.border_color = Color(0.45, 0.40, 0.30, 0.7)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", prs)
		b.add_theme_stylebox_override("disabled", dis)
		b.add_theme_stylebox_override("focus", sb)
		b.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82))
		b.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.85))
		b.add_theme_color_override("font_pressed_color", Color(0.82, 0.78, 0.68))
		b.add_theme_color_override("font_disabled_color", Color(0.7, 0.66, 0.58, 0.8))
	status_label.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86))
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)


func _on_google_pressed() -> void:
	_select_local_account(BackendService.ACCOUNT_GOOGLE)


func _on_guest_pressed() -> void:
	_select_local_account(BackendService.ACCOUNT_GUEST)


func _select_local_account(account: String) -> void:
	# 구글/게스트 모두 로컬 전용이다. 슬롯만 분리해 서로의 진행도를 보호한다.
	if _entering:
		return
	_entering = true
	_set_buttons_enabled(false)
	status_label.text = "데이터를 불러오는 중..."
	if account == BackendService.ACCOUNT_GOOGLE:
		await BackendService.continue_as_google()
	else:
		await BackendService.continue_as_guest()
	if is_inside_tree():
		_goto_scene("res://scenes/main.tscn")


func _goto_scene(path: String) -> void:
	# Stage(cover 스테이지)가 있으면 SubViewport 내부에서 전환, 없으면(단독 실행) 일반 전환. (본문은 SceneNav 공용)
	SceneNav.goto_scene(get_tree(), path)


func _set_buttons_enabled(on: bool) -> void:
	for b in [google_button, guest_button]:
		b.disabled = not on
