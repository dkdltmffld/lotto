extends RefCounted

# 유물 효과 계산 — 장착 유물(BackendService)을 읽어 스크래치 분포·스킬 배율을 산출하는 순수 계산.
# game.gd 의 god object 완화(2026-06-10 리팩토링): 상태를 갖지 않으므로 static 으로 분리.
# ⚠️ class_name 없음 — game.gd 는 const RelicEffectsScript := preload(...) 로 참조(프로젝트 표준).
# 기획: docs/design/족보 스킬 시스템 정리본.md §5-2 (효과 ①분포 ⑤보정 ④와일드 ②확장).

const RelicsScript = preload("res://scripts/relics.gd")


static func equipped_of_kind(kind: String) -> Array:
	# 장착 유물 중 효과 종류(kind)가 일치하는 인스턴스만. (dist_suppress/grade_mult/wild/expand)
	var out: Array = []
	for inst in BackendService.get_equipped_relics():
		if RelicsScript.relic_kind(str(inst.get("effect", ""))) == kind:
			out.append(inst)
	return out


static func number_weights() -> Dictionary:
	# ①분포: 장착된 dist_suppress 유물 → 1~9 가중치. 없으면 {}(균등).
	# 강한(감소율 큰) 유물부터 낮은 숫자에 차례로 적용 → 풀이 고숫자 쪽으로 좁혀짐.
	# degeneracy 방지: 가중치 양수 숫자가 pool_floor 미만으로 줄지 않게 완전 제거를 강한 감소로 대체.
	var grades: Array = []
	for inst in equipped_of_kind("dist_suppress"):
		grades.append(str(inst.get("grade", "")))
	if grades.is_empty():
		return {}
	grades.sort_custom(func(a, b): return RelicsScript.dist_reduction(a) > RelicsScript.dist_reduction(b))
	var w: Dictionary = {}
	for n in range(1, 10):
		w[n] = 1.0
	var floor_n: int = RelicsScript.pool_floor()
	var target: int = 1
	for g in grades:
		if target > 9:
			break
		var red: float = RelicsScript.dist_reduction(g)
		# 이 숫자를 제거(red>=1)하면 양수 가중치 개수가 floor 미만이 되는지 검사
		if red >= 1.0:
			var positive: int = 0
			for n in w:
				if float(w[n]) > 0.0:
					positive += 1
			if positive - 1 < floor_n:
				red = 0.9  # floor 보호: 완전 제거 대신 강한 감소
		w[target] = float(w[target]) * (1.0 - red)
		target += 1
	return w


static func wild_chances() -> Array:
	# ④와일드: 장착된 wild 유물들의 발생 확률 배열(스크래치가 카드마다 각각 굴림).
	var out: Array = []
	for inst in equipped_of_kind("wild"):
		out.append(RelicsScript.wild_chance(str(inst.get("grade", ""))))
	return out


static func skill_mult(count: int) -> float:
	# ⑤등급 보정: 족보 count가 밴드 범위에 드는 grade_mult 유물들의 보너스 합산 → 배율.
	var m: float = 1.0
	for inst in equipped_of_kind("grade_mult"):
		var eff: String = str(inst.get("effect", ""))
		var rng: Array = RelicsScript.band_range(RelicsScript.relic_band(eff))
		if rng.size() == 2 and count >= int(rng[0]) and count <= int(rng[1]):
			m += RelicsScript.grade_bonus(str(inst.get("grade", "")))
	return m


static func expand_mult(groups: Array) -> float:
	# ②족보 확장: 장착된 expand 유물의 패턴(투페어/풀하우스)이 그룹 묶음과 맞으면 배율 보너스 합산.
	var m: float = 1.0
	for inst in equipped_of_kind("expand"):
		var eff: String = str(inst.get("effect", ""))
		if _pattern_matches(RelicsScript.relic_pattern(eff), groups):
			m += RelicsScript.expand_bonus(str(inst.get("grade", "")))
	return m


static func _pattern_matches(pattern: String, groups: Array) -> bool:
	# 포커식 그룹 랭킹: 큰 그룹이 우선 → 투페어=최대 2+2짜리 둘 / 풀하우스=최대 3+보조 2이상.
	# (groups[0]>=4면 이미 포카드+ 라 두 패턴 모두 불성립 = 자동 보장.)
	if groups.size() < 2:
		return false
	var g0: int = int(groups[0])
	var g1: int = int(groups[1])
	match pattern:
		"two_pair":
			return g0 == 2 and g1 == 2
		"full_house":
			return g0 == 3 and g1 >= 2
	return false
