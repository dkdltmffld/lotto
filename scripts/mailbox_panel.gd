extends "res://scripts/panel_overlay_base.gd"

# 우편함 오버레이 — 보상 수령식 통로. (기획: docs/design/우편함 시스템 정리본.md)
# 전체화면 모달(상단 HUD 버튼에서 UIManager.register_overlay 로 띄움 — settings/cheat 계열).
# panel_overlay_base 의 closed 시그널·make_close_button·_toast 만 재사용(밴드용 _build_scaffold 는 안 씀).
#
# 수령 시퀀스(§6-0): 보상 add_currency + mark_mail_claimed 를 **메모리에 일괄 반영 → flush() 1회**
#   → Events.currency_changed.emit() → NotificationManager.reward(합산). 건별 flush 금지(이중/부분지급 방지).
# 재화 화이트리스트(§5): Mailbox.is_currency_allowed 로 지급 직전 거름(미지원 키는 그 보상만 스킵).

const MailboxScript = preload("res://scripts/mailbox.gd")  # 카탈로그+순수 로직(class_name Mailbox)

var _list: VBoxContainer = null    # 우편 행 목록
var _claim_all_btn: Button = null


func _ready() -> void:
	# 전체화면 dim + 중앙 카드(헤더 / 목록 스크롤 / 모두받기).
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
	title.text = "우편함"
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

	# 모두 받기
	_claim_all_btn = UISkin.make_buy_button(Vector2(0, 44), 16, 6, true, true, Color(0, 0, 0, 0))
	_claim_all_btn.text = "모두 받기"
	_claim_all_btn.pressed.connect(_on_claim_all)
	vb.add_child(_claim_all_btn)


func open() -> void:
	# UIManager.open_overlay() 통일 인터페이스.
	_refresh()
	visible = true


# ---------- 목록 ----------

func _refresh() -> void:
	UISkin.clear_children(_list)
	var claimed: Dictionary = BackendService.get_mail_claimed()
	var at: int = MailboxScript.now()
	var any_claimable: bool = false
	# 안읽음(받을 수 있음) 먼저, 그 다음 수령완료/만료. 카탈로그 순서 유지하되 2패스.
	var pending: Array = []
	var done: Array = []
	for id in MailboxScript.all_ids():
		var def: Dictionary = MailboxScript.get_mail(id)
		var is_claimed: bool = bool(claimed.get(id, false))
		var is_expired: bool = MailboxScript.is_expired(def, at)
		if not is_claimed and not is_expired:
			pending.append(def)
			any_claimable = true
		else:
			done.append({"def": def, "claimed": is_claimed, "expired": is_expired})
	for def in pending:
		_list.add_child(_build_mail_row(def, "pending"))
	for e in done:
		# 받은 우편은 만료보다 '수령완료'를 우선 표시(claimed AND expired 동시면 수령완료가 자연스러움).
		_list.add_child(_build_mail_row(e["def"], "claimed" if e["claimed"] else "expired"))

	if _list.get_child_count() == 0:
		var empty := UISkin.make_empty_label("우편이 없습니다.")
		empty.visible = true
		_list.add_child(empty)
	_claim_all_btn.disabled = not any_claimable
	_claim_all_btn.modulate = Color(1, 1, 1) if any_claimable else Color(0.6, 0.6, 0.6)


func _build_mail_row(def: Dictionary, state: String) -> Control:
	# 우편 1행: [제목 + 상태배지] / [본문] / [보상 요약] / [받기 버튼](pending만).
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UISkin.inset_row_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if state != "pending":
		panel.modulate = Color(0.62, 0.62, 0.62)  # 수령완료/만료 = 흐리게

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# 제목 + 상태
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = str(def.get("title", "?"))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if state == "claimed":
		title_row.add_child(_status_badge("수령완료", Color(0.6, 0.85, 0.6)))
	elif state == "expired":
		title_row.add_child(_status_badge("만료됨", Color(0.9, 0.4, 0.4)))
	vb.add_child(title_row)

	# 본문
	var body := Label.new()
	body.text = str(def.get("body", ""))
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(0.80, 0.77, 0.70))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)

	# 보상 요약
	var rewards: Array = def.get("rewards", [])
	if not rewards.is_empty():
		vb.add_child(_reward_summary_row(rewards))

	# 받기 버튼 (받을 수 있을 때만)
	if state == "pending":
		var id: String = str(def.get("id", ""))
		var b := UISkin.make_buy_button(Vector2(0, 36), 14, 4, true, true, Color(0, 0, 0, 0), true)
		b.text = "받기"
		b.pressed.connect(func() -> void: _on_claim_one(id))
		vb.add_child(b)

	return panel


# ---------- 수령 (§6-0 시퀀스: 메모리 일괄 반영 → flush 1회) ----------
# _status_badge / _reward_summary_row 는 panel_overlay_base(베이스) 공용. 수령 토스트는 UISkin.reward_toast.

func _on_claim_one(id: String) -> void:
	Audio.play_sfx("button")
	if BackendService.is_mail_claimed(id):
		return
	var def: Dictionary = MailboxScript.get_mail(id)
	if def.is_empty() or MailboxScript.is_expired(def):
		_toast("받을 수 없는 우편입니다", 34.0, 14, Color(1.0, 0.85, 0.5), 1.0)
		_refresh()
		return
	# ⚠️ 지급 가능한 보상이 0개면 claimed를 찍지 않는다 — 오타/무보상 우편이 "보상 없이 수령완료"되어
	#    영영 미지급으로 박제되는 것 방지(Codex 리뷰 #8). 발행 실수는 카탈로그 수정으로 복구 가능하게 둔다.
	var valid: Array = MailboxScript.valid_rewards(def.get("rewards", []))
	if valid.is_empty():
		push_warning("[Mailbox] 지급 가능한 보상 없음 — claimed 미표시: %s" % id)
		_toast("받을 수 있는 보상이 없습니다", 34.0, 14, Color(1.0, 0.85, 0.5), 1.0)
		_refresh()
		return
	var acc: Dictionary = {}
	# 멱등성: claimed 먼저 메모리 표시(미지급보다 이중지급이 위험) → 보상 가산 → flush 1회.
	BackendService.mark_mail_claimed(id)
	BackendService.grant_currencies(valid, acc)
	BackendService.flush()
	Events.currency_changed.emit()
	Audio.play_sfx("reward")
	UISkin.reward_toast(acc)
	_refresh()


func _on_claim_all() -> void:
	Audio.play_sfx("button")
	var claimed: Dictionary = BackendService.get_mail_claimed()
	var ids: Array = MailboxScript.claimable_ids(claimed)
	if ids.is_empty():
		_toast("받을 우편이 없습니다", 34.0, 14, Color(1.0, 0.85, 0.5), 1.0)
		return
	var acc: Dictionary = {}
	var any: bool = false
	for id in ids:
		if BackendService.is_mail_claimed(id):
			continue  # 멱등성 국소 가드(§6-0) — claimable_ids 사전필터 외 이중 안전. 미래 회귀 방어.
		var valid: Array = MailboxScript.valid_rewards(MailboxScript.get_mail(id).get("rewards", []))
		if valid.is_empty():
			continue  # 무보상/오타 우편은 claimed 안 찍고 건너뜀(단일 수령과 동일 가드)
		BackendService.mark_mail_claimed(id)
		BackendService.grant_currencies(valid, acc)
		any = true
	if not any:
		_toast("받을 수 있는 보상이 없습니다", 34.0, 14, Color(1.0, 0.85, 0.5), 1.0)
		return
	BackendService.flush()  # 모두받기 = 메모리 일괄 반영 후 flush 1회
	Events.currency_changed.emit()
	Audio.play_sfx("reward")
	UISkin.reward_toast(acc)
	_refresh()
