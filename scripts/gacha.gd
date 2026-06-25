class_name Gacha
extends RefCounted

# 장비 뽑기/강화/합성 로직 — data/equipment.json(GameData) 기반. 전부 static.
# 기획: docs/design/장비 시스템 정리본.md
# 등급(전 종류 공용): grades{grade: {weight, base}}. 풀(종류): pools{id: {name,effect,stat,cost,catalog{item:{name,grade}}}}.
# 절차: ① grades 가중치로 등급 추첨 → ② 그 등급의 풀 카탈로그에서 무작위 1개.
# 장착 보너스 = base[grade] × (1 + per_lv × 강화레벨). 무기=공격력 곱, 방어구=체력 곱(stat).

static func _table() -> Dictionary:
	return GameData.table("equipment")


# ---------- 등급 ----------

static func grade_ids() -> Array:
	# 낮은→높은 순. grade_order 우선, 없으면 grades 키 순.
	var t := _table()
	return GameData.ordered_ids(t.get("grades", {}), t.get("grade_order", []))


static func _grade(grade: String) -> Dictionary:
	return (_table().get("grades", {}) as Dictionary).get(grade, {})


static func grade_base(grade: String) -> float:
	return float(_grade(grade).get("base", 0.0))


static func next_grade(grade: String) -> String:
	# 한 단계 위 등급. 최상위면 "".
	var ids := grade_ids()
	var i := ids.find(grade)
	if i < 0 or i + 1 >= ids.size():
		return ""
	return str(ids[i + 1])


# ---------- 강화 ----------

static func _enhance() -> Dictionary:
	return _table().get("enhance", {})


static func enhance_per_lv() -> float:
	return float(_enhance().get("per_lv", 0.10))


static func enhance_max() -> int:
	return int(_enhance().get("max_lv", 20))


static func equip_bonus(grade: String, level: int, stars: int = 0) -> float:
	# 장착 시 스탯 곱 보너스. base × (1 + per_lv × level) × (1 + star_bonus_per × stars).
	# stars 는 신화(최상위) 돌파 전용 — 다른 등급은 항상 0.
	var b := grade_base(grade) * (1.0 + enhance_per_lv() * float(level))
	if stars > 0:
		b *= (1.0 + star_bonus_per() * float(stars))
	return b


# ---------- 신화 돌파/별 ----------

static func _star() -> Dictionary:
	return _table().get("star", {})


static func star_bonus_per() -> float:
	return float(_star().get("bonus_per", 0.20))


static func star_cap() -> int:
	# 별 상한(0 = 무제한).
	return int(_star().get("cap", 0))


static func is_top_grade(grade: String) -> bool:
	# 더 올릴 등급이 없는 최상위(신화) = 합성 불가, 돌파 대상.
	return next_grade(grade) == ""


static func enhance_cost(grade: String, level: int) -> int:
	# 강화 비용(골드). base_cost × grade_mult^등급index × growth^현재레벨.
	var e := _enhance()
	var base := float(e.get("base_cost", 100.0))
	var growth := float(e.get("growth", 1.5))
	var gmult := float(e.get("grade_mult", 4.0))
	var gi: int = grade_ids().find(grade)
	if gi < 0:
		gi = 0
	return int(round(base * pow(gmult, gi) * pow(growth, level)))


static func combine_n() -> int:
	return int(_table().get("combine_n", 4))


# ---------- 풀(종류) ----------

static func pool_ids() -> Array:
	var t := _table()
	return GameData.ordered_ids(t.get("pools", {}), t.get("pool_order", []))


static func _pool(pool_id: String) -> Dictionary:
	return (_table().get("pools", {}) as Dictionary).get(pool_id, {})


static func cost(pool_id: String) -> int:
	return int(_pool(pool_id).get("cost_dia", 100))


static func cost_11(pool_id: String) -> int:
	var p := _pool(pool_id)
	if p.has("cost_dia_11"):
		return int(p.get("cost_dia_11"))
	return cost(pool_id) * 10


static func pool_name(pool_id: String) -> String:
	return str(_pool(pool_id).get("name", pool_id))


static func pool_effect(pool_id: String) -> String:
	return str(_pool(pool_id).get("effect", ""))


static func pool_stat(pool_id: String) -> String:
	# 이 풀이 올리는 스탯("attack"/"hp").
	return str(_pool(pool_id).get("stat", ""))


# ---------- 추첨 / 조회 ----------

static func roll(pool_id: String) -> Dictionary:
	# 등급 가중 추첨 → 그 등급의 풀 아이템 무작위. {item, grade, name, stat}. 카탈로그 비면 {}.
	var p := _pool(pool_id)
	var catalog: Dictionary = p.get("catalog", {})
	if catalog.is_empty():
		return {}
	var grade := _roll_grade()
	var item := random_item_of_grade(pool_id, grade)
	if item == "":
		# 그 등급 아이템이 없으면 카탈로그 전체에서(안전)
		var keys: Array = catalog.keys()
		item = str(keys[randi() % keys.size()])
		grade = str((catalog[item] as Dictionary).get("grade", grade))
	var entry: Dictionary = catalog[item]
	return {"item": item, "grade": grade, "name": str(entry.get("name", item)), "stat": pool_stat(pool_id)}


static func roll_many(pool_id: String, n: int) -> Array:
	var out: Array = []
	for i in range(max(0, n)):
		var r := roll(pool_id)
		if r.is_empty():
			break
		out.append(r)
	return out


static func random_item_of_grade(pool_id: String, grade: String) -> String:
	# 풀 카탈로그에서 해당 등급 아이템 id 무작위 1개. 없으면 "".
	var catalog: Dictionary = _pool(pool_id).get("catalog", {})
	var pool: Array = []
	for eid in catalog:
		if str((catalog[eid] as Dictionary).get("grade", "")) == grade:
			pool.append(eid)
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])


static func item_info(item_id: String) -> Dictionary:
	# 아이템 id → {name, grade, pool, stat}. 모든 풀 catalog 검색. 없으면 {}.
	var pools: Dictionary = _table().get("pools", {})
	for pool_id in pools:
		var pd: Dictionary = pools[pool_id]
		var cat: Dictionary = pd.get("catalog", {})
		if cat.has(item_id):
			var e: Dictionary = cat[item_id]
			return {
				"name": str(e.get("name", item_id)),
				"grade": str(e.get("grade", "common")),
				"pool": str(pool_id),
				"stat": str(pd.get("stat", "")),
			}
	return {}


static func _roll_grade() -> String:
	# grades.weight 가중 추첨(grade_ids 순으로 누적). 합 0이면 최하 등급. 부동소수 폴백 → 마지막.
	return GameData.weighted_pick(grade_ids(), _table().get("grades", {}))
