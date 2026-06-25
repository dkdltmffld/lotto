class_name HandEvaluator
extends RefCounted

# 숫자 배열(와일드 칸 제외)을 받아 족보 평가 결과 반환.
# 결과: { "count": int, "value": int, "mult": int, "name": String, "groups": Array }
#   mult = count² × value (족보배율) / groups = 그룹 크기 내림차순(②족보확장 판정용, 와일드 포함).
# wild_count(④): 와일드 칸 수 — 어떤 숫자로도 취급되어 **최대 그룹에 합류**(매칭 +wild_count).
static func evaluate(numbers: Array, wild_count: int = 0) -> Dictionary:
	var freq: Dictionary = {}
	for n in numbers:
		freq[n] = int(freq.get(n, 0)) + 1

	# 가장 많은 등장 횟수 찾기 (count 우선, 동점이면 value 더 높은 쪽)
	var best_count: int = 0
	var best_value: int = 0
	for n in freq:
		var c: int = freq[n]
		if c > best_count or (c == best_count and n > best_value):
			best_count = c
			best_value = n

	# 그룹 크기 묶음(내림차순). 와일드는 최대 그룹에 더한다(②족보확장 = 그룹 묶음 포커 랭킹).
	var groups: Array = []
	for n in freq:
		groups.append(int(freq[n]))
	groups.sort()
	groups.reverse()
	var w: int = max(0, wild_count)
	if groups.is_empty():
		if w > 0:
			groups = [w]
	else:
		groups[0] += w

	# 와일드는 최대 그룹(best_value)에 합류 → 매칭 +wild_count.
	best_count += w

	# 복권 족보배율 (count² × value). 최종 데미지는 game.gd에서 공격력·복권배율·유물 보정과 곱한다.
	var mult: int = best_count * best_count * best_value
	var hand_name: String = "%d개 %d" % [best_count, best_value]

	return {
		"count": best_count,
		"value": best_value,
		"mult": mult,
		"name": hand_name,
		"groups": groups,
	}
