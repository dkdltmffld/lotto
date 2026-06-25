class_name PlayerController
extends AnimatedSprite2D

# PC 자체 상태·모션·위치·머리 위 HP바를 관리한다.
# 게임 흐름(상태 전이 트리거, 데미지 적용 시점 등)은 game.gd가 외부 API 호출/시그널 수신으로 조율한다.

signal attack_motion_completed  # attack 애니메이션 종료 = 데미지 적용 시점 (기획서 5-1)

const HPBarScene: PackedScene = preload("res://scenes/hp_bar.tscn")

# 머리 위 HP바 위치 보정 (sprite 중심 기준).
# VISUAL_SCALE 변경 시 같이 조정 필요.
const HP_BAR_OFFSET := Vector2(-25, -67)

# 시트별 캐릭터 크기/발끝 스캔 (불투명 픽셀 기준). enemy.gd와 동일 접근:
# 시트마다 캐릭터가 그려진 크기·위치가 달라(특히 attack이 작게 그려짐) 애니 전환 시 크기가 튐 →
# idle을 기준 크기로 삼아 각 애니의 scale 보정 + 발끝을 공통 바닥선에 정렬한다.
# 스캔 자체(발끝·캐릭터 높이, 경로|프레임폭 1회 캐시)는 sprite_scan.gd 공용 유틸로 이동.
const SpriteScanLib := preload("res://scripts/sprite_scan.gd")

# --- 포즈투포즈 프로토타입 (2026-06-19, 치트 토글로 현재 방식과 비교) ---
# attack 시트에서 핵심 포즈 3장(준비/타격/마무리)만 샘플 → 임팩트 프레임을 짧게 hold(히트스톱 대체)
# + 타격 순간 슬래시 이펙트로 중간을 가린다. 새 아트 없이 "기법"만 비교하려는 더미. 비율/홀드/속도는 전부 튜닝 노브.
const POSE_ANTICIPATION_RATIO: float = 0.15  # 준비 포즈 = attack 프레임의 이 위치(0~1)
const POSE_IMPACT_RATIO: float = 0.55        # 타격 포즈 = attack 프레임의 이 위치(0~1)
const POSE_IMPACT_HOLD: int = 3              # 타격 프레임 반복 수(클수록 더 오래 멈춤=묵직)
const POSE_SPEED: float = 20.0               # attack_pose 재생 fps (총길이≈현재 attack과 맞춤)
const POSE_IMPACT_SLOT: int = 1              # attack_pose 안에서 타격 프레임 시작 인덱스(준비 1장 다음)
const POSE_SLASH_OFFSET: Vector2 = Vector2(46, -8)  # 슬래시(타격 순간) 위치(PC 앞)
const POSE_SWING_OFFSET: Vector2 = Vector2(22, -16)  # 휘두름 궤적(스워시) 회전 중심(PC 손/어깨 근처)

var pose_mode: bool = true           # [2026-06-19] 포즈투포즈 공격(3포즈+홀드+슬래시+스윙트레일)을 기본값으로. 치트 "원래대로"로 옛 풀프레임 방식과 비교 가능.
var _pose_slash_fired: bool = false  # 한 스윙에 슬래시 1회만

var _hp_bar: ProgressBar = null
var _is_dead: bool = false
var _anim_render: Dictionary = {}  # anim -> {scale, offset_y} (크기 정규화 + 발끝 정렬)

# --- 무기 부착 (2026-06-24, 무기 분리 step 2 — 몽둥이부터) ---
# 장착 무기를 PC 손에 표시. Weapon = 형제 Sprite2D(몸 자식 X — per-anim scale 정규화가 무기까지 왜곡).
# 몸보다 뒤(z-1)에 깔아 몸의 주먹이 손잡이를 덮음 = "손이 무기 위"(사용자 결정 2026-06-24).
# 단일 이미지(몽둥이)를 키프레임 2개(와인드업/타격)로 스냅 전환 — PC 포즈투포즈와 동일(트윈 X, 몸 프레임 전환과 동기). 검(_0/_1 포즈)은 이후 텍스처 스왑으로 확장.
# ⚠️ 현재 idle/run/attacked/dead 시트엔 검이 baked-in → 겹침 방지 위해 공격 모션 중에만 표시. 나머지 빈손화 후 상시 표시.
# 아래 값은 전부 튜닝 노브(라이브로 맞춤).
const WEAPON_TEXTURE: Texture2D = preload("res://assets/sprites/weapon/w_0001.png")  # TODO: Events.equipment_changed 로 교체
const WEAPON_SCALE: float = 0.30                  # 화면상 무기 크기
const WEAPON_GRIP: Vector2 = Vector2(128, 235)    # 텍스처 내 손잡이(회전 중심) 픽셀 — 몽둥이 하단
const WEAPON_Z_BEHIND: int = -1                   # 공격 시 무기 z(음수=뒤) → 몸 주먹이 손잡이 덮음("손이 무기 위")
const WEAPON_Z_RUN: int = 1                       # run 시 무기 z(양수=앞) → 가까운(오른)손이 쥔 것처럼 보이게(몸 앞)
# 손 앵커 = player.position(발끝) 기준 화면 오프셋. 무기 회전각 = 라디안(+ 시계방향, 0=위로). 2개 키프레임을 스냅 전환.
const WEAPON_WINDUP_OFFSET: Vector2 = Vector2(10, -15)   # 들어올린 주먹(머리 옆) — 48px 빈손 포즈서 역산
const WEAPON_WINDUP_ROT: float = -0.35
const WEAPON_STRIKE_OFFSET: Vector2 = Vector2(4, 16)     # 허리 앞 주먹 — 48px 빈손 포즈서 역산
const WEAPON_STRIKE_ROT: float = 1.35
# run(달리기) — 오른손에 들고 뒤로 늘어뜨림. 고정 트레일링 앵커(run 사이클 동안 유지).
const WEAPON_RUN_OFFSET: Vector2 = Vector2(-18, -11)     # 뒤로 젖힌 손(어깨·뒤·위) — run 스프라이트가 한 팔을 뒤로 빼므로 거기에 그립. 48px (13,15)서 역산
const WEAPON_RUN_ROT: float = 4.85                       # 뒤로 거의 수평(팔과 평행, ~8° 위로 들림). 0=위/+시계방향. 4.71=정수평, 키우면 위로
# run 중 무기에 생기 부여 — 스프라이트 자체는 몸통 상하 움직임이 거의 없어(다리만 움직임) 절차적으로 흔든다. run 애니 프레임에 위상 동기.
const RUN_BOB_AMP: float = 2.5                           # 상하 바운스 진폭(px)
const RUN_SWAY_AMP: float = 0.12                         # 회전 흔들림 진폭(라디안, ~7°)
const RUN_BOB_CYCLES: float = 2.0                        # run 한 사이클당 바운스 횟수(보폭 수에 맞춤)

var _weapon: Sprite2D = null
var _has_weapon: bool = true        # 현재 항상 몽둥이 장착(추후 장비 시스템 연동)
var _weapon_offset: Vector2 = Vector2.ZERO
var _weapon_rot: float = 0.0
var _run_frame_count: int = 0       # run 애니 프레임 수(바운스 위상 계산용)


func _ready() -> void:
	# PC 위치·크기는 PlayerData에서 가져와 적용
	scale = Vector2(PlayerData.VISUAL_SCALE, PlayerData.VISUAL_SCALE)
	position.x = PlayerData.HOME_X
	_build_animations()
	if sprite_frames != null and sprite_frames.has_animation("run"):
		_run_frame_count = sprite_frames.get_frame_count("run")
	animation_finished.connect(_on_animation_finished)
	frame_changed.connect(_on_frame_changed)
	_play("idle")
	_create_hp_bar()
	_create_weapon()
	# 부모(Arena) 크기에 따라 Y 동기
	var arena: Control = get_parent()
	arena.resized.connect(_on_arena_resized)
	_on_arena_resized()


func _process(_delta: float) -> void:
	# 머리 위 HP바가 PC 위치를 따라가도록 매 프레임 갱신
	if _hp_bar != null:
		_hp_bar.position = position + HP_BAR_OFFSET
	_update_weapon()


# --------- 외부 API ---------

func play_idle() -> void:
	_play("idle")


func play_run() -> void:
	_play("run")
	_weapon_to_run()  # 무기 = 트레일링 자세(오른손에 들고 뒤로 늘어뜨림)


func play_attack() -> void:
	# attack 모션 + 잽 위치 트윈 + modulate 강조. 모두 attack 애니메이션 길이(~0.5초)에 동기.
	_start_attack_anim()
	var home_x: float = PlayerData.HOME_X
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position:x", home_x + 24, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:x", home_x, 0.35).set_ease(Tween.EASE_OUT).set_delay(0.03)
	var tw2 := create_tween()
	tw2.tween_property(self, "modulate", Color(1.4, 1.4, 1.6), 0.1)
	tw2.tween_property(self, "modulate", Color(1, 1, 1), 0.4)


func play_auto_attack() -> void:
	# 일반 공격(자동) — 가벼운 attack 모션 + 작은 잽. 자주 발동하므로 modulate 플래시는 생략.
	# (데미지는 game.gd가 타이머로 적용 — 이 모션은 연출용. 스킬 모션 우선이라 attack 중이면 생략.)
	if _is_attacking():
		return
	_start_attack_anim()
	var home_x: float = PlayerData.HOME_X
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position:x", home_x + 12, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:x", home_x, 0.16).set_ease(Tween.EASE_OUT)


func play_attacked() -> void:
	# 모션 우선 룰: attack 중이면 attacked 모션 미재생 (데미지만 적용)
	if _is_attacking():
		return
	_play("attacked")


func play_dead() -> void:
	_is_dead = true
	_play("dead")


func revive() -> void:
	# 보스 사망 후 블록 재시작 시 다시 살아나 idle/run으로 복귀 가능하게.
	_is_dead = false
	modulate = Color(1, 1, 1, 1)
	position.x = PlayerData.HOME_X
	_play("idle")


func flash_hit() -> void:
	Effects.flash_modulate(self, Color(2.0, 0.5, 0.5))


func set_hp(value: float) -> void:
	if _hp_bar != null:
		_hp_bar.value = float(value)


func set_max_hp(value: float) -> void:
	if _hp_bar != null:
		_hp_bar.max_value = max(1.0, value)


func set_hp_visible(on: bool) -> void:
	# PC 체력바는 보스전에서만 표시 (일반 스테이지는 위협 없음)
	if _hp_bar != null:
		_hp_bar.visible = on


func reset_visual() -> void:
	# 트윈 kill 후 정상 모습으로 강제 복귀
	modulate = Color(1, 1, 1, 1)
	position.x = PlayerData.HOME_X


# --------- 내부 ---------

func _build_animations() -> void:
	var sf := SpriteFrames.new()
	for anim_name in PlayerData.ANIMATIONS:
		var meta: Dictionary = PlayerData.ANIMATIONS[anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, meta.speed)
		sf.set_animation_loop(anim_name, meta.loop)
		if meta.has("pose_base"):
			_add_pose_frames(sf, anim_name, String(meta["pose_base"]))
		else:
			_add_sheet_frames(sf, anim_name, String(meta.get("path", "")))
	_build_attack_pose(sf)
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sprite_frames = sf
	_compute_anim_render()


func _add_sheet_frames(sf: SpriteFrames, anim_name: String, path: String) -> void:
	# 가로 시트: 정사각 프레임(한 변 = 텍스처 높이) → width/height 개로 슬라이스.
	# 시트마다 프레임 크기가 달라도 됨(48px·256px 혼재 지원) — FRAME_SIZE 고정 제거, 높이로 자동 감지.
	var tex: Texture2D = load(path)
	if tex == null:
		push_warning("PlayerController: 시트 누락 " + path)
		return
	var fs: int = tex.get_height()
	if fs <= 0:
		return
	var frame_count: int = int(tex.get_width() / fs)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * fs, 0, fs, fs)
		sf.add_frame(anim_name, atlas)


func _add_pose_frames(sf: SpriteFrames, anim_name: String, base: String) -> void:
	# 포즈 파일: base_0.png, base_1.png, … 를 0부터 연속으로 로드(끊기면 종료).
	# 각 파일 = 한 프레임 전체(슬라이싱 없음). 0=시작 포즈, 증가=뒤 포즈. [[reference_sprite_naming]]
	var i: int = 0
	while true:
		var path: String = "%s_%d.png" % [base, i]
		if not ResourceLoader.exists(path):
			break
		var tex: Texture2D = load(path)
		if tex == null:
			break
		sf.add_frame(anim_name, tex)
		i += 1
	if i == 0:
		push_warning("PlayerController: 포즈 파일 없음 " + base + "_0.png")


func _build_attack_pose(sf: SpriteFrames) -> void:
	# [포즈투포즈 프로토타입] attack 시트에서 포즈 3장만 샘플 → [준비, 타격×HOLD, 마무리].
	# 임팩트 프레임 반복 = 히트스톱(멈춤) 대체. 새 시트 안 만들고 attack 프레임 재사용.
	if not sf.has_animation("attack"):
		return
	var ac: int = sf.get_frame_count("attack")
	if ac <= 0:
		return
	var anticip: int = clampi(int(round((ac - 1) * POSE_ANTICIPATION_RATIO)), 0, ac - 1)
	var impact: int = clampi(int(round((ac - 1) * POSE_IMPACT_RATIO)), 0, ac - 1)
	var recover: int = ac - 1
	sf.add_animation("attack_pose")
	sf.set_animation_speed("attack_pose", POSE_SPEED)
	sf.set_animation_loop("attack_pose", false)
	sf.add_frame("attack_pose", sf.get_frame_texture("attack", anticip))
	for _i in POSE_IMPACT_HOLD:
		sf.add_frame("attack_pose", sf.get_frame_texture("attack", impact))
	sf.add_frame("attack_pose", sf.get_frame_texture("attack", recover))


func _play(anim: String) -> void:
	# 재생 + 시트별 크기 정규화(scale) + 발끝 정렬(offset). 모든 play는 이걸 거친다.
	SpriteScanLib.apply_render(self, anim, _anim_render, PlayerData.VISUAL_SCALE)


func _is_attacking() -> bool:
	return animation == "attack" or animation == "attack_pose"


func _start_attack_anim() -> void:
	# [포즈투포즈] pose_mode 면 attack_pose(3포즈+홀드+슬래시+휘두름 궤적), 아니면 기존 attack 시트.
	_weapon_to_windup()  # 무기 = 와인드업 자세로(타격 프레임에서 _start_weapon_swing 으로 휘두름)
	if pose_mode:
		_pose_slash_fired = false
		_play("attack_pose")
		var parent := get_parent()
		if parent != null:
			Effects.spawn_swing_trail(parent, position + POSE_SWING_OFFSET)
	else:
		_play("attack")


func _on_frame_changed() -> void:
	# [포즈투포즈] 타격 포즈가 뜨는 순간 슬래시 이펙트로 중간을 가린다(한 스윙 1회).
	if pose_mode and animation == "attack_pose" and frame == POSE_IMPACT_SLOT and not _pose_slash_fired:
		_pose_slash_fired = true
		var parent := get_parent()
		if parent != null:
			Effects.spawn_slash(parent, position + POSE_SLASH_OFFSET)
		_weapon_to_strike()  # 무기 = 타격 키프레임으로 스냅(몸 strike 프레임과 동기)


func _compute_anim_render() -> void:
	# idle을 기준 크기로 삼아 각 애니의 scale·offset_y 계산. (스캔 실패 시 기본 스케일·offset 0 폴백)
	# ⚠️ 프레임 한 칸 크기가 애니마다 다를 수 있음(시트=FRAME_SIZE, 포즈 파일=네이티브 폭) → half를 애니별로 계산.
	var base_scale: float = PlayerData.VISUAL_SCALE
	var idle_scan: Dictionary = _scan_anim(PlayerData.ANIMATIONS.get("idle", {}))
	var idle_half: float = float(int(idle_scan.get("frame_size", PlayerData.FRAME_SIZE))) * 0.5
	var base_h: int = int(idle_scan.get("char_h", -1))
	var idle_feet: int = int(idle_scan.get("feet", -1))
	# idle 발끝의 화면상 위치(position.y 기준 오프셋) — 다른 애니도 여기에 맞춘다.
	var target: float = base_scale * (float(idle_feet) - idle_half) if idle_feet >= 0 else 0.0
	for anim_name in PlayerData.ANIMATIONS:
		var scan: Dictionary = _scan_anim(PlayerData.ANIMATIONS[anim_name])
		var half: float = float(int(scan.get("frame_size", PlayerData.FRAME_SIZE))) * 0.5
		var ch: int = int(scan.get("char_h", -1))
		var norm: float = 1.0
		if base_h > 0 and ch > 0:
			norm = float(base_h) / float(ch)  # 이 애니 캐릭터를 idle 크기로
		var sc: float = base_scale * norm
		var off_y: float = 0.0
		var feet: int = int(scan.get("feet", -1))
		if feet >= 0 and sc > 0.0:
			off_y = target / sc - (float(feet) - half)  # 발끝을 idle 바닥선에 맞춤
		_anim_render[anim_name] = {"scale": sc, "offset_y": off_y}
	# [포즈투포즈] attack_pose 는 attack 프레임 재사용 → 같은 렌더 파라미터.
	if _anim_render.has("attack"):
		_anim_render["attack_pose"] = _anim_render["attack"]


func _scan_anim(meta: Dictionary) -> Dictionary:
	# 애니의 모든 프레임을 스캔해 발끝·캐릭터높이(중앙값) + 프레임 한 칸 크기를 반환.
	# 시트: scan_sheet가 width/FRAME_SIZE로 프레임을 나눠 중앙값. 포즈 파일: 각 _i 파일을 개별 스캔해 중앙값.
	if meta.has("pose_base"):
		var base: String = String(meta["pose_base"])
		var feets: Array = []
		var heights: Array = []
		var fs: int = PlayerData.FRAME_SIZE
		var i: int = 0
		while true:
			var path: String = "%s_%d.png" % [base, i]
			if not ResourceLoader.exists(path):
				break
			var t: Texture2D = load(path)
			if t == null:
				break
			if i == 0:
				fs = int(t.get_width())  # 포즈 캔버스 크기(전체가 한 프레임)
			var s: Dictionary = SpriteScanLib.scan_sheet(t, int(t.get_width()))
			if int(s.get("feet", -1)) >= 0:
				feets.append(int(s["feet"]))
				heights.append(int(s["char_h"]))
			i += 1
		feets.sort()
		heights.sort()
		var feet: int = int(feets[feets.size() / 2]) if not feets.is_empty() else -1
		var ch: int = int(heights[heights.size() / 2]) if not heights.is_empty() else -1
		return {"feet": feet, "char_h": ch, "frame_size": fs}
	var tex: Texture2D = load(String(meta.get("path", "")))
	var fs: int = tex.get_height() if tex != null else PlayerData.FRAME_SIZE  # 정사각 프레임 = 높이
	var scan: Dictionary = SpriteScanLib.scan_sheet(tex, fs)
	return {"feet": int(scan.get("feet", -1)), "char_h": int(scan.get("char_h", -1)), "frame_size": fs}


func _create_hp_bar() -> void:
	_hp_bar = HPBarScene.instantiate()
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.visible = false  # game.gd가 set_hp_visible로 제어(교전 중 표시)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UISkin.style_hp_bar(_hp_bar, Color(0.27, 0.82, 0.32))  # 채움=녹색 / 깎임=어두운 회색(공용 헬퍼)
	# Player의 _ready 시점에 부모(Arena)가 아직 자식 setup 중이라 즉시 add_child 불가 → deferred 처리
	get_parent().add_child.call_deferred(_hp_bar)


func _create_weapon() -> void:
	# 장착 무기 = 형제 Sprite2D(몸 자식 X). 손잡이(WEAPON_GRIP)를 원점에 맞춰 회전 중심으로.
	_weapon = Sprite2D.new()
	_weapon.texture = WEAPON_TEXTURE
	_weapon.centered = true
	_weapon.offset = (WEAPON_TEXTURE.get_size() * 0.5) - WEAPON_GRIP  # 텍스처 중심 - 그립 → 그립이 원점
	_weapon.scale = Vector2(WEAPON_SCALE, WEAPON_SCALE)
	_weapon.z_index = z_index + WEAPON_Z_BEHIND  # 몸보다 뒤(주먹이 손잡이 덮음)
	_weapon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_weapon.visible = false
	get_parent().add_child.call_deferred(_weapon)


func _update_weapon() -> void:
	# 무기는 공격 모션 중에만 표시(현재 과도기). 위치=발끝+손앵커, 회전=스윙 트윈값.
	if _weapon == null:
		return
	var show_weapon: bool = _has_weapon and not _is_dead and (_is_attacking() or animation == "run")
	_weapon.visible = show_weapon
	if not show_weapon:
		return
	var off: Vector2 = _weapon_offset
	var sway: float = 0.0
	# run 중엔 무기에 생기를 준다 — 스프라이트 몸통이 거의 안 흔들려 절차적 바운스+흔들림(run 프레임에 위상 동기).
	if animation == "run" and _run_frame_count > 0:
		var phase: float = (float(frame) + frame_progress) / float(_run_frame_count) * TAU * RUN_BOB_CYCLES
		off.y += sin(phase) * RUN_BOB_AMP
		sway = sin(phase) * RUN_SWAY_AMP
	_weapon.position = position + off
	_weapon.rotation = _weapon_rot + sway


func _weapon_to_windup() -> void:
	# 공격 시작 — 무기를 와인드업 키프레임으로 스냅(트윈 없음, PC 포즈투포즈와 동일). 공격은 몸 뒤(손이 무기 위).
	_weapon_offset = WEAPON_WINDUP_OFFSET
	_weapon_rot = WEAPON_WINDUP_ROT
	if _weapon != null:
		_weapon.z_index = z_index + WEAPON_Z_BEHIND


func _weapon_to_strike() -> void:
	# 타격 프레임 — 타격 키프레임으로 스냅(트윈 없음). 몸 포즈가 strike 프레임으로 바뀌는 순간과 동기.
	_weapon_offset = WEAPON_STRIKE_OFFSET
	_weapon_rot = WEAPON_STRIKE_ROT


func _weapon_to_run() -> void:
	# 달리기 — 무기를 트레일링 자세로(오른손에 들고 뒤로 늘어뜨림). 바운스/흔들림은 _update_weapon이 절차적으로. 몸 앞(가까운 손).
	_weapon_offset = WEAPON_RUN_OFFSET
	_weapon_rot = WEAPON_RUN_ROT
	if _weapon != null:
		_weapon.z_index = z_index + WEAPON_Z_RUN


func _on_arena_resized() -> void:
	var arena: Control = get_parent()
	position.y = arena.size.y - PlayerData.Y_FROM_BOTTOM


func _on_animation_finished() -> void:
	# dead는 마지막 프레임에서 멈춰야 하므로 어떤 복귀도 안 함
	if _is_dead:
		return
	if animation == "attack" or animation == "attack_pose":
		var was: String = animation
		attack_motion_completed.emit()
		# 핸들러(데미지→처치→전진 등)가 모션을 바꿨으면 idle 복귀 안 함.
		# 한 방 처치 시 _on_player_attack_completed가 _enter_run→play_run 하므로 그땐 run 유지(idle로 안 덮음).
		if animation == was:
			_play("idle")
	elif animation == "attacked":
		_play("idle")
