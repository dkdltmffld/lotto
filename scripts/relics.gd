class_name Relics
extends RefCounted

# 유물(족보 커스텀) 데이터·가챠·효과 강도 — data/relics.json(GameData) 기반. 전부 static.
# 기획: docs/design/족보 스킬 시스템 정리본.md §5.
# 유물 인스턴스 = {uid, effect(catalog key), grade}. 파워=등급으로만(per-유물 레벨업 없음).
# 가챠: ① grades 가중치로 등급 추첨 → ② catalog 에서 효과 무작위 1개. → {effect, grade, name, kind}.

static func _t() -> Dictionary:
	return GameData.table("relics")


# ---------- 등급 ----------

static func grade_ids() -> Array:
	# 낮은→높은 순. grade_order 우선.
	var t := _t()
	return GameData.ordered_ids(t.get("grades", {}), t.get("grade_order", []))


static func grade_index(grade: String) -> int:
	var i := grade_ids().find(grade)
	return i if i >= 0 else 0


# ---------- 카탈로그(효과 템플릿) ----------

static func catalog_ids() -> Array:
	var t := _t()
	return GameData.ordered_ids(t.get("catalog", {}), t.get("catalog_order", []))


static func _entry(effect_id: String) -> Dictionary:
	return (_t().get("catalog", {}) as Dictionary).get(effect_id, {})


static func relic_name(effect_id: String) -> String:
	return str(_entry(effect_id).get("name", effect_id))


static func relic_kind(effect_id: String) -> String:
	# dist_suppress(①) / grade_mult(⑤) / wild(④) / expand(②)
	return str(_entry(effect_id).get("kind", ""))


static func relic_band(effect_id: String) -> String:
	# ⑤ grade_mult 전용: low / mid / high
	return str(_entry(effect_id).get("band", ""))


static func relic_pattern(effect_id: String) -> String:
	# ② expand 전용: two_pair / full_house
	return str(_entry(effect_id).get("pattern", ""))


static func slot_count() -> int:
	return int(_t().get("slots", 5))


# ---------- 효과 강도(등급별 테이블) ----------

static func _grade_val(table_key: String, grade: String, default_v: float) -> float:
	return float((_t().get(table_key, {}) as Dictionary).get(grade, default_v))


static func dist_reduction(grade: String) -> float:
	# ① 저숫자 억제: 가중치 감소율(1.0=완전 제거).
	return _grade_val("dist_suppress", grade, 0.0)


static func grade_bonus(grade: String) -> float:
	# ⑤ 등급 보정: 배율 보너스(+).
	return _grade_val("grade_mult", grade, 0.0)


static func wild_chance(grade: String) -> float:
	# ④ 와일드 발생 확률.
	return _grade_val("wild_chance", grade, 0.0)


static func expand_bonus(grade: String) -> float:
	# ② 족보 확장 패턴 배율 보너스.
	return _grade_val("expand_mult", grade, 0.0)


static func band_range(band: String) -> Array:
	# ⑤ 보정 대상 족보 count 범위 [lo, hi].
	var key := "bands_" + band
	var r: Variant = _t().get(key, [])
	return r if r is Array else []


static func pool_floor() -> int:
	return int(_t().get("pool_floor", 3))


static func wild_cap() -> int:
	return int(_t().get("wild_cap", 2))


# ---------- 가챠 ----------

static func gacha_cost() -> int:
	return int((_t().get("gacha", {}) as Dictionary).get("cost_dust", 100))


static func gacha_cost_11() -> int:
	var g: Dictionary = _t().get("gacha", {})
	if g.has("cost_dust_11"):
		return int(g.get("cost_dust_11"))
	return gacha_cost() * 10


static func roll() -> Dictionary:
	# 등급 가중 추첨 + 효과 무작위. {effect, grade, name, kind}. 카탈로그 비면 {}.
	var ids := catalog_ids()
	if ids.is_empty():
		return {}
	var grade := _roll_grade()
	var effect := str(ids[randi() % ids.size()])
	return {"effect": effect, "grade": grade, "name": relic_name(effect), "kind": relic_kind(effect)}


static func roll_many(n: int) -> Array:
	var out: Array = []
	for i in range(max(0, n)):
		var r := roll()
		if r.is_empty():
			break
		out.append(r)
	return out


# ---------- 무료 확정 소환 (초반 부트스트랩, 사전 설정 유물) ----------

static func _free_pull() -> Dictionary:
	return _t().get("free_pull", {})


static func _free_effects() -> Array:
	return (_free_pull().get("effects", []) as Array)


static func _free_grades() -> Array:
	return (_free_pull().get("grades", []) as Array)


static func free_pull_count() -> int:
	# 무료 확정 소환 가능 총 횟수 = 사전 설정 효과 리스트 길이. 0이면 비활성.
	return _free_effects().size()


static func free_pull_grant(index: int) -> Dictionary:
	# index 번째 무료 확정 소환이 줄 **사전 설정** 유물. {effect, grade, name, kind}. 범위 밖이면 {}.
	# grade 가 effects 보다 짧으면 최하 등급 폴백.
	var effs := _free_effects()
	if index < 0 or index >= effs.size():
		return {}
	var effect := str(effs[index])
	var grades := _free_grades()
	var grade := str(grades[index]) if index < grades.size() else _default_grade()
	return {"effect": effect, "grade": grade, "name": relic_name(effect), "kind": relic_kind(effect)}


static func _default_grade() -> String:
	var ids := grade_ids()
	return str(ids[0]) if not ids.is_empty() else ""


# ---------- 가루 구매 (상점 > 재화, 다이아 결제) ----------

static func _dust_shop() -> Dictionary:
	return _t().get("dust_shop", {})


static func dust_shop_count() -> int:
	return (_dust_shop().get("amounts", []) as Array).size()


static func dust_shop_pack(index: int) -> Dictionary:
	# index 번째 가루 구매 팩. {amount(가루), cost(다이아)}. 범위 밖이면 {}.
	var amts := (_dust_shop().get("amounts", []) as Array)
	if index < 0 or index >= amts.size():
		return {}
	var costs := (_dust_shop().get("costs", []) as Array)
	var cost: int = int(costs[index]) if index < costs.size() else 0
	return {"amount": int(amts[index]), "cost": cost}


# ---------- 표시용 ----------

static func band_name(band: String) -> String:
	match band:
		"low": return "저족보"
		"mid": return "중족보"
		"high": return "고족보"
	return band


static func pattern_name(pattern: String) -> String:
	match pattern:
		"two_pair": return "투페어"
		"full_house": return "풀하우스"
	return pattern


static func relic_desc(effect_id: String, grade: String) -> String:
	# 효과+등급 → 짧은 한글 설명(UI 행/결과 팝업용).
	match relic_kind(effect_id):
		"dist_suppress":
			var r: float = dist_reduction(grade)
			return "낮은 숫자 제거" if r >= 1.0 else "낮은 숫자 -%d%%" % int(round(r * 100.0))
		"grade_mult":
			return "%s 배율 +%d%%" % [band_name(relic_band(effect_id)), int(round(grade_bonus(grade) * 100.0))]
		"wild":
			return "와일드 %d%% (매칭+1)" % int(round(wild_chance(grade) * 100.0))
		"expand":
			return "%s 인정 +%d%%" % [pattern_name(relic_pattern(effect_id)), int(round(expand_bonus(grade) * 100.0))]
	return ""


static func _roll_grade() -> String:
	return GameData.weighted_pick(grade_ids(), _t().get("grades", {}))
