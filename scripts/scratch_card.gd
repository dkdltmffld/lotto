extends Control
class_name ScratchCard

signal card_completed(result: Dictionary)

# 칸을 덮는 코팅 이미지. 칸마다 같은 이미지를 subdivisions_per_cell² 조각(AtlasTexture)으로 잘라 덮고, 긁으면 조각이 사라진다.
const COATING_TEX: Texture2D = preload("res://assets/ui/scratch.png")

@export var grid_cols: int = 3
@export var grid_rows: int = 3
@export var number_min: int = 1
@export var number_max: int = 9
@export var brush_radius: float = 30.0
@export_range(0.0, 1.0, 0.05) var completion_threshold: float = 0.7
# 추가 완성 조건(OR): 칸 가운데 영역(숫자가 그려진 곳)이 다 긁히면 전체 임계 미달이어도 완성.
# "숫자가 다 보이는데 완성 안 됨" 해소 — 가운데만 긁어도 됨. 0이면 비활성(기존 임계만).
# 값 = 가운데 정사각 영역의 한 변 비율(0.5 = 칸 중앙 50% 영역). 브러시가 이보다 크면 한 번에 클리어.
@export_range(0.0, 1.0, 0.05) var center_complete_ratio: float = 0.5
@export var subdivisions_per_cell: int = 10
@export var cell_padding: float = 4.0

var numbers: Array[int] = []

# 숫자 분포(집합/가중치). 비어 있으면 number_min~number_max 균등 추첨(하위 호환).
# 런타임 변경: set_number_weights({값:가중치}) / set_number_pool([값…]) / set_number_range(min,max).
# 변경은 다음 카드(new_card)부터 반영된다. (강화/등급 연동 훅)
var _number_weights: Dictionary = {}      # {int 숫자 : float 가중치}
var _weighted_values: Array[int] = []     # 추첨 캐시: 후보 값(가중치 양수만)
var _weighted_cum: Array[float] = []      # 추첨 캐시: 누적 가중치
var _weight_total: float = 0.0

var cells: Array = []
var _center_sub_indices: Array[int] = []  # 가운데 완성 판정용 서브셀 인덱스(geometry 동일이라 전 칸 공용, _build_cells에서 1회 계산)
var is_locked: bool = false
var _cell_tweens: Array = []  # 진행 중 셀 완성 연출 트윈(페이드/플래시/펑) — new_card 시 중단(한 방 죽음 후 잔재가 새 카드 덮는 버그 방지)

# ④ 와일드(유물): 카드마다 일부 칸을 와일드(★)로 — 어떤 숫자로도 취급(최대 그룹 합류=매칭+1).
# game.gd가 장착된 wild 유물의 발생확률 배열·상한을 넣는다. 발동은 new_card에서 카드마다 재추첨.
var wild_chances: Array = []   # [float] 유물별 발생 확률
var wild_cap: int = 0          # 와일드 칸 상한(여러 유물이어도)
var wild_cells: Array = []     # 이번 카드의 와일드 칸 인덱스
var _grid_size: Vector2 = Vector2.ZERO  # 격자 빌드·입력 판정에 쓰는 기준 크기(웹 anchor size=0 문제 회피용으로 명시 지정)

# 자동 긁기(방치): 입력이 없어도 초당 auto_rate 칸씩 자동 공개. game.gd가 복권 성장(자동 긁기 속도)값으로 설정.
var auto_rate: float = 0.0   # 칸/초 (0이면 자동 OFF)
var _auto_accum: float = 0.0
# 수동 조작 중/직후엔 자동 긁기 정지. 마지막 수동 입력 후 이 시간(초)이 지나야 자동 재개.
const AUTO_RESUME_DELAY: float = 2.0
var _manual_cooldown: float = 0.0


# 격자 생성은 game.gd가 configure()로 크기를 명시해 호출한다.
# (웹에서는 anchor 기반 size가 계속 0으로 남아 self-측정이 불가 → 레이아웃 상수로 직접 지정)
func _ready() -> void:
	pass


func _process(delta: float) -> void:
	# 자동 긁기: 잠금이 아니고 자동 속도가 있으면 한 칸씩 자동 공개.
	if is_locked or auto_rate <= 0.0 or cells.is_empty():
		return
	# 수동 조작 직후 AUTO_RESUME_DELAY 동안은 자동 정지 (조작 종료 후에야 재개)
	if _manual_cooldown > 0.0:
		_manual_cooldown -= delta
		_auto_accum = 0.0  # 재개 시 누적분이 한꺼번에 터지지 않도록 리셋
		return
	_auto_accum += delta
	var interval: float = 1.0 / auto_rate
	var did: bool = false
	while _auto_accum >= interval:
		_auto_accum -= interval
		var idx: int = _first_incomplete()
		if idx < 0:
			break
		var sub_total: int = _sub_total()
		cells[idx].scratched_count = sub_total
		_finish_cell(idx)
		did = true
	if did and _all_completed():
		_complete()


func _first_incomplete() -> int:
	for i in cells.size():
		if not cells[i].completed:
			return i
	return -1


func configure(grid_size: Vector2) -> void:
	if grid_size.x < 1.0 or grid_size.y < 1.0:
		grid_size = Vector2(260, 240)  # 안전 폴백
	_grid_size = grid_size
	# 카드 자체 크기도 명시(입력 히트 역역이 잡히도록). anchor는 top-left 고정(scratch_card.tscn).
	custom_minimum_size = grid_size
	size = grid_size
	_clear_cells()
	_build_cells()
	new_card()


func _clear_cells() -> void:
	for c in cells:
		var root = c.get("root")
		if is_instance_valid(root):
			root.queue_free()
	cells.clear()


func reset_card() -> void:
	is_locked = false
	new_card()


func _cell_geometry() -> Dictionary:
	# 격자 셀/서브셀 치수 — _build_cells(렌더)와 _scratch_at(히트 판정)이 동일 수식을 써야 하므로 단일 출처로.
	# 레이아웃 상수 변경 시 한 곳만 고치면 렌더/입력이 같이 따라온다.
	var cell_w: float = _grid_size.x / float(grid_cols)
	var cell_h: float = _grid_size.y / float(grid_rows)
	return {
		"cell_w": cell_w,
		"cell_h": cell_h,
		"sub_w": (cell_w - cell_padding * 2) / float(subdivisions_per_cell),
		"sub_h": (cell_h - cell_padding * 2) / float(subdivisions_per_cell),
	}


func _sub_total() -> int:
	# 셀당 서브셀 총 개수(subdivisions_per_cell²). 자동 공개·완료 임계 계산 공용.
	return subdivisions_per_cell * subdivisions_per_cell


func _cell_origin(i: int, cell_w: float, cell_h: float) -> Vector2:
	# 셀 인덱스 → 좌상단 좌표(행/열 분해, 정수 나눗셈). _build_cells(렌더)/_scratch_at(히트 판정) 단일 출처.
	var row: int = i / grid_cols
	var col: int = i % grid_cols
	return Vector2(col * cell_w, row * cell_h)


func _compute_center_indices() -> void:
	# 가운데 정사각 영역(center_complete_ratio)에 중심이 들어오는 서브셀 인덱스 수집.
	# 이 영역이 다 긁히면(브러시가 크면 한 번에) 칸을 완성으로 본다. ratio=0 이면 비활성(빈 배열).
	_center_sub_indices.clear()
	if center_complete_ratio <= 0.0:
		return
	var half: float = center_complete_ratio * 0.5
	var n: int = subdivisions_per_cell
	for sy in n:
		for sx in n:
			var fx: float = (sx + 0.5) / float(n)
			var fy: float = (sy + 0.5) / float(n)
			if abs(fx - 0.5) <= half and abs(fy - 0.5) <= half:
				_center_sub_indices.append(sy * n + sx)


func _center_cleared(c) -> bool:
	# 가운데 영역 서브셀이 전부 긁혔으면(보이지 않으면) true. 영역 비면 false(비활성).
	if _center_sub_indices.is_empty():
		return false
	for idx in _center_sub_indices:
		if c.sub_cells[idx].visible:
			return false
	return true


func _build_cells() -> void:
	_compute_center_indices()
	var geo := _cell_geometry()
	var cell_w: float = geo["cell_w"]
	var cell_h: float = geo["cell_h"]
	var sub_w: float = geo["sub_w"]
	var sub_h: float = geo["sub_h"]
	var cell_count: int = grid_cols * grid_rows

	for i in cell_count:
		var cell := Control.new()
		cell.position = _cell_origin(i, cell_w, cell_h)
		cell.size = Vector2(cell_w, cell_h)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cell)

		# 뒤(긁어낸 후) 숫자 칸. scratch.png 코팅 타일과 프레임을 맞추려고 테두리 있는 타일로.
		var bg := Panel.new()
		bg.position = Vector2(cell_padding, cell_padding)
		bg.size = Vector2(cell_w - cell_padding * 2, cell_h - cell_padding * 2)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.95, 0.92, 0.83)
		bg_style.border_color = Color(0.11, 0.11, 0.17)
		bg_style.set_border_width_all(3)
		bg_style.set_corner_radius_all(2)
		bg.add_theme_stylebox_override("panel", bg_style)
		cell.add_child(bg)

		var label := Label.new()
		label.position = Vector2.ZERO
		label.size = Vector2(cell_w, cell_h)
		label.pivot_offset = Vector2(cell_w * 0.5, cell_h * 0.5)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 32)
		label.add_theme_color_override("font_color", Color(0.18, 0.14, 0.10))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(label)

		# 코팅 이미지를 셀마다 subdivisions_per_cell² 조각으로 슬라이스 (AtlasTexture region). 같은 이미지가 9칸 모두에 들어감.
		var tex_w: float = COATING_TEX.get_width() / float(subdivisions_per_cell)
		var tex_h: float = COATING_TEX.get_height() / float(subdivisions_per_cell)
		var sub_cells: Array = []
		for sy in subdivisions_per_cell:
			for sx in subdivisions_per_cell:
				var sub := TextureRect.new()
				sub.position = Vector2(cell_padding + sx * sub_w, cell_padding + sy * sub_h)
				sub.size = Vector2(sub_w, sub_h)
				var atlas := AtlasTexture.new()
				atlas.atlas = COATING_TEX
				atlas.region = Rect2(sx * tex_w, sy * tex_h, tex_w, tex_h)
				sub.texture = atlas
				sub.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				sub.stretch_mode = TextureRect.STRETCH_SCALE
				sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(sub)
				sub_cells.append(sub)

		cells.append({
			"root": cell,
			"bg": bg,
			"label": label,
			"sub_cells": sub_cells,
			"scratched_count": 0,
			"completed": false,
		})


func new_card() -> void:
	# ⚠️ 진행 중인 셀 완성 연출 트윈을 먼저 중단 + 시각 강제 복원.
	# (한 방 죽음 시 reset_card→new_card 가 _celebrate_cell 페이드 트윈[0.15s]보다 빠르면, 살아남은 트윈
	#  콜백/페이드가 새 카드의 그 칸을 다시 숨겨 "마지막 칸 긁힌 채" 버그가 났음.)
	for t in _cell_tweens:
		if t != null and t.is_valid():
			t.kill()
	_cell_tweens.clear()
	_auto_accum = 0.0
	numbers.clear()
	_roll_wild_cells()   # 이번 카드의 와일드 칸 결정(④)
	for i in cells.size():
		numbers.append(_roll_number())
		# 와일드 칸은 ★ 표시(평가 시 numbers에서 제외하고 wild_count로 전달).
		cells[i].label.text = "★" if i in wild_cells else str(numbers[i])
		cells[i].label.scale = Vector2.ONE       # 펑 트윈 잔재 복원
		cells[i].bg.modulate = Color(1, 1, 1, 1)  # 플래시 트윈 잔재 복원
		cells[i].scratched_count = 0
		cells[i].completed = false
		for sub in cells[i].sub_cells:
			sub.visible = true
			sub.modulate.a = 1.0                  # 페이드 트윈 잔재 복원


func _roll_wild_cells() -> void:
	# ④ 와일드: 유물별 발생확률을 각각 굴려 성공 수(상한 wild_cap)만큼 무작위 칸을 와일드로.
	wild_cells = []
	if wild_chances.is_empty() or wild_cap <= 0 or cells.is_empty():
		return
	var n: int = 0
	for ch in wild_chances:
		if n >= wild_cap:
			break
		if randf() < float(ch):
			n += 1
	if n <= 0:
		return
	var idxs: Array = []
	for i in cells.size():
		idxs.append(i)
	idxs.shuffle()
	for k in min(n, idxs.size()):
		wild_cells.append(int(idxs[k]))


# ---------- 숫자 분포 (집합 / 가중치) ----------
# 칸에 들어갈 숫자의 집합과 등장 확률을 런타임에 바꾼다. 변경은 다음 카드(new_card)부터 반영.
# 즉시 반영하려면 호출 측이 reset_card()/new_card()를 부른다.

# {값:가중치} 직접 지정. 예) {7:3.0, 8:1.0, 9:1.0} → 7이 3배 자주.
# 빈 dict({})를 주면 균등(number_min~number_max)으로 복귀.
func set_number_weights(weights: Dictionary) -> void:
	_number_weights = weights.duplicate()
	_rebuild_weight_cache()


# 균등 가중치 집합. 예) [7, 8, 9] → 7·8·9만 같은 확률로 등장.
func set_number_pool(values: Array) -> void:
	var w: Dictionary = {}
	for v in values:
		w[int(v)] = 1.0
	set_number_weights(w)


# 균등 범위(기본 방식). 커스텀 분포를 지우고 min~max 균등으로.
func set_number_range(new_min: int, new_max: int) -> void:
	number_min = new_min
	number_max = max(new_min, new_max)
	clear_number_weights()


func clear_number_weights() -> void:
	_number_weights.clear()
	_weighted_values.clear()
	_weighted_cum.clear()
	_weight_total = 0.0


func _rebuild_weight_cache() -> void:
	_weighted_values.clear()
	_weighted_cum.clear()
	_weight_total = 0.0
	var keys: Array = _number_weights.keys()
	keys.sort()  # 결정적 순서
	for k in keys:
		var w: float = float(_number_weights[k])
		if w <= 0.0:
			continue
		_weight_total += w
		_weighted_values.append(int(k))
		_weighted_cum.append(_weight_total)


# 숫자 한 개 추첨. 커스텀 가중치가 있으면 가중 추첨, 없으면 min~max 균등.
func _roll_number() -> int:
	if _weighted_values.is_empty():
		return randi_range(number_min, number_max)
	var r: float = randf() * _weight_total
	for i in _weighted_values.size():
		if r < _weighted_cum[i]:
			return _weighted_values[i]
	return _weighted_values[_weighted_values.size() - 1]  # 부동소수 안전 폴백


func _gui_input(event: InputEvent) -> void:
	if is_locked:
		return
	# 터치(모바일) + 마우스(데스크탑/웹) 모두 처리.
	# 웹/PC는 입력이 마우스라 터치 이벤트만 처리하면 긁기가 안 먹는다.
	if event is InputEventScreenTouch:
		if event.pressed:
			_scratch_at(event.position)
	elif event is InputEventScreenDrag:
		_scratch_at(event.position)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_scratch_at(event.position)
	elif event is InputEventMouseMotion:
		# 왼쪽 버튼을 누른 채 움직일 때만 (드래그)
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_scratch_at(event.position)


func _scratch_at(local_pos: Vector2) -> void:
	# 수동 입력 발생 → 자동 긁기 쿨다운 리셋 (조작 종료 후 2초 뒤 자동 재개)
	_manual_cooldown = AUTO_RESUME_DELAY
	var geo := _cell_geometry()
	var cell_w: float = geo["cell_w"]
	var cell_h: float = geo["cell_h"]
	var sub_w: float = geo["sub_w"]
	var sub_h: float = geo["sub_h"]
	var sub_total: int = _sub_total()
	var threshold_count: int = int(ceil(float(sub_total) * completion_threshold))
	var any_completed_now: bool = false

	for i in cells.size():
		var cell_origin := _cell_origin(i, cell_w, cell_h)
		var cell_center := cell_origin + Vector2(cell_w * 0.5, cell_h * 0.5)

		# 브러시가 이 cell 영역 근처에 없으면 스킵
		var dx: float = abs(local_pos.x - cell_center.x) - cell_w * 0.5
		var dy: float = abs(local_pos.y - cell_center.y) - cell_h * 0.5
		if dx > brush_radius and dy > brush_radius:
			continue

		var c = cells[i]
		var changed_in_cell: bool = false

		for sy in subdivisions_per_cell:
			for sx in subdivisions_per_cell:
				var sub_idx: int = sy * subdivisions_per_cell + sx
				var sub: TextureRect = c.sub_cells[sub_idx]
				if not sub.visible:
					continue
				var sub_center := cell_origin + Vector2(
					cell_padding + (sx + 0.5) * sub_w,
					cell_padding + (sy + 0.5) * sub_h
				)
				if local_pos.distance_to(sub_center) <= brush_radius:
					sub.visible = false
					c.scratched_count += 1
					changed_in_cell = true

		# 완성 = 전체 임계(70%) 도달 OR 가운데 영역(숫자 위치)이 다 긁힘 — 둘 중 하나면 완성.
		if changed_in_cell and not c.completed and (c.scratched_count >= threshold_count or _center_cleared(c)):
			_finish_cell(i)
			any_completed_now = true

	if any_completed_now and _all_completed():
		_complete()


func _finish_cell(i: int) -> void:
	# 한 셀 완료 처리(수동 임계 도달 / 자동 공개 공용). 완료 표시 + 셀 연출 + 효과음.
	var c = cells[i]
	if c.completed:
		return
	c.completed = true
	Audio.play_sfx("scratch")
	_celebrate_cell(i)


func _all_completed() -> bool:
	for c in cells:
		if not c.completed:
			return false
	return true


func _complete() -> void:
	is_locked = true
	# 와일드 칸은 제외한 숫자 + 와일드 수를 평가기에 넘긴다(④: 최대 그룹 합류).
	var nonwild: Array = []
	for i in numbers.size():
		if not (i in wild_cells):
			nonwild.append(numbers[i])
	var result: Dictionary = HandEvaluator.evaluate(nonwild, wild_cells.size())
	card_completed.emit(result)
	# 잠금 해제는 game.gd가 상태에 맞춰 소유: 적 생존 시 reset_card(새 카드+해제) / 다음 적 조우 시 _enter_idle.
	# (과거엔 여기서 일정 시간 후 자동 해제했으나, 이동(run) 중 game이 건 잠금을 덮어써 "이동 중 재긁힘" 버그 유발 → 제거.)


func _celebrate_cell(idx: int) -> void:
	var c = cells[idx]

	# 남은 sub-cell 일제 페이드아웃 → 비활성
	var remaining: Array = []
	for sub in c.sub_cells:
		if sub.visible:
			remaining.append(sub)
	if remaining.size() > 0:
		var tw_sub := create_tween().set_parallel(true)
		_cell_tweens.append(tw_sub)
		for sub in remaining:
			tw_sub.tween_property(sub, "modulate:a", 0.0, 0.15)
		tw_sub.chain().tween_callback(func():
			for sub in remaining:
				sub.visible = false
				sub.modulate.a = 1.0
		)

	# 배경 노란 플래시 → 원색 복귀 (Panel이라 modulate로 틴트)
	c.bg.modulate = Color(1, 1, 1, 1)
	var tw_bg := create_tween()
	_cell_tweens.append(tw_bg)
	tw_bg.tween_property(c.bg, "modulate", Color(1.5, 1.4, 0.7, 1), 0.1)
	tw_bg.tween_property(c.bg, "modulate", Color(1, 1, 1, 1), 0.25)

	# 숫자 라벨 펑 (scale 1 → 1.3 → 1)
	c.label.scale = Vector2(1.0, 1.0)
	var tw_label := create_tween()
	_cell_tweens.append(tw_label)
	tw_label.tween_property(c.label, "scale", Vector2(1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_label.tween_property(c.label, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
