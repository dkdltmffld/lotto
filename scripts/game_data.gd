class_name GameData
extends RefCounted

# 게임 데이터(밸런스·강화·업적·적변종)의 단일 로드 진입점.
# 원본은 data/src/*.yaml, 게임이 읽는 산출물은 data/*.json (변환: tools/build_data.gd).
# 1회 로드 후 캐시. 파일이 없으면 빈 값 + 에러 로그(개발 중 변환 누락 진단용).
#
# ⚠️ data/*.json 은 비리소스라 웹 export 에 자동 포함되지 않음 →
#    export_presets.cfg include_filter="data/*.json" 필요(설정됨).

const DIR := "res://data/"

static var _cache: Dictionary = {}


static func table(name: String) -> Variant:
	if _cache.has(name):
		return _cache[name]
	var path: String = DIR + name + ".json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[GameData] 로드 실패: %s — tools/build_data.gd 를 돌렸나요?" % path)
		_cache[name] = {}
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_error("[GameData] JSON 파싱 실패: %s" % path)
		parsed = {}
	if not (parsed is Dictionary):
		push_error("[GameData] %s: top-level not a Dictionary" % name)
		parsed = {}
	_cache[name] = parsed
	return parsed


static func subtable(name: String, key: String, default: Variant = {}) -> Variant:
	# 테이블의 하위 키 조회. table()이 영구 캐시이므로 매 호출이 같은 객체 참조를 반환 —
	# 각 클래스가 _loaded 플래그로 스냅샷을 들고 있을 필요 없음(캐시 위의 캐시 제거).
	var t: Variant = table(name)
	if t is Dictionary:
		return (t as Dictionary).get(key, default)
	return default


static func ordered_ids(dict: Dictionary, order: Array) -> Array:
	# "order 배열 우선 + dict 잔여 키 추가" 정렬 패턴 공용화 (gacha/relics의 grade/pool/catalog ids).
	# dict.has(id)는 raw id로, ids 멤버는 str(id)로 — 원본 의미 그대로. 매 호출 새 Array 반환.
	var ids: Array = []
	for id in order:
		if dict.has(id) and not ids.has(str(id)):
			ids.append(str(id))
	for id in dict:
		if not ids.has(str(id)):
			ids.append(str(id))
	return ids


static func weighted_pick(ids: Array, table_dict: Dictionary, weight_key: String = "weight") -> String:
	# 가중 추첨 공용화 (gacha/relics _roll_grade). 빈 ids → "" / 합 0 → ids[0] / 부동소수 폴백 → 마지막.
	# randf()는 합이 양수일 때 정확히 1회 호출(RNG 스트림 소비 패턴 보존).
	if ids.is_empty():
		return ""
	var total: float = 0.0
	for k in ids:
		total += float((table_dict.get(k, {}) as Dictionary).get(weight_key, 0.0))
	if total <= 0.0:
		return str(ids[0])
	var r: float = randf() * total
	var acc: float = 0.0
	for k in ids:
		acc += float((table_dict.get(k, {}) as Dictionary).get(weight_key, 0.0))
		if r < acc:
			return str(k)
	return str(ids[ids.size() - 1])
