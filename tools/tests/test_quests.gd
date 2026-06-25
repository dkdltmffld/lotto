extends SceneTree

# ============================================================================
# 대상 모듈: res://scripts/quests.gd (퀘스트 카탈로그 + 순수 판정 로직, class_name Quests)
#   autoload 미참조 — headless --script 모드에서 단독 실행 가능.
#   ⚠️ claim 실행(재화 지급·flush)·일일 롤오버는 BackendService 의존이라 범위 외(quest_panel/backend 소관).
# 단독 실행:
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_quests.gd
# ============================================================================

const QuestsMod := preload("res://scripts/quests.gd")


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []

	# ===== 1. 카탈로그 구조 (메인/일일 모두 행동량 stat + 양수 허용재화 보상) =====
	var main: Array = QuestsMod.main_quests()
	_check(not main.is_empty(), "메인 퀘스트 카탈로그가 비어있음", fails)
	var all_daily: Array = QuestsMod.daily_quests(true)
	_check(not all_daily.is_empty(), "일일 퀘스트 카탈로그가 비어있음", fails)
	for q in main + all_daily:
		var qd := q as Dictionary
		_check(qd.has("id") and qd.has("title") and qd.has("stat") and qd.has("target") and qd.has("rewards"),
			"퀘스트 필드 누락: %s" % str(qd.get("id", "?")), fails)
		_check(int(qd.get("target", 0)) > 0, "%s target 이 양수가 아님" % str(qd.get("id")), fails)
		# 보상 currency 는 화이트리스트 + amount 양수(카탈로그 자체 정합 — 무보상 수령 방지)
		for r in qd.get("rewards", []):
			var cur: String = str((r as Dictionary).get("currency", ""))
			_check(QuestsMod.is_currency_allowed(cur), "%s reward currency '%s' 화이트리스트 밖" % [qd.get("id"), cur], fails)
		_check(not QuestsMod.valid_rewards(qd.get("rewards", [])).is_empty(),
			"%s 는 지급 가능한 보상이 있어야 함" % str(qd.get("id")), fails)
	# id 중복 없음
	var seen_ids: Dictionary = {}
	for q in main + all_daily:
		var id: String = str((q as Dictionary).get("id", ""))
		_check(not seen_ids.has(id), "퀘스트 id 중복: %s" % id, fails)
		seen_ids[id] = true

	# ===== 2. 일일 노출 필터 (소환은 exposed=false → 기본 목록 제외) =====
	var exposed: Array = QuestsMod.daily_quests(false)
	_check(exposed.size() < all_daily.size(), "비노출(소환) 일일이 하나는 있어야 함", fails)
	for q in exposed:
		_check(bool((q as Dictionary).get("exposed", true)), "daily_quests(false)에 비노출 퀘 포함됨", fails)
	# 노출 일일이 최소 1종은 있어야(데이터 편집으로 개수는 가변 — 구조 속성만 검사).
	_check(exposed.size() >= 1, "노출 일일이 최소 1종은 있어야 함 (실제 %d)" % exposed.size(), fails)

	# ===== 3. daily_stat_keys (중복 제거, 모든 일일 stat 포함) =====
	var keys: Array = QuestsMod.daily_stat_keys()
	for q in all_daily:
		_check(keys.has(str((q as Dictionary).get("stat", ""))), "daily_stat_keys 에 %s 누락" % str((q as Dictionary).get("stat")), fails)

	# ===== 4. 메인 진행도/완료 (절대 누적 = 소급) =====
	var mq := {"id": "t_main", "stat": "total_kills", "target": 30, "rewards": [{"currency": "dia", "amount": 10.0}]}
	_check(QuestsMod.main_progress(mq, {"total_kills": 0}) == 0, "메인 진행 0", fails)
	_check(QuestsMod.main_progress(mq, {"total_kills": 12}) == 12, "메인 진행 12", fails)
	_check(QuestsMod.main_progress(mq, {"total_kills": 99}) == 30, "메인 진행 target 캡", fails)
	_check(not QuestsMod.main_complete(mq, {"total_kills": 29}), "29<30 미완료", fails)
	_check(QuestsMod.main_complete(mq, {"total_kills": 30}), "30>=30 완료(경계)", fails)
	_check(QuestsMod.main_complete(mq, {"total_kills": 500}), "이미 초과 → 소급 완료", fails)
	_check(QuestsMod.main_progress(mq, {}) == 0, "stat 없음 → 0", fails)

	# ===== 5. 일일 진행도/완료 (base 대비 델타) =====
	var dq := {"id": "t_daily", "stat": "upgrades_bought", "target": 10, "rewards": [{"currency": "dia", "amount": 5.0}]}
	var base := {"upgrades_bought": 100}  # 그날 시작 스냅샷
	_check(QuestsMod.daily_delta(dq, {"upgrades_bought": 100}, base) == 0, "델타 0(시작 직후)", fails)
	_check(QuestsMod.daily_delta(dq, {"upgrades_bought": 107}, base) == 7, "델타 7", fails)
	_check(QuestsMod.daily_progress(dq, {"upgrades_bought": 130}, base) == 10, "일일 진행 target 캡", fails)
	_check(not QuestsMod.daily_complete(dq, {"upgrades_bought": 109}, base), "9<10 미완료", fails)
	_check(QuestsMod.daily_complete(dq, {"upgrades_bought": 110}, base), "10>=10 완료(경계)", fails)
	# base 가 현재보다 큰 손상 케이스 → 음수 방지(0)
	_check(QuestsMod.daily_delta(dq, {"upgrades_bought": 50}, base) == 0, "base>현재 → 델타 0(손상 방어)", fails)
	# base 키 없음(롤오버 직후 0 스냅샷 누락) → 현재값 그대로 델타
	_check(QuestsMod.daily_delta(dq, {"upgrades_bought": 5}, {}) == 5, "base 키 없음 → 현재값 델타", fails)

	# ===== 6. valid_rewards (오타/0/음수 제외) =====
	var vr: Array = QuestsMod.valid_rewards([
		{"currency": "dia", "amount": 30.0},   # 유효
		{"currency": "diia", "amount": 50.0},  # 오타 → 제외
		{"currency": "dust", "amount": 0.0},   # 0 → 제외
		{"currency": "gold", "amount": -5.0},  # 음수 → 제외
	])
	_check(vr.size() == 1, "valid_rewards 유효 1건 (실제 %d)" % vr.size(), fails)
	_check(QuestsMod.valid_rewards([]).is_empty(), "빈 보상 → 0", fails)

	# ===== 7. has_claimable (완료+미수령 = red dot) =====
	# 메인 첫 퀘(total_kills 30)를 완료시키는 stat
	var first_main := main[0] as Dictionary
	var stat_done := {str(first_main.get("stat")): int(first_main.get("target"))}
	_check(QuestsMod.has_claimable(stat_done, {}, {}, {}), "완료+미수령 → has_claimable", fails)
	# 그 퀘를 수령 처리 → (그 stat만으론) 더 없음
	_check(not QuestsMod.has_claimable(stat_done, {}, {str(first_main.get("id")): true}, {}), "수령하면 그 퀘는 제외", fails)
	# 아무 진행 없음 → false
	_check(not QuestsMod.has_claimable({}, {}, {}, {}), "진행 0 → has_claimable=false", fails)
	# 분리 판정 (메인=HUD 트래커 / 일일=상단 버튼 red dot)
	_check(QuestsMod.has_claimable_main(stat_done, {}), "has_claimable_main: 메인 완료 → true", fails)
	_check(not QuestsMod.has_claimable_daily(stat_done, {}, {}), "has_claimable_daily: total_kills 30 < 일일 100 → false", fails)
	# 비노출(소환) 일일은 완료해도 red dot 트리거 안 함
	var hidden = null  # 무타입(:= 는 null에서 타입 추론 불가) — 아래서 Dictionary 또는 null
	for q in all_daily:
		if not bool((q as Dictionary).get("exposed", true)):
			hidden = q as Dictionary
			break
	if hidden != null:
		var hidden_done := {str(hidden.get("stat")): int(hidden.get("target")) + 1000}
		# 비노출 일일의 stat 이 메인 퀘와 공유될 수 있으므로(예: equipment_pulls), 메인을 전부 수령 처리해
		# "일일 필터만" 격리한다 — 그래도 has_claimable=false 여야(비노출 일일은 red dot 비대상).
		var all_main_claimed := {}
		for q in main:
			all_main_claimed[str((q as Dictionary).get("id"))] = true
		_check(not QuestsMod.has_claimable(hidden_done, {}, all_main_claimed, {}),
			"비노출 일일 완료는 red dot 트리거 안 함", fails)

	return fails


func _initialize() -> void:
	var fails: Array = run()
	for msg in fails:
		printerr("  FAIL: %s" % str(msg))
	if fails.is_empty():
		print("[test_quests] PASS")
	else:
		print("[test_quests] FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
