extends SceneTree

# ============================================================================
# 대상 모듈: res://scripts/mailbox.gd (우편함 카탈로그 + 순수 판정 로직, class_name Mailbox)
#   autoload 미참조(now()는 Time만 사용) — headless --script 모드에서 단독 실행 가능.
#   ⚠️ claim 실행(재화 지급·flush)은 BackendService 의존이라 범위 외(mailbox_panel 소관).
# 단독 실행:
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_mailbox.gd
# 출력: 전부 통과 시 "[test_mailbox] PASS" + exit 0 / 실패 시 FAIL 목록 + exit 1
# ============================================================================

const MailboxMod := preload("res://scripts/mailbox.gd")


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []

	# ===== 1. 카탈로그 로드 + 우편 정의 구조 =====
	var ids: Array = MailboxMod.all_ids()
	_check(not ids.is_empty(), "카탈로그가 비어있음", fails)
	for id in ids:
		_check(MailboxMod.has_mail(id), "has_mail(%s) false" % id, fails)
		var def: Dictionary = MailboxMod.get_mail(id)
		_check(str(def.get("id", "")) == id, "get_mail(%s).id 불일치" % id, fails)
		_check(def.has("title") and def.has("rewards"), "%s 에 title/rewards 누락" % id, fails)
		# rewards 의 currency 는 모두 허용 집합에 속해야 함(카탈로그 자체 정합)
		for r in def.get("rewards", []):
			var cur: String = str((r as Dictionary).get("currency", ""))
			_check(MailboxMod.is_currency_allowed(cur), "%s reward 의 currency '%s' 가 화이트리스트 밖" % [id, cur], fails)
			_check(float((r as Dictionary).get("amount", 0)) > 0.0, "%s reward amount 가 양수가 아님" % id, fails)
	_check(MailboxMod.get_mail("__없는우편__").is_empty(), "없는 우편 get_mail = {}", fails)

	# ===== 2. 재화 화이트리스트 =====
	_check(MailboxMod.is_currency_allowed("gold"), "gold 허용", fails)
	_check(MailboxMod.is_currency_allowed("dia"), "dia 허용", fails)
	_check(MailboxMod.is_currency_allowed("dust"), "dust 허용", fails)
	_check(not MailboxMod.is_currency_allowed("diia"), "오타 'diia' 차단", fails)
	_check(not MailboxMod.is_currency_allowed("gold_old"), "'gold_old' 차단", fails)
	_check(not MailboxMod.is_currency_allowed(""), "빈 키 차단", fails)

	# ===== 2-1. valid_rewards (오타/무보상 우편 판정 — 무보상 수령완료 방지) =====
	var vr_mixed: Array = MailboxMod.valid_rewards([
		{"currency": "gold", "amount": 100.0},   # 유효
		{"currency": "diia", "amount": 50.0},     # 오타 키 → 제외
		{"currency": "dia", "amount": 0.0},       # amount 0 → 제외
		{"currency": "dust", "amount": -5.0},     # 음수 → 제외
		{"currency": "dia", "amount": 30.0},      # 유효
	])
	_check(vr_mixed.size() == 2, "valid_rewards 혼합 → 유효 2건 (실제 %d)" % vr_mixed.size(), fails)
	_check(MailboxMod.valid_rewards([]).is_empty(), "빈 보상 → valid 0", fails)
	_check(MailboxMod.valid_rewards([{"currency": "diia", "amount": 100.0}]).is_empty(), "전부 오타 키 → valid 0(무보상 수령 방지)", fails)
	# 현 카탈로그의 모든 우편은 valid_rewards 가 비지 않아야 함(정상 수령 가능)
	for id in ids:
		var def0: Dictionary = MailboxMod.get_mail(id)
		_check(not MailboxMod.valid_rewards(def0.get("rewards", [])).is_empty(), "%s 는 지급 가능한 보상이 있어야 함" % id, fails)

	# ===== 3. is_expired (at 명시로 결정적) =====
	var t0: int = 1_781_000_000
	_check(not MailboxMod.is_expired({"expires_at": 0}, t0), "expires_at=0 → 만료 없음", fails)
	_check(not MailboxMod.is_expired({}, t0), "expires_at 누락 → 만료 없음", fails)
	_check(MailboxMod.is_expired({"expires_at": t0 - 10}, t0), "과거 expires_at → 만료", fails)
	_check(not MailboxMod.is_expired({"expires_at": t0 + 10}, t0), "미래 expires_at → 미만료", fails)
	_check(MailboxMod.is_expired({"expires_at": t0}, t0), "expires_at == now → 만료(경계 포함)", fails)

	# ===== 4. claimable_ids / has_claimable =====
	# 빈 claimed_map + 미만료 카탈로그(현 더미는 전부 expires_at=0) → 전부 받을 수 있음
	var empty_claimed: Dictionary = {}
	var claimable_all: Array = MailboxMod.claimable_ids(empty_claimed, t0)
	_check(claimable_all.size() == ids.size(), "미수령 전체가 claimable 이어야 함 (실제 %d/%d)" % [claimable_all.size(), ids.size()], fails)
	_check(MailboxMod.has_claimable(empty_claimed, t0), "받을 게 있으면 has_claimable=true", fails)
	# 하나 수령 처리 → 그것만 빠짐
	if not ids.is_empty():
		var first: String = str(ids[0])
		var one_claimed: Dictionary = {first: true}
		var rest: Array = MailboxMod.claimable_ids(one_claimed, t0)
		_check(not rest.has(first), "수령한 우편은 claimable 에서 제외", fails)
		_check(rest.size() == ids.size() - 1, "수령 1건 후 claimable = 전체-1", fails)
	# 전부 수령 → has_claimable=false
	var all_claimed: Dictionary = {}
	for id in ids:
		all_claimed[id] = true
	_check(not MailboxMod.has_claimable(all_claimed, t0), "전부 수령 시 has_claimable=false", fails)
	# 만료된 우편은 claimable 에서 제외 (가상 만료 우편을 시뮬레이션할 수 없으니 만료 케이스는 is_expired 로 커버됨)

	# ===== 5. gc_claimed (카탈로그 제거 기준) =====
	# 카탈로그에 있는 id 만 → 변경 없음
	var keep_map: Dictionary = {}
	for id in ids:
		keep_map[id] = true
	var gc1: Dictionary = MailboxMod.gc_claimed(keep_map)
	_check(not bool(gc1["changed"]), "카탈로그에 있는 도장만 → changed=false", fails)
	_check((gc1["map"] as Dictionary).size() == ids.size(), "유효 도장은 보존", fails)
	# 카탈로그에 없는 id 포함 → 드롭 + changed=true
	var dirty_map: Dictionary = {"mail_옛날_삭제된우편": true}
	for id in ids:
		dirty_map[id] = true
	var gc2: Dictionary = MailboxMod.gc_claimed(dirty_map)
	_check(bool(gc2["changed"]), "카탈로그에 없는 id 있으면 changed=true", fails)
	_check(not (gc2["map"] as Dictionary).has("mail_옛날_삭제된우편"), "카탈로그에 없는 도장은 제거", fails)
	_check((gc2["map"] as Dictionary).size() == ids.size(), "GC 후 유효 도장만 남음", fails)

	# ===== 6. now() 는 양의 Unix초 =====
	_check(MailboxMod.now() > 1_700_000_000, "now() 가 합리적 Unix초가 아님", fails)

	return fails


func _initialize() -> void:
	var fails: Array = run()
	for msg in fails:
		printerr("  FAIL: %s" % str(msg))
	if fails.is_empty():
		print("[test_mailbox] PASS")
	else:
		print("[test_mailbox] FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
