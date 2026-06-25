extends PanelContainer

# 메인 퀘스트 HUD 트래커 — "다음 미수령 메인 퀘스트 1개"만 상시 표시(우측 하단). (기획: 퀘스트 §7 변형, 2026-06-12)
# 일일 퀘스트는 별도 패널(quest_panel), 메인은 이 상시 위젯이 담당.
# 흐름: 다음 메인 퀘 노출 → 진행도 상시 갱신(game._refresh_hud 가 refresh 호출) → 완료 시 "완료! 받기"(펄스)
#        → 위젯 클릭 = 수령 → 즉시 다음 미수령 메인 퀘로 교체. 전부 수령하면 숨김.
# 수령 시퀀스(우편함 §6-0 미러): valid_rewards 0개면 claimed 미표시 → mark_claimed → add_currency → flush 1회
#        → Events.currency_changed.emit() → reward 토스트 → refresh.

const QuestsScript = preload("res://scripts/quests.gd")

# 재화 표시명/색은 UISkin.CURRENCY_NAME / UISkin.CURRENCY_COLOR 공용(단일 출처).
# 재화 아이콘 — 보상 표시를 "아이콘 ×개수"로. 가루(dust)는 아이콘 에셋 없음 → 이름 폴백.
const CURRENCY_ICON := {
	"gold": preload("res://assets/ui/icon/icon_gold.png"),
	"dia": preload("res://assets/ui/icon/icon_dia.png"),
}

var _title: Label = null
var _status: Label = null
var _reward: HBoxContainer = null  # 보상 아이콘(×개수) 행
var _shown_id: String = ""         # 보상 표시 중인 퀘 id — 바뀔 때만 아이콘 재구성(매 처치 refresh 대비)
var _claimable: bool = false
var _pulse: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # 클릭 받기(완료 시 수령) + 뒤로 입력 안 샘
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.05, 0.84)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.6, 0.48, 0.25)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 클릭은 PanelContainer(_gui_input)가 받음
	add_child(vb)

	# 헤더: [메인 태그] + 제목
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Label.new()
	tag.text = "메인"
	tag.add_theme_font_size_override("font_size", 10)
	tag.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(tag)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	vb.add_child(head)

	# 상태: "x / target" 또는 "완료! 받기" (녹색 게이지 바는 제거 — 진행도는 텍스트로 표시)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_status)

	# 보상: 이 퀘스트로 받을 재화 = 아이콘 ×개수 (예: [다이아아이콘] ×50)
	_reward = HBoxContainer.new()
	_reward.add_theme_constant_override("separation", 4)
	_reward.alignment = BoxContainer.ALIGNMENT_CENTER
	_reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_reward)


func refresh() -> void:
	# 다음 미수령 메인 퀘를 찾아 표시. 없으면(전부 수령) 숨김.
	var q: Dictionary = _next_quest()
	if q.is_empty():
		visible = false
		_stop_pulse()
		return
	visible = true
	var stats: Dictionary = BackendService.get_stats()
	var cur: int = QuestsScript.main_progress(q, stats)
	var target: int = int(q.get("target", 0))
	_claimable = QuestsScript.main_complete(q, stats) and not QuestsScript.valid_rewards(q.get("rewards", [])).is_empty()
	_title.text = str(q.get("desc", q.get("title", "?")))  # 이름("더 강하게") 대신 목표("강화 5회")를 표시
	# 보상 아이콘은 퀘가 바뀔 때만 재구성(refresh는 처치마다 호출 → 매번 노드 재생성 방지)
	var id: String = str(q.get("id", ""))
	if id != _shown_id:
		_shown_id = id
		_set_reward(q.get("rewards", []))
	if _claimable:
		_status.text = "완료! 받기"
		_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
		_start_pulse()
	else:
		_status.text = "%s / %s" % [UISkin.fmt_currency(float(cur)), UISkin.fmt_currency(float(target))]
		_status.add_theme_color_override("font_color", Color(0.85, 0.82, 0.74))
		_stop_pulse()


func _set_reward(rewards: Array) -> void:
	# 보상 재화 = 아이콘 ×개수. (다이아: [다이아아이콘] ×50). 아이콘 없는 재화(가루)는 이름으로 폴백.
	UISkin.clear_children(_reward)
	for r in rewards:
		var rd := r as Dictionary
		var cur: String = str(rd.get("currency", ""))
		var amt: float = float(rd.get("amount", 0))
		var icon: Texture2D = CURRENCY_ICON.get(cur, null)
		if icon != null:
			var tex := TextureRect.new()
			tex.texture = icon
			tex.custom_minimum_size = Vector2(20, 20)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # 숫자와 세로 중앙 정렬
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_reward.add_child(tex)
			var lbl := Label.new()
			lbl.text = "×%s" % UISkin.fmt_currency(amt)
			lbl.add_theme_font_size_override("font_size", 18)  # × 더 크게(사용자 요청)
			lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # 아이콘과 세로 중앙 정렬
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_reward.add_child(lbl)
		else:
			# 아이콘 없는 재화(가루 등) — 이름 ×개수로 폴백, 재화 색 강조
			var lbl := Label.new()
			lbl.text = "%s ×%s" % [UISkin.CURRENCY_NAME.get(cur, cur), UISkin.fmt_currency(amt)]
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_color", UISkin.CURRENCY_COLOR.get(cur, Color(0.85, 0.82, 0.74)))
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_reward.add_child(lbl)


func is_claimable() -> bool:
	# 현재 표시 중인 메인 퀘가 받기 가능(완료+유효 보상)인지 — game 이 트래커 우상단 빨간 점 구동에 사용.
	return _claimable


func _next_quest() -> Dictionary:
	# 카탈로그 순서상 첫 '미수령' 메인 퀘(완료 여부 무관 — 미완료면 진행도, 완료면 받기).
	var claimed: Dictionary = BackendService.get_quests_main_claimed()
	for q in QuestsScript.main_quests():
		if not bool(claimed.get(str((q as Dictionary).get("id", "")), false)):
			return q as Dictionary
	return {}


func _gui_input(event: InputEvent) -> void:
	# 완료 상태에서 클릭 = 수령. 미완료면 무시(진행도 표시만).
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _claimable:
		_claim()


func _claim() -> void:
	var q: Dictionary = _next_quest()
	if q.is_empty():
		return
	var id: String = str(q.get("id", ""))
	if BackendService.is_quest_main_claimed(id):
		return
	if not QuestsScript.main_complete(q, BackendService.get_stats()):
		return
	var valid: Array = QuestsScript.valid_rewards(q.get("rewards", []))
	if valid.is_empty():
		push_warning("[QuestTracker] 지급 가능한 보상 없음 — claimed 미표시: %s" % id)
		return
	# 멱등성: claimed 먼저 메모리 표시 → 보상 가산 → flush 1회 (우편함 §6-0 동일).
	BackendService.mark_quest_main_claimed(id)
	var acc: Dictionary = {}
	BackendService.grant_currencies(valid, acc)
	BackendService.flush()
	Events.currency_changed.emit()  # → game._refresh_hud → tracker.refresh (다음 퀘 노출) + HUD 재화
	Audio.play_sfx("reward")
	UISkin.reward_toast(acc)
	refresh()  # 즉시 다음 미수령 메인 퀘로 교체


func _start_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		return  # 이미 펄스 중
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "modulate", Color(1.18, 1.12, 0.85), 0.5).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "modulate", Color(1, 1, 1), 0.5).set_trans(Tween.TRANS_SINE)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	modulate = Color(1, 1, 1)
