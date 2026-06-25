extends SceneTree
# 대상: res://scripts/hand_evaluator.gd (스크래치 족보 평가 — 순수 static, autoload 무참조)
# 단독 실행:
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_hand_evaluator.gd
# 기대값은 코드의 실제 동작 기준(characterization). 랜덤 없음 → 결정적.

const HE := preload("res://scripts/hand_evaluator.gd")


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []

	# ── 1. 잭팟: 9칸 모두 9 → count=9, value=9, mult=9²×9=729 ──
	var r: Dictionary = HE.evaluate([9, 9, 9, 9, 9, 9, 9, 9, 9])
	_check(r["count"] == 9, "잭팟(9×9) count: 기대 9, 실제 %s" % r["count"], fails)
	_check(r["value"] == 9, "잭팟(9×9) value: 기대 9, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 729, "잭팟(9×9) mult: 기대 729, 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [9], "잭팟(9×9) groups: 기대 [9], 실제 %s" % str(r["groups"]), fails)
	_check(r["name"] == "9개 9", "잭팟(9×9) name: 기대 '9개 9', 실제 '%s'" % r["name"], fails)

	# ── 2. 잭팟 최소값: 9칸 모두 1 → mult=81×1=81 ──
	r = HE.evaluate([1, 1, 1, 1, 1, 1, 1, 1, 1])
	_check(r["count"] == 9, "잭팟(9×1) count: 기대 9, 실제 %s" % r["count"], fails)
	_check(r["value"] == 1, "잭팟(9×1) value: 기대 1, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 81, "잭팟(9×1) mult: 기대 81, 실제 %s" % r["mult"], fails)

	# ── 3. 포카드(4장 같은 숫자) + 잡 → count=4, value=4, mult=16×4=64 ──
	r = HE.evaluate([4, 4, 4, 4, 2, 3, 5, 6, 7])
	_check(r["count"] == 4, "포카드 count: 기대 4, 실제 %s" % r["count"], fails)
	_check(r["value"] == 4, "포카드 value: 기대 4, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 64, "포카드 mult: 기대 64, 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [4, 1, 1, 1, 1, 1], "포카드 groups: 기대 [4,1,1,1,1,1], 실제 %s" % str(r["groups"]), fails)
	_check(r["name"] == "4개 4", "포카드 name: 기대 '4개 4', 실제 '%s'" % r["name"], fails)

	# ── 4. count 동점 시 높은 숫자 우선: 2가 2장·7이 2장 → value=7 ──
	r = HE.evaluate([2, 2, 7, 7, 1, 3, 4, 5, 6])
	_check(r["count"] == 2, "동점 count: 기대 2, 실제 %s" % r["count"], fails)
	_check(r["value"] == 7, "동점 value(높은 숫자 우선): 기대 7, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 28, "동점 mult: 기대 2²×7=28, 실제 %s" % r["mult"], fails)

	# ── 5. 와일드 합산(유물 ④): 5가 3장 + wild 2 → count=5, mult=25×5=125 ──
	r = HE.evaluate([5, 5, 5, 1, 2, 3, 4, 6], 2)
	_check(r["count"] == 5, "와일드 count: 기대 3+2=5, 실제 %s" % r["count"], fails)
	_check(r["value"] == 5, "와일드 value: 기대 5, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 125, "와일드 mult: 기대 5²×5=125, 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [5, 1, 1, 1, 1, 1], "와일드 groups(최대 그룹에 +2): 기대 [5,1,1,1,1,1], 실제 %s" % str(r["groups"]), fails)

	# ── 6. 음수 wild_count는 0으로 클램프(no-op) ──
	var base: Dictionary = HE.evaluate([5, 5, 5, 1, 2, 3, 4, 6], 0)
	r = HE.evaluate([5, 5, 5, 1, 2, 3, 4, 6], -3)
	_check(r["count"] == base["count"], "음수 와일드 count: 기대 %s(클램프), 실제 %s" % [base["count"], r["count"]], fails)
	_check(r["groups"] == base["groups"], "음수 와일드 groups: 기대 %s, 실제 %s" % [str(base["groups"]), str(r["groups"])], fails)

	# ── 7. 3+4 입력 → 포카드 우선 해석: groups=[4,3,...] (유물 ②족보확장) ──
	r = HE.evaluate([7, 7, 7, 7, 3, 3, 3, 1, 2])
	_check(r["count"] == 4, "3+4 count: 기대 4(큰 그룹), 실제 %s" % r["count"], fails)
	_check(r["value"] == 7, "3+4 value: 기대 7, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 112, "3+4 mult: 기대 4²×7=112, 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [4, 3, 1, 1], "3+4 groups(내림차순): 기대 [4,3,1,1], 실제 %s" % str(r["groups"]), fails)

	# ── 8. 풀하우스(3+2) 시나리오 groups ──
	r = HE.evaluate([3, 3, 3, 8, 8, 1, 2, 4, 5])
	_check(r["count"] == 3, "풀하우스 count: 기대 3, 실제 %s" % r["count"], fails)
	_check(r["value"] == 3, "풀하우스 value: 기대 3, 실제 %s" % r["value"], fails)
	_check(r["groups"] == [3, 2, 1, 1, 1, 1], "풀하우스 groups: 기대 [3,2,1,1,1,1], 실제 %s" % str(r["groups"]), fails)

	# ── 9. 투페어(2+2) 시나리오 groups + 동점 value ──
	r = HE.evaluate([2, 2, 5, 5, 9, 1, 3, 4, 6])
	_check(r["count"] == 2, "투페어 count: 기대 2, 실제 %s" % r["count"], fails)
	_check(r["value"] == 5, "투페어 value(2와 5 중 높은 쪽): 기대 5, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 20, "투페어 mult: 기대 2²×5=20, 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [2, 2, 1, 1, 1, 1, 1], "투페어 groups: 기대 [2,2,1,1,1,1,1], 실제 %s" % str(r["groups"]), fails)

	# ── 10. 전부 다른 숫자 → count=1, value=최고 숫자 ──
	r = HE.evaluate([1, 2, 3, 4, 5, 6, 7, 8, 9])
	_check(r["count"] == 1, "전부 다름 count: 기대 1, 실제 %s" % r["count"], fails)
	_check(r["value"] == 9, "전부 다름 value(최고 숫자): 기대 9, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 9, "전부 다름 mult: 기대 1²×9=9, 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [1, 1, 1, 1, 1, 1, 1, 1, 1], "전부 다름 groups: 기대 1×9개, 실제 %s" % str(r["groups"]), fails)

	# ── 11. 최소 입력(한 칸, 최소값 1) → mult=1 ──
	r = HE.evaluate([1])
	_check(r["count"] == 1, "단일 칸 count: 기대 1, 실제 %s" % r["count"], fails)
	_check(r["value"] == 1, "단일 칸 value: 기대 1, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 1, "단일 칸 mult: 기대 1, 실제 %s" % r["mult"], fails)

	# ── 12. 빈 배열 + wild=3 → groups=[3], value=0이라 mult=0 (코드 실제 동작) ──
	r = HE.evaluate([], 3)
	_check(r["count"] == 3, "빈+와일드 count: 기대 3, 실제 %s" % r["count"], fails)
	_check(r["value"] == 0, "빈+와일드 value: 기대 0, 실제 %s" % r["value"], fails)
	_check(r["mult"] == 0, "빈+와일드 mult: 기대 0(value=0), 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [3], "빈+와일드 groups: 기대 [3], 실제 %s" % str(r["groups"]), fails)

	# ── 13. 빈 배열 + wild=0 → 전부 0/빈 ──
	r = HE.evaluate([])
	_check(r["count"] == 0, "빈 배열 count: 기대 0, 실제 %s" % r["count"], fails)
	_check(r["groups"] == [], "빈 배열 groups: 기대 [], 실제 %s" % str(r["groups"]), fails)

	# ── 14. (특성 고정) 와일드는 '최다 등장' 그룹에 합류 — mult 최적 그룹이 아님 ──
	# [9,1,1] + wild 1: 1의 페어(count 2)가 최다라 와일드가 1쪽에 붙음 → 3²×1=9.
	# (9에 붙였다면 2²×9=36으로 더 컸을 것 — 현행 코드의 의도적/잠재적 특성, notes 참조)
	r = HE.evaluate([9, 1, 1], 1)
	_check(r["count"] == 3, "와일드 배치 count: 기대 3, 실제 %s" % r["count"], fails)
	_check(r["value"] == 1, "와일드 배치 value: 기대 1(최다 그룹), 실제 %s" % r["value"], fails)
	_check(r["mult"] == 9, "와일드 배치 mult: 기대 9, 실제 %s" % r["mult"], fails)
	_check(r["groups"] == [3, 1], "와일드 배치 groups: 기대 [3,1], 실제 %s" % str(r["groups"]), fails)

	return fails


func _initialize() -> void:
	var fails: Array = run()
	for f in fails:
		printerr("  FAIL: %s" % f)
	if fails.is_empty():
		print("[test_hand_evaluator] PASS")
		quit(0)
	else:
		print("[test_hand_evaluator] FAIL (%d)" % fails.size())
		quit(1)
