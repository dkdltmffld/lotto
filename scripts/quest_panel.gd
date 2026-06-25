extends "res://scripts/panel_overlay_base.gd"

# 퀘스트 오버레이 — 메인/일일 목표 + 진행도 + 수령. (기획: docs/design/퀘스트 시스템 정리본.md §7)
# 전체화면 모달(상단 HUD 퀘스트 버튼에서 UIManager.register_overlay 로 띄움 — 우편함/설정 계열).
# panel_overlay_base 의 closed 시그널·make_close_button·_toast·_status_badge·_reward_summary_row 재사용.
#
# 수령 시퀀스(우편함 §6-0 미러): 보상 add_currency + mark_claimed 메모리 일괄 반영 → flush() 1회
#   → Events.currency_changed.emit() → NotificationManager.reward(합산). 건별 flush 금지.
# 진행도(기획 §4): 메인=절대 누적 stat(소급), 일일=get_stat - 그날 base. 카탈로그/판정은 Quests(순수).

const QuestsScript = preload("res://scripts/quests.gd")    # 카탈로그+순수 로직(class_name Quests)
const DayUtilScript = preload("res://scripts/day_util.gd")  # 일일 리셋 날짜(class_name DayUtil)

var _list: VBoxContainer = null
# 메인 퀘스트는 HUD 트래커(quest_tracker.gd)로 분리 — 이 패널은 일일 전용(2026-06-12).


func _ready() -> void:
	# 전체화면 dim + 중앙 카드(헤더[제목+닫기] / 일일 목록 스크롤). 메인은 HUD 트래커로 분리.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # 뒤(게임)로 입력 안 샘. 닫기는 버튼으로만.
	add_child(dim)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UISkin.panel())
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -168.0
	card.offset_right = 168.0
	card.offset_top = -300.0
	card.offset_bottom = 300.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	card.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	m.add_child(vb)

	# 헤더: 제목 + 닫기
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "일일 퀘스트"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	header.add_child(make_close_button(_on_close_pressed))
	vb.add_child(header)

	# 목록 (세로 스크롤)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	vb.add_child(scroll)


func open() -> void:
	# UIManager.open_overlay() 통일 인터페이스. 패널 열 때도 일일 롤오버 점검(앱 실행 중 날짜 변경 대비, 기획 §5).
	if BackendService.roll_daily_quests_if_needed(DayUtilScript.today(), QuestsScript.daily_stat_keys()):
		BackendService.flush()
	_refresh()
	visible = true


# ---------- 목록 (일일 전용 — 메인은 HUD 트래커) ----------

func _refresh() -> void:
	UISkin.clear_children(_list)
	var stats: Dictionary = BackendService.get_stats()
	var base: Dictionary = BackendService.get_quests_daily_base()
	for q in QuestsScript.daily_quests():  # 노출(exposed) 일일만 — 소환은 개발 비노출
		_list.add_child(_build_daily_row(q, stats, base))
	if _list.get_child_count() == 0:
		var empty := UISkin.make_empty_label("오늘의 퀘스트가 없습니다.")
		empty.visible = true
		_list.add_child(empty)


func _build_daily_row(q: Dictionary, stats: Dictionary, base: Dictionary) -> Control:
	var id: String = str(q.get("id", ""))
	var cur: int = QuestsScript.daily_progress(q, stats, base)
	var target: int = int(q.get("target", 0))
	var complete: bool = QuestsScript.daily_complete(q, stats, base)
	var claimed: bool = BackendService.is_quest_daily_claimed(id)
	return _build_row("daily", q, cur, target, complete, claimed)


func _build_row(category: String, q: Dictionary, cur: int, target: int, complete: bool, claimed: bool) -> Control:
	# 퀘스트 1행: [제목 + 상태] / [설명] / [진행 바 + x/target] / [보상] / [받기|완료].
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.inset_row_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if claimed:
		panel.modulate = Color(0.62, 0.62, 0.62)  # 수령완료 = 흐리게

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# 제목 + 상태
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = str(q.get("title", "?"))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if claimed:
		title_row.add_child(_status_badge("수령완료", Color(0.6, 0.85, 0.6)))
	elif complete:
		title_row.add_child(_status_badge("완료!", Color(1.0, 0.85, 0.35)))
	vb.add_child(title_row)

	# 설명
	var desc := Label.new()
	desc.text = str(q.get("desc", ""))
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.80, 0.77, 0.70))
	vb.add_child(desc)

	# 진행 바 + x/target
	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 8)
	var bar := _make_progress_bar(float(cur) / float(maxi(1, target)))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prog_row.add_child(bar)
	var prog_lbl := Label.new()
	prog_lbl.text = "%s / %s" % [_fmt_int(cur), _fmt_int(target)]
	prog_lbl.add_theme_font_size_override("font_size", 11)
	prog_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.74))
	prog_row.add_child(prog_lbl)
	vb.add_child(prog_row)

	# 보상 요약
	var rewards: Array = q.get("rewards", [])
	if not rewards.is_empty():
		vb.add_child(_reward_summary_row(rewards))

	# 받기 버튼 (완료 & 미수령일 때만)
	if complete and not claimed:
		var id: String = str(q.get("id", ""))
		var b := UISkin.make_buy_button(Vector2(0, 36), 14, 4, true, true, Color(0, 0, 0, 0), true)
		b.text = "받기"
		b.pressed.connect(func() -> void: _on_claim(category, q))
		vb.add_child(b)

	return panel


func _make_progress_bar(ratio: float) -> Control:
	# 트랙(어두움) + 채움(녹색, anchor_right = 진행도). 채움/깎임 색 규칙(어두운 회색=미진행).
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 10)
	var track := ColorRect.new()
	track.color = Color(0.12, 0.12, 0.14)
	track.anchor_right = 1.0
	track.anchor_bottom = 1.0
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(track)
	var fill := ColorRect.new()
	fill.color = Color(0.27, 0.82, 0.32)
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	return holder


# _status_badge / _reward_summary_row 는 panel_overlay_base(베이스) 공용.


func _fmt_int(v: int) -> String:
	return UISkin.fmt_currency(float(v))


# ---------- 수령 (우편함 §6-0 시퀀스 미러: 메모리 일괄 반영 → flush 1회) ----------

func _on_claim(category: String, q: Dictionary) -> void:
	Audio.play_sfx("button")
	var id: String = str(q.get("id", ""))
	var already: bool = BackendService.is_quest_main_claimed(id) if category == "main" else BackendService.is_quest_daily_claimed(id)
	if already:
		return
	# 완료 재확인(버튼 표시 후 상태가 바뀌었을 가능성 — 방어)
	var stats: Dictionary = BackendService.get_stats()
	var done: bool
	if category == "main":
		done = QuestsScript.main_complete(q, stats)
	else:
		done = QuestsScript.daily_complete(q, stats, BackendService.get_quests_daily_base())
	if not done:
		_toast("아직 완료하지 않았습니다", 34.0, 14, Color(1.0, 0.85, 0.5), 1.0)
		_refresh()
		return
	# 지급 가능한 보상이 0개면 claimed 안 찍음(무보상 수령완료 방지, 우편함 §6 동일 가드)
	var valid: Array = QuestsScript.valid_rewards(q.get("rewards", []))
	if valid.is_empty():
		push_warning("[Quests] 지급 가능한 보상 없음 — claimed 미표시: %s" % id)
		_toast("받을 수 있는 보상이 없습니다", 34.0, 14, Color(1.0, 0.85, 0.5), 1.0)
		_refresh()
		return
	# 멱등성: claimed 먼저 메모리 표시(미지급보다 이중지급이 위험) → 보상 가산 → flush 1회.
	if category == "main":
		BackendService.mark_quest_main_claimed(id)
	else:
		BackendService.mark_quest_daily_claimed(id)
	var acc: Dictionary = {}
	BackendService.grant_currencies(valid, acc)
	BackendService.flush()
	Events.currency_changed.emit()  # → game._refresh_hud (HUD 재화 + 퀘스트 red dot 갱신)
	Audio.play_sfx("reward")
	UISkin.reward_toast(acc)
	_refresh()
