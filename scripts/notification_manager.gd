extends CanvasLayer

# 알림/토스트 매니저 (autoload "NotificationManager") — 싱글톤 매니저 2단계 (2026-06-11).
# 떴다 사라지는 알림의 단일 경로: 업적 해금(큐 순차) · 오프라인 보상 · 내비 "준비 중" · 패널 피드백.
# 자체 CanvasLayer(layer 80)라 씬 독립 — 씬 전환에도 안 끊기고, 씬 UI(컷인 z200 포함) 위에 그려진다.
# 좌표는 디자인 공간(360×780) — canvas_items 스트레치가 CanvasLayer에도 동일 적용.
# PROCESS_MODE_ALWAYS: 컷인 pause(get_tree().paused) 중에도 토스트 트윈이 진행(고착/누수 방지).
#   ⚠️ pause 중 modulate:a 트윈이 시각 반영 안 되던 엔진 이력(2026-06-08 컷인) — 최악의 경우 페이드가
#   해제 후로 밀려 보일 뿐 트윈은 완료되어 노드는 정리됨(토스트는 수명이 짧아 허용).
# 경계: 표시(+알림 고유 sfx)만 소유. 게임 반응(HUD 갱신 등)·이벤트 sfx는 호출 측 소유.
#   게임플레이 연출(컷인·튜토리얼 배너)·상주 HUD는 여기 소속이 아님(ui_manager.gd 경계 주석 참조).

const TOAST_FADE := 0.4   # 공통 페이드아웃 시간(초)
const ACH_HOLD := 2.2     # 업적 칩 유지 시간(초)
const ACH_TOP_Y := 170.0  # 업적 칩 상단 Y — 스테이지 배너(58~127) 아래

var _ach_queue: Array = []   # 대기 중 업적 def — 여러 개 동시 해금 시 순차 표시
var _ach_busy: bool = false  # 업적 칩 표시 중(큐 드레인 단일 비행)
# 슬롯별 활성 토스트(slot -> 노드). 같은 슬롯에 새 토스트가 뜨면 기존을 즉시 제거(겹침 방지).
# 슬롯이 다르면 공존(위치가 달라 안 겹침): "top"(보상) / "bottom"(안내) / "panel"(패널 피드백) / "hand"(족보 결과).
var _slots: Dictionary = {}


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------- 공개 API ----------

func reward(text: String) -> void:
	# 큰 보상 토스트(오프라인 정산·우편 수령 등) — 상단, 노랑, 2초. (구 game._show_offline_toast 시각 재현)
	var lbl := _make_label(text, 28, Color(1, 0.92, 0.3))
	lbl.anchor_right = 1.0
	lbl.offset_top = 110.0
	lbl.offset_bottom = 190.0
	_show_in_slot("top", lbl, 2.0)


func info(text: String) -> void:
	# 하단(내비 위) 안내 토스트 — "준비 중입니다" 등. (구 game._show_nav_toast 시각 재현)
	var lbl := _make_label(text, 20, Color(1, 1, 1, 0.95))
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_top = -150.0
	lbl.offset_bottom = -110.0
	_show_in_slot("bottom", lbl, 1.0)


func panel_feedback(text: String, panel: Control, bottom: float = 32.0, font_size: int = 14, color: Color = Color(1.0, 0.88, 0.5), hold: float = 1.2) -> void:
	# 밴드 패널 상단 피드백("보유 골드 부족" 등) — 패널 글로벌 rect 기준으로
	# 구 panel_overlay_base._toast(anchor_right=1 · offset_top 6 · offset_bottom <bottom>) 위치 재현.
	# 패널이 곧바로 닫혀도 토스트는 끝까지 표시된다(전역 레이어 소속).
	var r := panel.get_global_rect()
	var lbl := _make_label(text, font_size, color)
	# 그림자도 구 _toast 값 그대로(alpha 0.8 / offset 1px — 공용 apply_label_shadow 0.75/2px와 달라 오버라이드).
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.offset_left = r.position.x
	lbl.offset_right = r.position.x + r.size.x
	lbl.offset_top = r.position.y + 6.0
	lbl.offset_bottom = r.position.y + bottom
	_show_in_slot("panel", lbl, hold)


func hand_result(value: int, count: int, jackpot: bool = false) -> void:
	# 족보 결과 "value X count !!!" — 화면 중앙, scale 팝 + 페이드. (구 Effects.show_hand_result + HandResultLabel)
	# "hand" 슬롯이라 빠른 연속 완성 시 직전 결과를 즉시 교체(깜빡임 방지). 보상/안내 토스트와는 슬롯이 달라 공존.
	_clear_slot("hand")
	var lbl := Label.new()
	lbl.text = "%d X %d %s" % [value, count, "!".repeat(count)]
	lbl.anchor_left = 0.5
	lbl.anchor_top = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_bottom = 0.5
	lbl.offset_left = -170.0
	lbl.offset_top = -50.0
	lbl.offset_right = 170.0
	lbl.offset_bottom = 50.0
	lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	lbl.pivot_offset = Vector2(170, 50)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.35))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.scale = Vector2(0.3, 0.3)
	add_child(lbl)
	_slots["hand"] = lbl
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		if _slots.get("hand") == lbl:
			_slots.erase("hand")
		lbl.queue_free())
	if jackpot:
		_jackpot_tag()


func _jackpot_tag() -> void:
	# 족보 결과 아래 금색 "JACKPOT" 태그(팝업→페이드, 일회용). (구 Effects._spawn_jackpot_tag 재현)
	var tag := Label.new()
	tag.text = "JACKPOT"
	tag.add_theme_font_size_override("font_size", 44)
	tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	Effects.apply_label_shadow(tag, 0.85)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.anchor_left = 0.5
	tag.anchor_top = 0.5
	tag.anchor_right = 0.5
	tag.anchor_bottom = 0.5
	tag.offset_left = -170.0
	tag.offset_right = 170.0
	tag.offset_top = 44.0
	tag.offset_bottom = 100.0
	tag.pivot_offset = Vector2(170, 28)
	add_child(tag)
	tag.scale = Vector2(0.3, 0.3)
	var tw := tag.create_tween()
	tw.tween_property(tag, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(tag, "modulate:a", 0.0, 0.3)
	tw.tween_callback(tag.queue_free)


func achievement(def: Dictionary) -> void:
	# 업적 해금 칩. 빈 def(이미 해금/알 수 없음)는 무시 — 호출부가 Achievements.unlock 반환을 그대로 넘기면 됨.
	if def.is_empty():
		return
	_ach_queue.append(def)
	_drain_achievements()


func achievements(defs: Array) -> void:
	# 여러 업적 동시 해금(스탯 임계 일괄 판정) — 큐로 순차 표시.
	for d in defs:
		achievement(d)


# ---------- 내부 ----------

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	Effects.apply_label_shadow(lbl, 0.75, 2)
	return lbl


func _show_in_slot(slot: String, node: Control, hold: float) -> void:
	# 같은 슬롯에 떠 있던 토스트를 즉시 제거하고 새 토스트를 표시(겹침 방지). 슬롯이 다르면 공존.
	_clear_slot(slot)
	add_child(node)
	_slots[slot] = node
	var tw := node.create_tween()  # 노드 바인딩 — 노드 free 시 트윈 자동 정리
	tw.tween_interval(hold)
	tw.tween_property(node, "modulate:a", 0.0, TOAST_FADE)
	tw.tween_callback(func() -> void:
		if _slots.get(slot) == node:
			_slots.erase(slot)
		node.queue_free())


func _clear_slot(slot: String) -> void:
	# 해당 슬롯에 떠 있는 토스트 즉시 제거. (업적 칩은 큐로 순차 표시라 슬롯 관리 대상 아님)
	var prev = _slots.get(slot)
	if is_instance_valid(prev):
		prev.queue_free()
	_slots.erase(slot)


func _drain_achievements() -> void:
	if _ach_busy or _ach_queue.is_empty():
		return
	_ach_busy = true
	var def: Dictionary = _ach_queue.pop_front()
	Audio.play_sfx("reward")
	var chip := _build_achievement_chip(def)
	add_child(chip)
	var tw := chip.create_tween()
	tw.tween_interval(ACH_HOLD)
	tw.tween_property(chip, "modulate:a", 0.0, TOAST_FADE)
	tw.tween_callback(func() -> void:
		chip.queue_free()
		_ach_busy = false
		_drain_achievements())


func _build_achievement_chip(def: Dictionary) -> Control:
	# 검은 반투명 칩(가로 중앙 자동 크기) + 금색 제목 + 크림 설명.
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.65)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 8.0
	chip.add_theme_stylebox_override("panel", sb)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.anchor_left = 0.5
	chip.anchor_right = 0.5
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chip.offset_top = ACH_TOP_Y
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Container 기본 PASS — layer 80 최상위라 클릭을 흡수하지 않게
	vbox.add_theme_constant_override("separation", 1)
	chip.add_child(vbox)
	var title := Label.new()
	title.text = "업적 달성 - %s" % str(def.get("name", def.get("id", "?")))  # ASCII 하이픈(em-dash는 번들폰트에 없어 웹서 깨짐)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
	vbox.add_child(title)
	var desc: String = str(def.get("desc", ""))
	if desc != "":
		var dl := Label.new()
		dl.text = desc
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_font_size_override("font_size", 12)
		dl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
		vbox.add_child(dl)
	return chip
