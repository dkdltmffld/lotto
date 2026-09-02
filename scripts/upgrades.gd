class_name Upgrades
extends RefCounted

# 성장(강화) 트랙. 레벨은 BackendService에 "upg_<id>"로 저장, 골드는 BackendService.gold.
# 데이터는 data/upgrades.json (원본 data/src/upgrades.yaml, 변환 tools/build_data.gd).
# 기획서: docs/design/강화 시스템 정리본.md
#
# kind: char(캐릭터=공격력/생존) / card(복권=배율/자동속도) / util(저장소)
# value(level) = base_val + per_level × level   (선형, 싸고 자주 누르는 결)
# cost(level)  = base_cost × cost_growth^level
# cost()는 max_level 도달 시 INF 반환(만렙).

static func all_ids() -> Array:
	return GameData.subtable("upgrades", "order", [])


static func def(id: String) -> Dictionary:
	var tracks: Dictionary = GameData.subtable("upgrades", "tracks", {})
	return tracks.get(id, {})


static func get_level(id: String) -> int:
	return int(BackendService.get_value("upg_" + id, 0))


static func value(id: String) -> float:
	# ⚠️ 무가드 tracks[id]는 data/upgrades.json 누락(웹 export include_filter 누락 등) 시 빈 dict라 크래시.
	#    .get 기반으로 — 누락이 "전투 첫 공격 하드 크래시"가 아니라 안전값(0)으로 degrade.
	var tracks: Dictionary = GameData.subtable("upgrades", "tracks", {})
	var d: Dictionary = tracks.get(id, {})
	return float(d.get("base_val", 0.0)) + float(d.get("per_level", 0.0)) * get_level(id)


static func max_level(id: String) -> int:
	var tracks: Dictionary = GameData.subtable("upgrades", "tracks", {})
	var d: Dictionary = tracks.get(id, {})
	return int(d.get("max_level", -1))  # -1 = 무제한


static func is_maxed(id: String) -> bool:
	var ml: int = max_level(id)
	return ml >= 0 and get_level(id) >= ml


static func cost(id: String) -> float:
	if is_maxed(id):
		return INF
	var tracks: Dictionary = GameData.subtable("upgrades", "tracks", {})
	var d: Dictionary = tracks.get(id, {})
	if d.is_empty():
		return INF  # 데이터 누락 → 구매 불가(살 수 없게 막아 안전)
	return float(d.get("base_cost", INF)) * pow(float(d.get("cost_growth", 1.0)), get_level(id))


static func can_afford(id: String) -> bool:
	return not is_maxed(id) and BackendService.get_gold() >= cost(id)


# 구매 시도. 성공 시 골드 차감 + 레벨+1(메모리·dirty). 성공 여부 반환.
# flush는 호출 측이 구매 묶음 끝에 1회만 한다(롱프레스 연타 중 디스크 쓰기 반복 방지).
static func buy(id: String) -> bool:
	var tracks: Dictionary = GameData.subtable("upgrades", "tracks", {})
	if not tracks.has(id) or is_maxed(id):
		return false
	var c: float = cost(id)
	if not BackendService.spend_gold(c):
		return false
	BackendService.set_value("upg_" + id, get_level(id) + 1)  # set_value가 dirty 표시
	return true
