class_name Achievements
extends RefCounted

# 업적 시스템 (프론트엔드). 카탈로그 + 조건 판정 + 해금 처리를 담당한다.
# 해금 결과의 "저장/불러오기"만 BackendService(순수 저장소)에 위임한다:
#   - 해금 시: BackendService.set_value("achievements", {...}) 로 저장
#   - 목록 조회 시: BackendService.get_value("achievements", {}) 로 불러옴
# 즉 게임 규칙은 여기, 영속화는 백엔드. (설계: docs/design/백엔드·로그인 정리본)
#
# 카탈로그는 data/achievements.json (원본 data/src/achievements.yaml, 변환 tools/build_data.gd).
# 수치(threshold)는 잠정 — 밸런스 확정 시 튜닝.

const SAVE_KEY := "achievements"


static func exists(id: String) -> bool:
	var cat: Dictionary = GameData.subtable("achievements", "catalog", {})
	return cat.has(id)


static func get_def(id: String) -> Dictionary:
	var cat: Dictionary = GameData.subtable("achievements", "catalog", {})
	var d: Dictionary = (cat.get(id, {}) as Dictionary).duplicate()
	d["id"] = id
	return d


static func all_ids() -> Array:
	var cat: Dictionary = GameData.subtable("achievements", "catalog", {})
	return cat.keys()


# 저장소에서 해금 상태 dict를 불러옴 ({id: true}).
static func _unlocked_map() -> Dictionary:
	return BackendService.get_value(SAVE_KEY, {})


static func is_unlocked(id: String) -> bool:
	return bool(_unlocked_map().get(id, false))


static func get_unlocked_ids() -> Array:
	var out: Array = []
	var m := _unlocked_map()
	for id in m:
		if m[id]:
			out.append(id)
	return out


# 해금 처리. 새로 해금되면 def(Dictionary) 반환, 이미/없음이면 빈 {}.
# 결과를 BackendService에 저장(영속화)하고, UI 토스트는 호출 측이 반환값으로 처리.
static func unlock(id: String) -> Dictionary:
	var cat: Dictionary = GameData.subtable("achievements", "catalog", {})
	if not cat.has(id):
		push_warning("[Achievements] 알 수 없는 업적 id: %s" % id)
		return {}
	var m := _unlocked_map()
	if m.get(id, false):
		return {}
	m[id] = true
	BackendService.set_value(SAVE_KEY, m)  # 저장 위임
	return get_def(id)


# stat 임계값 기반 업적을 평가해 새로 달성된 것을 unlock. 새로 해금된 def 배열 반환.
static func check_stat_achievements() -> Array:
	var cat: Dictionary = GameData.subtable("achievements", "catalog", {})
	var newly: Array = []
	for id in cat:
		var entry: Dictionary = cat[id]
		if not entry.has("stat") or is_unlocked(id):
			continue
		if _stat_value(str(entry["stat"])) >= int(entry["threshold"]):
			var unlocked := unlock(id)
			if not unlocked.is_empty():
				newly.append(unlocked)
	return newly


static func _stat_value(key: String) -> int:
	if key == "high_score":
		return BackendService.get_high_score()
	return BackendService.get_stat(key)
