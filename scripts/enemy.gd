class_name Enemy
extends Control

signal died
signal attacked_player(damage: int)

@export var max_hp: int = 120
@export var attack_interval: float = 2.0
@export var attack_damage: int = 10
@export var attack_windup: float = 0.4
@export var is_boss: bool = false  # 보스만 PC를 공격(start_attacking 호출). 일반 몹은 위협 X
@export var variant: String = ""   # 외형 변종 id(폴더명). 비우면 스폰 시 무작위 선택.
@export var tint_override: Color = Color(1, 1, 1, 1)  # 외형 색 덮어쓰기(보스 틴트보다 우선 — 던전 빨강 등). 흰색=없음.

# ── 외형 변종 ──────────────────────────────────────────────────────────────
# 스탯·타이밍은 그대로 두고 외형(스프라이트)만 무작위로 바꾼다. 외형은 폴더로 구분:
#   assets/sprites/enemies/<id>/<id>_idle.png , <id>_attack.png   (가로 스트립)
# 의도된 변종 목록(VARIANTS) 중 **실제 로드 가능한 것만** 추려 무작위 선택 →
# 폴더를 추가하고 여기에 id만 더하면 자동 합류. (웹 export 안전: DirAccess 스캔 대신 명시 경로)
#
# 프레임 규격: **폭=256 고정, 높이는 시트마다 다를 수 있음**(idle 256 / attack 256·320 등).
#   프레임 수 = 시트 width / FRAME_W.
# 정렬 + 크기 정규화: 시트마다 ①캐릭터가 프레임 내 어디에 있고(위/아래 패딩) ②얼마나 크게
#   그려졌는지가 **제각각**이다(같은 몬스터인데 idle↔attack 크기·위치가 다름). →
#   시트를 스캔해 **발끝**(불투명 최하단)과 **대표 캐릭터 높이**(프레임별 높이 중앙값)를 구하고,
#   **idle을 기준 크기**로 삼아 attack을 같은 크기로 scale 보정 + 발끝을 공통 바닥선에 정렬한다.
#   (몬스터 간 고유 크기는 유지, 같은 몬스터의 idle↔attack만 일치) — 무손실 임포트라 웹 안전.
const ENEMY_DIR: String = "res://assets/sprites/enemies/"
const FRAME_W: int = 256
const BASE_SPRITE_SCALE: float = 0.35  # enemy.tscn Sprite 기준 스케일(정규화 norm을 여기 곱한다)
const BASE_FEET_LOCAL: float = 128.0   # 발끝이 놓일 sprite 로컬 y(=BASE_H/2; centered 256프레임 하단)
const IDLE_SPEED: float = 8.0          # idle 재생 속도(고정). attack은 windup에 맞춰 자동 계산.
const BOSS_PIVOT := Vector2(25, 88.8)  # 보스 확대 시 발밑 기준 pivot(로컬 25,44 + 반높이≈44.8)

# 시트 스캔(발끝·캐릭터 높이 → {feet, char_h})은 sprite_scan.gd 공용 유틸 — 경로|프레임폭 1회 캐시.
const SpriteScanLib := preload("res://scripts/sprite_scan.gd")

static var _last_variant: String = ""  # 직전 스폰 외형(연속 중복 회피용, 인스턴스 공유)

# 외형 변종 카탈로그. data/enemies.json (원본 data/src/enemies.yaml, 변환 tools/build_data.gd).
# 폴더만 추가하고 yaml 에 id 만 더하면 자동 합류 (로드 가능한 것만 _variant_ok 로 추려짐).
static var _variants: Array = []
static var _variants_loaded: bool = false


static func _variant_catalog() -> Array:
	if not _variants_loaded:
		_variants_loaded = true
		var v: Variant = GameData.table("enemies").get("variants", [])
		_variants = v if v is Array else []
		if _variants.is_empty():
			_variants = ["mon_001"]  # 최후 폴백
	return _variants

var current_hp: int
var is_dead: bool = false
var is_attacking: bool = false  # PC가 조우 위치에 도착해서 전투가 시작된 이후 true
var attack_timer: float = 0.0
var _attacking_now: bool = false  # 공격 모션(windup) 진행 중 — interval≤windup이어도 코루틴 중첩 방지
var _base_modulate: Color = Color(1, 1, 1)  # 평상시 sprite 색(보스는 더미 틴트). 피격 플래시 후 이 색으로 복귀
var _anim_render: Dictionary = {}           # anim_name -> {"scale": float, "offset_y": float}

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hp_bar: ProgressBar = $HPBar


func _ready() -> void:
	current_hp = max_hp
	attack_timer = attack_interval
	UISkin.style_hp_bar(hp_bar, Color(0.85, 0.27, 0.24))  # 채움=빨강 / 깎임=어두운 회색(공용 헬퍼)
	_build_animations(_resolve_variant())
	sprite.animation_finished.connect(_on_anim_finished)
	_play_anim("idle")
	if is_boss:
		# 보스 더미 외형: 크게 + 보라 틴트로 일반 몹과 구분 (placeholder, 추후 보스 전용 아트)
		# 발밑(스프라이트 하단) 기준으로 확대 → 몹과 같은 바닥선 유지.
		# 스프라이트 로컬 (25,44) + 반높이(256×0.35/2≈44.8) → 발끝 y≈88.8
		pivot_offset = BOSS_PIVOT
		scale = Vector2(1.8, 1.8)
		_base_modulate = Color(0.6, 0.25, 0.95)
		sprite.modulate = _base_modulate
	# 색 덮어쓰기(던전 등): 보스 틴트보다 우선. 평상시 색·피격 복귀색이 모두 이 색이 된다.
	if tint_override != Color(1, 1, 1, 1):
		_base_modulate = tint_override
		sprite.modulate = _base_modulate
	_refresh_ui()


# ── 변종 선택 / 애니메이션 빌드 ────────────────────────────────────────────

func _resolve_variant() -> String:
	# 명시된 variant가 있고 로드 가능하면 그것, 아니면 로드 가능한 변종 중 무작위.
	if variant != "" and _variant_ok(variant):
		_last_variant = variant
		return variant
	var avail: Array = _available_variants()
	if avail.is_empty():
		return _variant_catalog()[0]  # 최후 폴백(아무 것도 못 찾으면 첫 변종 — 로드 단계에서 다시 막힐 수 있음)
	# 직전 외형 제외 → 같은 몬스터가 연속해서 나오지 않게(2종 이상일 때만 가능).
	var pool: Array = avail
	if avail.size() > 1 and _last_variant != "":
		pool = avail.filter(func(id): return id != _last_variant)
		if pool.is_empty():
			pool = avail
	var chosen: String = pool[randi() % pool.size()]
	_last_variant = chosen
	return chosen


func _available_variants() -> Array:
	var out: Array = []
	for id in _variant_catalog():
		if _variant_ok(id):
			out.append(id)
	return out


static func pick_variant() -> String:
	# 한 웨이브 전체에 쓸 외형 1개를 무작위로 선택(로드 가능한 변종 중, 직전 외형 회피). game.gd가 호출.
	var avail: Array = []
	for id in _variant_catalog():
		var idle_p: String = "%s%s/%s_idle.png" % [ENEMY_DIR, id, id]
		var atk_p: String = "%s%s/%s_attack.png" % [ENEMY_DIR, id, id]
		if ResourceLoader.exists(idle_p) and ResourceLoader.exists(atk_p):
			avail.append(id)
	if avail.is_empty():
		var cat: Array = _variant_catalog()
		return str(cat[0]) if not cat.is_empty() else "mon_001"
	var pool: Array = avail
	if avail.size() > 1 and _last_variant != "":
		pool = avail.filter(func(x): return str(x) != _last_variant)
		if pool.is_empty():
			pool = avail
	var chosen: String = str(pool[randi() % pool.size()])
	_last_variant = chosen
	return chosen


func _variant_ok(id: String) -> bool:
	# idle/attack 두 시트가 모두 임포트돼 로드 가능한 변종만 유효.
	return ResourceLoader.exists(_sheet_path(id, "idle")) and ResourceLoader.exists(_sheet_path(id, "attack"))


func _sheet_path(id: String, anim: String) -> String:
	return "%s%s/%s_%s.png" % [ENEMY_DIR, id, id, anim]


func _build_animations(id: String) -> void:
	var sf := SpriteFrames.new()
	# idle을 "기준 크기"로 삼아 attack을 거기에 맞춘다(같은 몬스터 idle↔attack 크기 일치).
	var idle_scan: Dictionary = SpriteScanLib.scan_sheet(load(_sheet_path(id, "idle")), FRAME_W)
	var base_char_h: int = int(idle_scan.get("char_h", -1))
	_add_anim(sf, id, "idle", true, base_char_h)
	_add_anim(sf, id, "attack", false, base_char_h)
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sprite.sprite_frames = sf


func _add_anim(sf: SpriteFrames, id: String, anim: String, loop: bool, base_char_h: int) -> void:
	# 변종 시트 1개를 가로 스트립(폭 256, 높이=시트 높이)으로 잘라 프레임 추가 +
	# 크기 정규화(scale) + 발끝 정렬(offset)을 계산해 _anim_render에 저장.
	var tex: Texture2D = load(_sheet_path(id, anim))
	var h: int = tex.get_height()
	var n: int = max(1, int(tex.get_width() / FRAME_W))
	var scan: Dictionary = SpriteScanLib.scan_sheet(tex, FRAME_W)
	# norm = 기준 캐릭터 높이 / 이 시트 캐릭터 높이. 같은 화면 크기가 되도록 scale 보정.
	var norm: float = 1.0
	if base_char_h > 0 and int(scan.get("char_h", -1)) > 0:
		norm = float(base_char_h) / float(scan["char_h"])
	var sc: float = BASE_SPRITE_SCALE * norm
	# 발끝(feet)을 화면상 고정 위치에 두는 offset (scale 보정 후에도 바닥선 일치).
	# 발끝 로컬 y = feet - h/2 + offset = BASE_FEET_LOCAL/norm  →  화면 발끝 = 그 값 × sc = 상수.
	var off_y: float = 0.0
	var feet: int = int(scan.get("feet", -1))
	if feet >= 0:
		off_y = BASE_FEET_LOCAL / norm - float(feet) + float(h) / 2.0
	_anim_render[anim] = {"scale": sc, "offset_y": off_y}
	sf.add_animation(anim)
	sf.set_animation_loop(anim, loop)
	for i in n:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, h)
		sf.add_frame(anim, atlas)
	# attack은 windup 시간에 맞춰 끝나도록 speed 자동 계산(프레임 수 무관 — 연출이 데미지 시점에 동기).
	if anim == "attack":
		var dur: float = max(0.05, attack_windup)
		sf.set_animation_speed(anim, float(n) / dur)
	else:
		sf.set_animation_speed(anim, IDLE_SPEED)


func _play_anim(anim: String) -> void:
	# 재생 + 시트별 크기 정규화(scale) + 발끝 정렬(offset) 적용.
	SpriteScanLib.apply_render(sprite, anim, _anim_render, BASE_SPRITE_SCALE)


func _on_anim_finished() -> void:
	# 공격 모션(1회)이 끝나면 대기로 복귀
	if is_dead:
		return
	if sprite.animation == "attack":
		_play_anim("idle")


# ── 전투 ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if is_dead or not is_attacking:
		return
	attack_timer -= delta
	if attack_timer <= 0.0 and not _attacking_now:
		attack_timer = attack_interval
		_perform_attack()


func start_attacking() -> void:
	# PC가 조우 위치에 도착해 idle 진입 시 game.gd가 호출한다.
	is_attacking = true
	attack_timer = attack_interval
	_attacking_now = false


func _perform_attack() -> void:
	_attacking_now = true
	_play_anim("attack")
	# 잽 모션: 플레이어 쪽(좌측)으로 살짝 튀어나갔다 복귀
	var origin_x: float = position.x
	var lunge_out: float = attack_windup * 0.4
	var lunge_back: float = attack_windup * 0.6
	var tw := create_tween()
	tw.tween_property(self, "position:x", origin_x - 8.0, lunge_out).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:x", origin_x, lunge_back).set_ease(Tween.EASE_OUT)
	# 공격 모션 종료 시점(잽+복귀 완료)에 데미지. **데미지 타이밍은 attack_windup 고정** — 외형/프레임 수 무관.
	await get_tree().create_timer(attack_windup).timeout
	_attacking_now = false
	if is_dead:
		return
	attacked_player.emit(attack_damage)


func take_damage(amount: int) -> void:
	if is_dead:
		return
	current_hp -= amount
	if current_hp <= 0:
		current_hp = 0
		is_dead = true
		_refresh_ui()
		died.emit()
	else:
		_refresh_ui()
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(1.6, 0.5, 0.5), 0.05)
		tw.tween_property(sprite, "modulate", _base_modulate, 0.15)


func _refresh_ui() -> void:
	hp_bar.value = float(current_hp) / float(max_hp) * 100.0
