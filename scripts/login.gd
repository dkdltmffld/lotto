extends Control

# 로그인 게이트 (메인 씬). 계정 3종 중 택1 → 게임(main.tscn) 진입.
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
@onready var kplay_button: Button = $Bottom/KplayButton
@onready var guest_button: Button = $Bottom/GuestButton

const LOGIN_TIMEOUT: float = 20.0

var _entering: bool = false       # 게임 씬 진입 중복 방지
var _waiting_login: bool = false  # 인증 결과 대기 중


func _ready() -> void:
	# 배경 이미지($Background)가 캔버스를 덮으므로 캔버스는 불투명으로 둔다.
	# (게임 씬에서 transparent_bg=true로 켰다가 로그인 복귀 시 잔존할 수 있어 명시적으로 끔)
	get_tree().root.transparent_bg = false
	# @export로 지정한 제목 이미지가 있으면 씬 기본값을 덮어씀
	if title_logo_texture != null:
		logo.texture = title_logo_texture
	_skin_ui()
	google_button.pressed.connect(_on_google_pressed)
	kplay_button.pressed.connect(_on_kplay_pressed)
	guest_button.pressed.connect(_on_guest_pressed)
	BackendService.login_changed.connect(_on_login_changed)
	status_label.text = "계정을 선택하세요"


# 배경 일러스트(bg_main)+캐릭터 위에서 또렷하게 읽히도록 하단 UI 스킨.
# 버튼=어두운 반투명 패널+금색 테두리, 상태 라벨=밝은 크림+그림자.
func _skin_ui() -> void:
	for b in [google_button, kplay_button, guest_button]:
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
	_start_login(BackendService.ACCOUNT_GOOGLE)


func _on_kplay_pressed() -> void:
	_start_login(BackendService.ACCOUNT_KPLAY)


func _on_guest_pressed() -> void:
	# 게스트: 게스트 슬롯 데이터를 로드한 뒤 진입 (로컬 저장, 랭킹 등록 제한)
	await BackendService.continue_as_guest()
	_enter_game()


func _start_login(provider: String) -> void:
	if _entering or _waiting_login:
		return
	_set_buttons_enabled(false)
	status_label.text = "로그인 중..."
	if BackendService.is_logged_in:
		# 이미 플랫폼 인증됨(예: kplay 자동 로그인) → 재인증 없이 인증 슬롯 로드 + 계정 표기 갱신 후 진입.
		# (이게 없으면 게스트→구글 등 계정 변경 시 표기·데이터가 이전(게스트) 그대로 유지됨)
		await BackendService.commit_auth_session(provider)
		_enter_game()
		return
	_waiting_login = true
	BackendService.begin_login(provider)
	_login_timeout()


func _login_timeout() -> void:
	await get_tree().create_timer(LOGIN_TIMEOUT).timeout
	# 로그인 성공 → 게임 씬 전환으로 login 노드가 free된 뒤 타이머가 재개될 수 있다(SceneTreeTimer는 트리 소유).
	# freed 인스턴스 멤버 접근 = 콘솔 에러 → 트리 밖이면 조기 return.
	if not is_inside_tree():
		return
	if _waiting_login and not _entering:
		_waiting_login = false
		_set_buttons_enabled(true)
		status_label.text = "로그인에 실패했어요. 다시 시도해주세요."


func _on_login_changed(logged_in: bool) -> void:
	if logged_in and _waiting_login:
		_waiting_login = false
		_enter_game()


func _enter_game() -> void:
	if _entering:
		return
	_entering = true
	_goto_scene("res://scenes/main.tscn")


func _goto_scene(path: String) -> void:
	# Stage(cover 스테이지)가 있으면 SubViewport 내부에서 전환, 없으면(단독 실행) 일반 전환. (본문은 SceneNav 공용)
	SceneNav.goto_scene(get_tree(), path)


func _set_buttons_enabled(on: bool) -> void:
	for b in [google_button, kplay_button, guest_button]:
		b.disabled = not on
