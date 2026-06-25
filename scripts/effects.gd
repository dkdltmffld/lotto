class_name Effects
extends RefCounted

# 게임 내 시각 이펙트 함수 모음 (모두 static).
# 각 함수는 부모 노드(보통 Arena Control) 또는 대상 노드를 인자로 받아 자체 트윈을 돌리고 끝나면 자동 정리한다.

# --- 공용 빌더/트윈 헬퍼 (파일 내부 중복 제거, 2026-06-10 리팩토링) ---

static func _make_square(parent: Node, at_pos: Vector2, sz: float, color: Color, with_pivot: bool = true) -> ColorRect:
	# 중앙 정렬 정사각 ColorRect 생성+부착. with_pivot=false 는 shard/fragment(스케일 미사용) byte 보존용.
	var c := ColorRect.new()
	c.size = Vector2(sz, sz)
	c.position = at_pos - Vector2(sz * 0.5, sz * 0.5)
	c.color = color
	if with_pivot:
		c.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


static func _pop_fade_free(parent: Node, item: CanvasItem, end_scale: float, dur: float, eased_out: bool) -> void:
	# scale 확대 + 페이드 후 자동 free. eased_out=false 면 trans/ease 미설정(impact burst 의 기본 TRANS_LINEAR 보존).
	var tw := parent.create_tween().set_parallel(true)
	if eased_out:
		tw.tween_property(item, "scale", Vector2(end_scale, end_scale), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(item, "scale", Vector2(end_scale, end_scale), dur)
	tw.tween_property(item, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(item.queue_free)


static func _fly_fade_free(parent: Node, item: Control, velocity: Vector2, travel_mult: float, dur: float) -> void:
	# 직선 비행(감속) + 페이드 후 자동 free — 파편류 공용. (⚠️ CanvasItem 엔 position 프로퍼티가 없어 Control 타입)
	var end_pos: Vector2 = item.position + velocity * travel_mult
	var tw := parent.create_tween().set_parallel(true)
	tw.tween_property(item, "position", end_pos, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(item, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(item.queue_free)


static func _kill_meta_tween(node: Node, key: String, remove: bool) -> void:
	# meta 에 보관해 둔 트윈이 살아있으면 kill (remove=true 면 meta 키도 제거).
	if node.has_meta(key):
		var tw = node.get_meta(key)
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		if remove:
			node.remove_meta(key)


static func apply_label_shadow(l: Label, alpha: float = 0.75, off: int = 2) -> void:
	# 라벨 그림자(검정 alpha + offset) 3줄 패턴 공용. cut_in.gd 등 외부에서도 직접 호출.
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, alpha))
	l.add_theme_constant_override("shadow_offset_x", off)
	l.add_theme_constant_override("shadow_offset_y", off)


# --- 임팩트 burst (적 피격 시) ---

static func spawn_impact_burst(parent: Node, at_pos: Vector2, size: float = 20.0) -> void:
	# size로 자동공격(작게)/스킬(크게) 차등.
	var burst := _make_square(parent, at_pos, size, Color(1, 1, 1, 0.9))
	_pop_fade_free(parent, burst, 2.5, 0.25, false)


# --- 슬래시(베기) 호 — 포즈투포즈 공격에서 중간 동작을 가리는 더미 이펙트(2026-06-19) ---

static func spawn_slash(parent: Node, at_pos: Vector2, color: Color = Color(1, 1, 1, 0.95)) -> void:
	# 흰 호(arc) 스트로크 + 작은 코어 플래시. 절차적(에셋0). 빠르게 확장+페이드.
	# Line2D 는 Node2D — Control(Arena) 자식으로 붙어도 부모 좌표계에서 그려진다(PC 와 동일 공간).
	var line := Line2D.new()
	line.width = 7.0
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	var pts := PackedVector2Array()
	var r: float = 30.0
	var steps: int = 8
	for i in steps + 1:
		var a: float = lerpf(-1.0, 1.0, float(i) / float(steps))  # 위→아래로 베는 호
		pts.append(Vector2(cos(a), sin(a)) * r)
	line.points = pts
	line.position = at_pos
	line.scale = Vector2(0.5, 0.5)
	parent.add_child(line)
	var tw := parent.create_tween().set_parallel(true)
	tw.tween_property(line, "scale", Vector2(1.25, 1.25), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(line, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(line.queue_free)
	# 베는 시작점 작은 코어 플래시(타격감 보강)
	var core := _make_square(parent, at_pos, 16.0, color)
	_pop_fade_free(parent, core, 2.0, 0.18, true)


# --- 휘두름 궤적(스워시) — 칼이 위→아래로 쓸고 지나가는 초승달 트레일 + 잔상. 절차적(에셋0). ---

static func spawn_swing_trail(parent: Node, at_pos: Vector2, color: Color = Color(0.72, 0.92, 1.0, 0.9)) -> void:
	# at_pos = 회전 중심(PC 손/어깨 근처). 초승달 호가 그 점을 축으로 위→아래로 회전하며 페이드.
	# 2겹(두 번째는 더 흐리고 살짝 늦게) → 잔상(smear) 느낌.
	for s in 2:
		var a: float = color.a * (1.0 - 0.45 * float(s))
		_swing_arc(parent, at_pos, Color(color.r, color.g, color.b, a), 0.03 * float(s))


static func _swing_arc(parent: Node, at_pos: Vector2, color: Color, delay: float) -> void:
	var arc := Line2D.new()
	arc.width = 11.0
	arc.default_color = color
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	arc.joint_mode = Line2D.LINE_JOINT_ROUND
	# 가운데가 두껍고 끝이 가는 초승달(width_curve로 테이퍼).
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 0.15))
	wc.add_point(Vector2(0.5, 1.0))
	wc.add_point(Vector2(1.0, 0.15))
	arc.width_curve = wc
	var pts := PackedVector2Array()
	var r: float = 40.0
	var steps: int = 10
	for i in steps + 1:
		var ang: float = lerpf(-1.0, 1.0, float(i) / float(steps))  # 호 한 조각(약 ±57°)
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	arc.points = pts
	arc.position = at_pos
	arc.rotation = -0.8  # 시작 = 위로 들림
	arc.scale = Vector2(0.7, 0.7)
	arc.modulate.a = 0.0
	parent.add_child(arc)
	# 회전(휘두름) + 확장 (별도 트윈, modulate 와 프로퍼티 충돌 없음)
	var tmove := parent.create_tween().set_parallel(true)
	tmove.tween_property(arc, "rotation", 0.8, 0.16).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tmove.tween_property(arc, "scale", Vector2(1.25, 1.25), 0.16).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 알파: 등장 → 잠깐 유지 → 페이드 → free (단일 시퀀스)
	var tfade := parent.create_tween()
	if delay > 0.0:
		tfade.tween_interval(delay)
	tfade.tween_property(arc, "modulate:a", 1.0, 0.04)
	tfade.tween_interval(0.05)
	tfade.tween_property(arc, "modulate:a", 0.0, 0.10)
	tfade.tween_callback(arc.queue_free)


# --- 데미지 플로터 (피격: -n / 공격: n) ---

static func spawn_damage_floater(parent: Node, at_pos: Vector2, value: int, is_incoming: bool, big: bool = false) -> void:
	# big=true → 스크래치 스킬(버스트): 크게·금색·스케일 팝·더 높이. 자동공격은 big=false(작게).
	var floater := Label.new()
	var prefix: String = "-" if is_incoming else ""
	floater.text = "%s%d" % [prefix, value]
	var color: Color = UIPalette.DAMAGE_FLOATER_INCOMING if is_incoming else UIPalette.DAMAGE_FLOATER_OUTGOING
	if big and not is_incoming:
		color = UIPalette.DAMAGE_FLOATER_SKILL  # 스킬 버스트 = 밝은 빨강 강조(자동 빨강과 구분)
	floater.add_theme_color_override("font_color", color)
	apply_label_shadow(floater, 0.75)
	floater.add_theme_font_size_override("font_size", 36 if big else 22)
	floater.position = at_pos
	floater.pivot_offset = Vector2(18, 18)
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(floater)
	if big:
		floater.scale = Vector2(0.5, 0.5)
		var tp := parent.create_tween()
		tp.tween_property(floater, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tp.tween_property(floater, "scale", Vector2(1.0, 1.0), 0.1)
	var start_y: float = at_pos.y
	var rise: float = 52.0 if big else 36.0
	var tw := parent.create_tween().set_parallel(true)
	tw.tween_property(floater, "position:y", start_y - rise, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(floater, "modulate:a", 0.0, 0.5).set_delay(0.35)
	tw.chain().tween_callback(floater.queue_free)


static func screen_shake(node: CanvasItem, amplitude: float, duration: float = 0.22) -> void:
	# node.position을 무작위로 흔들었다 복귀(감쇠). 중첩 시 드리프트 방지 위해 진행 중이면 무시.
	# 일반 스킬=arena(전투영역만), 잭팟=화면 전체(game) 식으로 호출.
	if node.has_meta("_shake_base"):
		return
	var base: Vector2 = node.position
	node.set_meta("_shake_base", base)
	var tw := node.create_tween()
	node.set_meta("_shake_tween", tw)  # 외부(reset_shake)에서 명시 중단할 수 있게 보관
	var steps: int = 6
	for i in steps:
		var damp: float = 1.0 - float(i) / float(steps)
		var off := Vector2(randf_range(-amplitude, amplitude), randf_range(-amplitude, amplitude)) * damp
		tw.tween_property(node, "position", base + off, duration / float(steps))
	tw.tween_property(node, "position", base, duration / float(steps))
	tw.tween_callback(func() -> void:
		node.remove_meta("_shake_base")
		if node.has_meta("_shake_tween"):
			node.remove_meta("_shake_tween"))


static func reset_shake(node: CanvasItem) -> void:
	# 흔들기를 명시적으로 중단·복구. (사망 시 전역 트윈 kill을 제거했으므로, 흔들림 정지는 여기 책임.)
	# 진행 중 트윈을 kill하고 position을 원위치로 → 위치 영구 어긋남·흔들림 영구고장 방지.
	if node == null or not node.has_meta("_shake_base"):
		return
	_kill_meta_tween(node, "_shake_tween", true)
	node.position = node.get_meta("_shake_base")
	node.remove_meta("_shake_base")


# --- 스크래치 스킬 이펙트 (족보 count에 따라 차등, 전부 더미 = 절차적 도형) ---
# tier: 1(저)~4(잭팟). 코어 플래시 + 확장 링 + 방사 파편 + 고티어 화면 플래시. 추후 정식 스프라이트/파티클로 교체.

const _SKILL_COLORS: Array = [
	Color(0.5, 0.8, 1.0),   # tier1 청색
	Color(0.6, 1.0, 0.85),  # tier2 청록
	Color(1.0, 0.7, 0.3),   # tier3 주황
	Color(1.0, 0.9, 0.35),  # tier4 금색(잭팟)
]


static func _skill_tier(count: int) -> int:
	# ⚠️ cut_in._tier 와 임계 다름(5/3 vs 6/4) — 통합 금지 (이펙트/컷인 각각의 독립 튜닝 노브).
	if count >= 9:
		return 4
	if count >= 5:
		return 3
	if count >= 3:
		return 2
	return 1


static func spawn_skill_effect(parent: Node, at_pos: Vector2, count: int) -> void:
	var tier: int = _skill_tier(count)
	var color: Color = _SKILL_COLORS[tier - 1]
	_skill_core(parent, at_pos, 28.0 + tier * 14.0, color)
	for r in tier:
		_skill_ring(parent, at_pos, 26.0, 70.0 + tier * 36.0, color, 0.05 * r)
	var shards: int = 4 + tier * 4
	for i in shards:
		var ang: float = TAU * float(i) / float(shards) + randf_range(-0.12, 0.12)
		var spd: float = 70.0 + tier * 45.0 + randf_range(-20.0, 20.0)
		_skill_shard(parent, at_pos, Vector2.RIGHT.rotated(ang) * spd, color, 3.0 + tier)
	if tier >= 3:
		_skill_flash(parent, color, 0.10 * float(tier - 1))


static func _skill_core(parent: Node, at_pos: Vector2, size: float, color: Color) -> void:
	var c := _make_square(parent, at_pos, size, color)
	_pop_fade_free(parent, c, 2.2, 0.22, true)


static func _skill_ring(parent: Node, at_pos: Vector2, start_size: float, end_size: float, color: Color, delay: float) -> void:
	# 모서리를 둥글게(반지름=절반) 한 테두리 Panel → 확장하면 링(고리)처럼 보인다.
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(start_size * 0.5))
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(start_size, start_size)
	p.position = at_pos - Vector2(start_size * 0.5, start_size * 0.5)
	p.pivot_offset = Vector2(start_size * 0.5, start_size * 0.5)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var target: float = end_size / start_size
	var tw := parent.create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector2(target, target), 0.3).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 0.0, 0.3).set_delay(delay)
	tw.chain().tween_callback(p.queue_free)


static func _skill_shard(parent: Node, start_pos: Vector2, velocity: Vector2, color: Color, size: float) -> void:
	var f := _make_square(parent, start_pos, size, color, false)
	_fly_fade_free(parent, f, velocity, 0.5, 0.4)


static func _skill_flash(parent: Node, color: Color, strength: float) -> void:
	# 부모 영역(전투 영역)을 잠깐 색으로 덮었다 페이드 — 고티어/잭팟 한정.
	var f := ColorRect.new()
	f.color = Color(color.r, color.g, color.b, clampf(strength, 0.0, 1.0))
	f.anchor_right = 1.0
	f.anchor_bottom = 1.0
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(f)
	var tw := parent.create_tween()
	tw.tween_property(f, "modulate:a", 0.0, 0.25)
	tw.tween_callback(f.queue_free)


# --- 적 사망 폭발 (코어 + 방사형 파편) ---

const _EXPLOSION_FRAGMENT_COUNT: int = 12
const _EXPLOSION_FRAGMENT_COLORS: Array = [
	Color(1.0, 0.85, 0.3),
	Color(1.0, 0.55, 0.2),
	Color(0.9, 0.3, 0.2),
]

static func spawn_explosion(parent: Node, at_pos: Vector2) -> void:
	_spawn_explosion_core(parent, at_pos)
	for i in _EXPLOSION_FRAGMENT_COUNT:
		var angle: float = TAU * float(i) / float(_EXPLOSION_FRAGMENT_COUNT) + randf_range(-0.15, 0.15)
		var speed: float = randf_range(70.0, 130.0)
		var velocity: Vector2 = Vector2.RIGHT.rotated(angle) * speed
		_spawn_explosion_fragment(parent, at_pos, velocity)


static func _spawn_explosion_core(parent: Node, at_pos: Vector2) -> void:
	var core := _make_square(parent, at_pos, 36.0, Color(1.0, 0.92, 0.4))
	_pop_fade_free(parent, core, 2.8, 0.3, true)


static func _spawn_explosion_fragment(parent: Node, start_pos: Vector2, velocity: Vector2) -> void:
	# ⚠️ RNG 순서 보존: 크기(randf_range) 먼저 → 색(randi) 다음 (인자 좌→우 평가).
	var s: float = randf_range(4.0, 8.0)
	var frag := _make_square(parent, start_pos, s, _EXPLOSION_FRAGMENT_COLORS[randi() % _EXPLOSION_FRAGMENT_COLORS.size()], false)
	_fly_fade_free(parent, frag, velocity, 0.6, 0.6)


# 화면 중앙 족보 결과 텍스트("value X count !!!")·JACKPOT 태그는 NotificationManager.hand_result 로 이전(2026-06-11
# 토스트 매니저 통합) — Effects 는 임팩트 버스트·플로터·스킬 이펙트·화면 흔들림 등 전투 연출만 담당.


# --- 캐릭터 피격 플래시 (modulate를 잠깐 색으로 → 복귀) ---

static func flash_modulate(node: CanvasItem, flash_color: Color, peak: float = 0.05, recover: float = 0.2) -> void:
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", flash_color, peak)
	tw.tween_property(node, "modulate", Color(1, 1, 1), recover)
