extends SceneTree
# 대상: res://scripts/gacha.gd (장비 가챠 — 등급/강화 비용/추첨. 데이터 = res://data/equipment.json, GameData 경유)
# 단독 실행:
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_gacha.gd
# Gacha/GameData 전부 static·autoload 무참조 → --script 모드에서 그대로 동작.
# 기대값은 현재 data/equipment.json + 코드의 실제 동작 기준(characterization).
# 랜덤(roll 계열)은 seed 고정 → 결정적. 분포 검사는 느슨한 경계만.

const GachaScript := preload("res://scripts/gacha.gd")
const GameDataScript := preload("res://scripts/game_data.gd")

const EPS := 0.000001	# 부동소수 허용오차
const DIST_N := 6000	# 분포 검사 롤 횟수


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []
	var t: Dictionary = GameDataScript.table("equipment")

	# ── 1. 등급/풀 목록 ──
	var grades: Array = GachaScript.grade_ids()
	_check(grades == ["common", "rare", "epic", "legendary", "mythic"],
		"grade_ids = grade_order 순서: 실제 %s" % str(grades), fails)
	var pools: Array = GachaScript.pool_ids()
	_check(not pools.is_empty(), "pool_ids 비어있지 않음", fails)
	var order_str: Array = []
	for pid in (t.get("pool_order", []) as Array):
		order_str.append(str(pid))
	_check(pools == order_str, "pool_ids == 데이터 pool_order(%s): 실제 %s" % [str(order_str), str(pools)], fails)

	# ── 2. equip_bonus = base × (1 + per_lv(0.1) × lv), lv = 0 / 10 / 20(max) ──
	var exp_bonus := {
		"common": [0.1, 0.2, 0.3],
		"rare": [0.3, 0.6, 0.9],
		"epic": [0.8, 1.6, 2.4],
		"legendary": [2.0, 4.0, 6.0],
		"mythic": [5.0, 10.0, 15.0],
	}
	var bonus_levels := [0, 10, 20]
	for g in exp_bonus:
		for i in range(bonus_levels.size()):
			var lv: int = bonus_levels[i]
			var got: float = GachaScript.equip_bonus(g, lv)
			var want: float = exp_bonus[g][i]
			_check(absf(got - want) < EPS,
				"equip_bonus(%s, %d): 기대 %s, 실제 %s" % [g, lv, want, got], fails)

	# ── 2-2. 신화 돌파 별: equip_bonus(grade, lv, stars) = base×(1+0.1×lv)×(1+star_bonus_per×stars) ──
	# star_bonus_per=0.20 (data). stars=0 이면 기존과 동일.
	var sbp: float = GachaScript.star_bonus_per()
	_check(absf(GachaScript.equip_bonus("mythic", 0, 0) - 5.0) < EPS, "별0 = 기존(5.0)", fails)
	_check(absf(GachaScript.equip_bonus("mythic", 0, 1) - 5.0 * (1.0 + sbp)) < EPS, "별1 = 5.0×(1+sbp)", fails)
	_check(absf(GachaScript.equip_bonus("mythic", 0, 3) - 5.0 * (1.0 + sbp * 3.0)) < EPS, "별3 = 5.0×(1+sbp×3)", fails)
	_check(absf(GachaScript.equip_bonus("mythic", 20, 2) - 15.0 * (1.0 + sbp * 2.0)) < EPS, "별2+강화max = 15.0×(1+sbp×2)", fails)
	_check(GachaScript.is_top_grade("mythic"), "is_top_grade(mythic)=true", fails)
	_check(not GachaScript.is_top_grade("legendary"), "is_top_grade(legendary)=false", fails)

	# ── 3. enhance_cost = base_cost(100) × grade_mult(4)^등급idx × growth(1.5)^lv, round→int ──
	_check(GachaScript.enhance_cost("common", 0) == 100, "enhance_cost(common,0)=100: 실제 %d" % GachaScript.enhance_cost("common", 0), fails)
	_check(GachaScript.enhance_cost("common", 1) == 150, "enhance_cost(common,1)=150: 실제 %d" % GachaScript.enhance_cost("common", 1), fails)
	_check(GachaScript.enhance_cost("common", 2) == 225, "enhance_cost(common,2)=225: 실제 %d" % GachaScript.enhance_cost("common", 2), fails)
	# 337.5 → round half away from zero = 338 (코드 동작)
	_check(GachaScript.enhance_cost("common", 3) == 338, "enhance_cost(common,3)=338(337.5 반올림): 실제 %d" % GachaScript.enhance_cost("common", 3), fails)
	_check(GachaScript.enhance_cost("rare", 0) == 400, "enhance_cost(rare,0)=400: 실제 %d" % GachaScript.enhance_cost("rare", 0), fails)
	_check(GachaScript.enhance_cost("epic", 0) == 1600, "enhance_cost(epic,0)=1600: 실제 %d" % GachaScript.enhance_cost("epic", 0), fails)
	_check(GachaScript.enhance_cost("legendary", 0) == 6400, "enhance_cost(legendary,0)=6400: 실제 %d" % GachaScript.enhance_cost("legendary", 0), fails)
	_check(GachaScript.enhance_cost("mythic", 0) == 25600, "enhance_cost(mythic,0)=25600: 실제 %d" % GachaScript.enhance_cost("mythic", 0), fails)
	# 인접 등급 비율 = grade_mult(4) 정확히 (lv=0이면 반올림 오차 없음)
	for i in range(grades.size() - 1):
		var lo: int = GachaScript.enhance_cost(grades[i], 0)
		var hi: int = GachaScript.enhance_cost(grades[i + 1], 0)
		_check(hi == lo * 4, "등급 비용 비율 4배: %s(%d) → %s(%d)" % [grades[i], lo, grades[i + 1], hi], fails)
	# 인접 레벨 비율 ≈ growth(1.5) — round→int 오차 허용
	for lv in range(5):
		var a: int = GachaScript.enhance_cost("common", lv)
		var b: int = GachaScript.enhance_cost("common", lv + 1)
		var ratio: float = float(b) / float(a)
		_check(absf(ratio - 1.5) < 0.06, "레벨 비용 비율 ≈1.5: lv%d(%d)→lv%d(%d) = %f" % [lv, a, lv + 1, b, ratio], fails)
	# 미지 등급 → 등급 idx 0 폴백(코드 동작: find()<0 → gi=0)
	_check(GachaScript.enhance_cost("__없는등급__", 0) == 100, "미지 등급 enhance_cost = common과 동일(100)", fails)

	# ── 4. next_grade 체인: common→rare→epic→legendary→mythic→"" ──
	_check(GachaScript.next_grade("common") == "rare", "next_grade(common)=rare", fails)
	_check(GachaScript.next_grade("rare") == "epic", "next_grade(rare)=epic", fails)
	_check(GachaScript.next_grade("epic") == "legendary", "next_grade(epic)=legendary", fails)
	_check(GachaScript.next_grade("legendary") == "mythic", "next_grade(legendary)=mythic", fails)
	_check(GachaScript.next_grade("mythic") == "", "최상위 next_grade(mythic)=\"\"", fails)
	_check(GachaScript.next_grade("__없는등급__") == "", "미지 등급 next_grade=\"\"", fails)

	# ── 5. 강화 파라미터 / 풀 메타 ──
	_check(absf(GachaScript.enhance_per_lv() - 0.1) < EPS, "enhance_per_lv=0.1", fails)
	_check(GachaScript.enhance_max() == 20, "enhance_max=20", fails)
	_check(GachaScript.combine_n() == 4, "combine_n=4", fails)
	_check(GachaScript.cost("weapon") == 100, "cost(weapon)=100", fails)
	_check(GachaScript.cost_11("weapon") == 1000, "cost_11(weapon)=1000", fails)
	_check(GachaScript.cost_11("armor") == 1000, "cost_11(armor)=1000", fails)
	# 미지 풀: cost 기본 100 → cost_11 폴백 = 100×10 (코드 동작)
	_check(GachaScript.cost_11("__없는풀__") == 1000, "미지 풀 cost_11 = 기본 cost(100)×10", fails)
	_check(GachaScript.pool_stat("weapon") == "attack", "pool_stat(weapon)=attack", fails)
	_check(GachaScript.pool_stat("armor") == "hp", "pool_stat(armor)=hp", fails)
	# 표시 문자열(잠정 더미)은 하드코딩 대신 데이터 파생으로 대조 — 카탈로그 교체에도 생존.
	var weapon_pool: Dictionary = (t.get("pools", {}) as Dictionary).get("weapon", {})
	_check(GachaScript.pool_name("weapon") == str(weapon_pool.get("name", "")), "pool_name(weapon) = 데이터 pools.weapon.name", fails)
	_check(GachaScript.pool_effect("weapon") == str(weapon_pool.get("effect", "")), "pool_effect(weapon) = 데이터 pools.weapon.effect", fails)

	# ── 6. roll / roll_many (seed 고정 → 결정적, 불변식 검사) ──
	seed(20260611)
	var weapon_cat: Dictionary = ((t.get("pools", {}) as Dictionary).get("weapon", {}) as Dictionary).get("catalog", {})
	var armor_cat: Dictionary = ((t.get("pools", {}) as Dictionary).get("armor", {}) as Dictionary).get("catalog", {})
	var ok_keys := true
	var ok_in_catalog := true
	var ok_grade_match := true
	var ok_name_match := true
	var ok_stat := true
	var ok_grade_valid := true
	for i in range(200):
		var r: Dictionary = GachaScript.roll("weapon")
		if not (r.has("item") and r.has("grade") and r.has("name") and r.has("stat")):
			ok_keys = false
			continue
		var item: String = str(r["item"])
		if not weapon_cat.has(item):
			ok_in_catalog = false
			continue
		var entry: Dictionary = weapon_cat[item]
		if str(r["grade"]) != str(entry.get("grade", "")):
			ok_grade_match = false
		if str(r["name"]) != str(entry.get("name", "")):
			ok_name_match = false
		if str(r["stat"]) != "attack":
			ok_stat = false
		if not grades.has(str(r["grade"])):
			ok_grade_valid = false
	_check(ok_keys, "roll(weapon) 반환에 item/grade/name/stat 키 존재", fails)
	_check(ok_in_catalog, "roll(weapon) item이 weapon 카탈로그에 속함", fails)
	_check(ok_grade_match, "roll(weapon) grade == 카탈로그 아이템 grade", fails)
	_check(ok_name_match, "roll(weapon) name == 카탈로그 아이템 name", fails)
	_check(ok_stat, "roll(weapon) stat == attack", fails)
	_check(ok_grade_valid, "roll(weapon) grade가 grade_ids 집합에 속함", fails)

	var rm: Array = GachaScript.roll_many("armor", 11)
	_check(rm.size() == 11, "roll_many(armor,11) 개수=11: 실제 %d" % rm.size(), fails)
	var ok_rm := true
	for r in rm:
		if not (r is Dictionary):
			ok_rm = false
			continue
		var rd: Dictionary = r
		if not armor_cat.has(str(rd.get("item", ""))) or str(rd.get("stat", "")) != "hp":
			ok_rm = false
	_check(ok_rm, "roll_many(armor,11) 전부 armor 카탈로그 소속 + stat=hp", fails)
	_check(GachaScript.roll_many("weapon", 0).is_empty(), "roll_many(weapon,0) = 빈 배열", fails)
	_check(GachaScript.roll_many("weapon", -3).is_empty(), "음수 n → max(0,n) = 빈 배열", fails)
	_check(GachaScript.roll("__없는풀__").is_empty(), "없는 풀 roll = {} (카탈로그 빈 경우)", fails)
	_check(GachaScript.roll_many("__없는풀__", 5).is_empty(), "없는 풀 roll_many = 빈 배열", fails)

	# random_item_of_grade: 해당 등급 아이템만 반환 / 없는 등급은 ""
	# (기대값은 카탈로그 파생 — 더미 카탈로그의 아이템 id/이름은 잠정이라 하드코딩하지 않는다)
	var ok_riog := true
	for i in range(20):
		var it: String = GachaScript.random_item_of_grade("weapon", "mythic")
		if not (weapon_cat.has(it) and str((weapon_cat[it] as Dictionary).get("grade", "")) == "mythic"):
			ok_riog = false
	_check(ok_riog, "random_item_of_grade(weapon,mythic) = weapon 카탈로그의 mythic 아이템", fails)
	_check(GachaScript.random_item_of_grade("weapon", "__없는등급__") == "", "없는 등급 random_item_of_grade=\"\"", fails)

	# ── 7. item_info: 모든 풀 검색 (카탈로그 파생 기대값 — 무기/방어구 각 1키로 크로스풀 검색 커버) ──
	_check(not weapon_cat.is_empty() and not armor_cat.is_empty(), "카탈로그 비어있지 않음(vacuous pass 방지)", fails)
	if not weapon_cat.is_empty():
		var wk: String = str(weapon_cat.keys()[0])
		var we: Dictionary = weapon_cat[wk]
		var info: Dictionary = GachaScript.item_info(wk)
		_check(info.get("name", "") == str(we.get("name", "")) and info.get("grade", "") == str(we.get("grade", ""))
			and info.get("pool", "") == "weapon" and info.get("stat", "") == "attack",
			"item_info(%s) = weapon 카탈로그 entry와 일치: 실제 %s" % [wk, str(info)], fails)
	if not armor_cat.is_empty():
		var ak: String = str(armor_cat.keys()[0])
		var ae: Dictionary = armor_cat[ak]
		var info2: Dictionary = GachaScript.item_info(ak)
		_check(info2.get("pool", "") == "armor" and info2.get("stat", "") == "hp"
			and info2.get("grade", "") == str(ae.get("grade", "")),
			"item_info(%s) = armor 카탈로그 entry와 일치: 실제 %s" % [ak, str(info2)], fails)
	_check(GachaScript.item_info("__없는아이템__").is_empty(), "없는 아이템 item_info = {}", fails)

	# ── 8. 분포 (seed 고정 + 느슨한 경계): 가중치 60/28/9/2.5/0.5 순으로 빈도 내림차순 ──
	seed(987654321)
	var counts := {}
	for g in grades:
		counts[g] = 0
	for i in range(DIST_N):
		var r: Dictionary = GachaScript.roll("weapon")
		var g: String = str(r.get("grade", ""))
		if counts.has(g):
			counts[g] = int(counts[g]) + 1
	for i in range(grades.size() - 1):
		_check(int(counts[grades[i]]) > int(counts[grades[i + 1]]),
			"빈도 순서: %s(%d) > %s(%d)" % [grades[i], counts[grades[i]], grades[i + 1], counts[grades[i + 1]]], fails)
	_check(int(counts["common"]) > DIST_N * 0.5 and int(counts["common"]) < DIST_N * 0.7,
		"common 비율 50~70%% (실제 %d/%d)" % [counts["common"], DIST_N], fails)
	_check(int(counts["mythic"]) < DIST_N * 0.02, "mythic 비율 < 2%% (실제 %d/%d)" % [counts["mythic"], DIST_N], fails)
	_check(int(counts["mythic"]) > 0, "mythic도 등장(0.5%%, %d롤)" % DIST_N, fails)

	return fails


func _initialize() -> void:
	var fails: Array = run()
	for f in fails:
		printerr("  FAIL: %s" % f)
	if fails.is_empty():
		print("[test_gacha] PASS")
	else:
		print("[test_gacha] FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
