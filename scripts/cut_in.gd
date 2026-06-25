class_name CutIn
extends Control

# 고족보 컷인 연출 (던파 2차각성 컷인 느낌 — 더미 placeholder).
# game.gd가 인스턴스 1개를 만들어 전체화면 오버레이로 두고, 스크래치 스킬이 고족보일 때 play(count) 호출.
# 구성(전부 절차적 더미): 어두운 배경 → 사선 컬러 밴드 + 스피드라인 → 일러스트 슬라이드인(오버슈트) → 화이트 플래시 → 정점 유지 → 슬라이드아웃·페이드.
# 일러스트: @export illustration 있으면 사용, 없으면 PC idle 첫 프레임을 placeholder로(영웅 컷인 느낌).
# ⚠️ 더미 — 실제 일러스트/연출은 추후 교체. 트리거 임계는 game.gd CUTIN_MIN_COUNT. 게임을 멈추지 않음(방치 계속).

signal finished  # 컷인 재생 완료(정리·페이드 끝). game.gd가 await해 화면 멈춤을 해제한다.

@export var illustration: Texture2D = null  # 실제 컷인 일러스트(없으면 PC placeholder)
# illustration 미지정 시 이 경로에 파일이 있으면 자동 사용. 파일만 떨궈놓으면 됨(README 참고).
const ILLUSTRATION_PATH := "res://assets/cutin/cutin.png"

const HOLD := 0.45          # 정점 유지(초). 화면 멈춤 길이에 직결 — 너무 길면 방치 피로. (속도 튜닝 노브)
const CUTIN_CENTER_Y := 270.0  # 일러스트/밴드 세로 중심(디자인 360×780 기준). 작을수록 위로. (위치 튜닝 노브)
const FADE_IN := 0.09
const FADE_OUT := 0.18
const _TIER_COLORS := [
	Color(0.55, 0.80, 1.00),  # tier1 청
	Color(0.60, 1.00, 0.85),  # tier2 청록
	Color(1.00, 0.70, 0.30),  # tier3 주황
	Color(1.00, 0.88, 0.35),  # tier4 금(잭팟)
]
const _TIER_LABEL := ["", "", "FOUR!", "JACKPOT!"]  # placeholder 문구(더미)

var _busy: bool = false
var _placeholder_tex: Texture2D = null


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 입력 통과
	z_index = 200                               # 모든 UI 위에
	process_mode = Node.PROCESS_MODE_ALWAYS     # get_tree().paused(화면 멈춤) 중에도 컷인은 재생
	visible = false
	# 실제 일러스트가 경로에 있으면 자동 사용(export로 직접 지정 시 그게 우선).
	if illustration == null and ResourceLoader.exists(ILLUSTRATION_PATH):
		illustration = load(ILLUSTRATION_PATH)
	_placeholder_tex = _load_placeholder()


func is_playing() -> bool:
	return _busy


func _load_placeholder() -> Texture2D:
	# PC idle 첫 프레임(256×256)을 placeholder 일러스트로. 실패하면 null(색 패널로 폴백).
	var path: String = PlayerData.ANIMATIONS["idle"]["path"]
	if not ResourceLoader.exists(path):
		return null
	var sheet: Texture2D = load(path)
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(0, 0, PlayerData.FRAME_SIZE, PlayerData.FRAME_SIZE)
	return at


func _tier(count: int) -> int:
	# ⚠️ effects._skill_tier 와 임계 다름(6/4 vs 5/3) — 통합 금지 (이펙트/컷인 각각의 독립 튜닝 노브).
	if count >= 9:
		return 4
	if count >= 6:
		return 3
	if count >= 4:
		return 2
	return 1


func play(count: int) -> bool:
	# 컷인 1회 재생. 이미 재생 중이거나 트리 밖이면 시작 안 함 → false 반환.
	# ⚠️ 반환값 필수: 호출부(game)가 false면 finished를 await하지 않게 해 pause 영구 고착(프리징)을 구조적으로 차단.
	if _busy or not is_inside_tree():
		return false
	_busy = true
	visible = true
	var tier: int = _tier(count)
	var color: Color = _TIER_COLORS[tier - 1]
	var intensity: float = 0.6 + 0.12 * float(tier)  # 티어 높을수록 강하게

	var parts: Array[Node] = []

	# 1) 어두운 배경
	var backdrop := _fullscreen_rect(Color(0, 0, 0, 0), parts)
	var tb := create_tween()
	tb.tween_property(backdrop, "color:a", 0.55, FADE_IN)
	tb.tween_interval(HOLD)
	tb.tween_property(backdrop, "color:a", 0.0, FADE_OUT)

	# 2) (사선 컬러 밴드 제거됨 — 일러스트가 가로 꽉 차서 뒤 노란 박스가 거슬려 삭제. 필요 시 복원.)

	# 3) 스피드라인 (사선 가는 막대들이 좌→우로 스쳐감)
	for i in (3 + tier):
		_speed_line(color, i, 3 + tier, parts)

	# 4) 일러스트 등장 — self 직속 + 디자인좌표(360×780). 가로 꽉(폭 360) + 텍스처 비율 유지 높이.
	#    (중첩 Control 자식 렌더 불가·pause 중 modulate 트윈 불가 회피: self 직속 + scale 연출만.)
	var has_art: bool = illustration != null
	var tex: Texture2D = illustration if has_art else _placeholder_tex
	var tex_size: Vector2 = tex.get_size() if tex != null else Vector2(256.0, 256.0)
	var disp_w: float = 360.0  # 가로 꽉(디자인 폭)
	var disp_h: float = disp_w * tex_size.y / maxf(1.0, tex_size.x)  # 비율 유지 높이
	var ox: float = 0.0
	var oy: float = CUTIN_CENTER_Y - disp_h * 0.5
	var pivot := Vector2(disp_w * 0.5, disp_h * 0.5)
	var arts: Array[Control] = []      # 등장 연출(scale) 공통 적용 대상
	if not has_art:
		# placeholder일 때만 뒤에 어두운 카드(투명 PC 스프라이트가 또렷하게). 실제 일러스트는 raw(슬롯 없음).
		var pan := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.08, 0.11, 0.88)
		sb.border_color = color
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(8)
		pan.add_theme_stylebox_override("panel", sb)
		pan.position = Vector2(ox, oy)
		pan.size = Vector2(disp_w, disp_h)
		pan.pivot_offset = pivot
		pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pan)
		parts.append(pan)
		arts.append(pan)
	if tex != null:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE  # 박스 비율=텍스처 비율이라 왜곡 없이 가로 꽉
		pic.position = Vector2(ox, oy)
		pic.size = Vector2(disp_w, disp_h)
		pic.pivot_offset = pivot
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pic)
		parts.append(pic)
		arts.append(pic)
	# placeholder 문구(더미) — placeholder일 때만(실제 일러스트엔 더미 글자 안 겹치게). tier3↑
	if not has_art and _TIER_LABEL[tier - 1] != "":
		var lbl := Label.new()
		lbl.text = _TIER_LABEL[tier - 1]
		lbl.position = Vector2(ox, oy + disp_h + 6.0)
		lbl.size = Vector2(disp_w, 40.0)
		lbl.pivot_offset = Vector2(disp_w * 0.5, 20.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", color)
		Effects.apply_label_shadow(lbl, 0.85)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)
		parts.append(lbl)
		arts.append(lbl)
	# 등장: scale 팝 / 퇴장: 살짝 확대.
	# ⚠️ 페이드(modulate:a 트윈)는 화면 멈춤(get_tree().paused) 중 안 도므로 쓰지 않는다(scale은 동작).
	#    band/backdrop는 color:a라 멈춤 중에도 페이드됨 — 그쪽이 들고남을 커버.
	for a in arts:
		a.scale = Vector2(0.88, 0.88)
		var ta := create_tween()
		ta.tween_property(a, "scale", Vector2(1.0, 1.0), 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ta.tween_interval(HOLD)
		ta.tween_property(a, "scale", Vector2(1.05, 1.05), FADE_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 5) 화이트 플래시 (펀치인 순간)
	var flash := _fullscreen_rect(Color(1, 1, 1, clampf(intensity, 0.0, 0.85)), parts)
	var tf := create_tween()
	tf.tween_interval(0.06)
	tf.tween_property(flash, "color:a", 0.0, 0.22)

	# 6) 종료: 전체 시간 후 정리 + busy 해제
	var total: float = FADE_IN + 0.22 + HOLD + FADE_OUT + 0.06
	var tend := create_tween()
	tend.tween_interval(total)
	tend.tween_callback(func() -> void:
		for p in parts:
			if is_instance_valid(p):
				p.queue_free()
		visible = false
		_busy = false
		finished.emit()
	)
	return true  # 재생 시작됨 → 호출부가 finished를 await해도 안전(tend 콜백이 반드시 emit).


func _fullscreen_rect(c: Color, parts: Array[Node]) -> ColorRect:
	# 풀스크린 ColorRect 셋업 공용(backdrop/flash). 트윈은 호출부 책임.
	# (effects._skill_flash 는 static·외부 parent·자체 free 트윈이라 통합 금지 — 여기 인스턴스 전용.)
	var rect := ColorRect.new()
	rect.color = c
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	parts.append(rect)
	return rect


func _speed_line(color: Color, idx: int, total: int, parts: Array[Node]) -> void:
	var line := ColorRect.new()
	var w: float = 90.0
	line.size = Vector2(w, 4.0)
	line.color = Color(color.r, color.g, color.b, 0.0)
	line.rotation = deg_to_rad(-12.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var y: float = 60.0 + float(idx) / float(total) * 460.0
	line.position = Vector2(-w, y)
	add_child(line)
	parts.append(line)
	var delay: float = 0.02 * idx
	var tw := create_tween().set_parallel(true)
	tw.tween_property(line, "position:x", 460.0, 0.3).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(line, "color:a", 0.5, 0.1).set_delay(delay)
	tw.chain().tween_property(line, "color:a", 0.0, 0.18)
