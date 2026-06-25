class_name Quests
extends RefCounted

# 퀘스트 — 유저에게 단기 목표를 연쇄로 제시하는 목표 시스템. (기획: docs/design/퀘스트 시스템 정리본.md)
# 이 파일은 **카탈로그 로드(data/quests.json) + 순수 판정 로직**만 소유한다(BackendService 무참조 → 헤드리스 테스트 가능).
# 실제 수령(재화 지급·claimed 저장·flush)·진행도 stat 읽기는 quest_panel.gd / game.gd 가 BackendService API로 수행한다.
#
# 카탈로그 원본 = 메인/일일 시트 분리: data/src/quests_main.yaml·quests_daily.yaml
#   → data/quests_main.json·quests_daily.json → GameData.table(...). 수치(target/보상)는 잠정.
# 진행도(기획 §4): 누적 stat 델타. 메인=절대 누적(get_stat, 소급 완료), 일일=get_stat - 그날 base(롤오버 시 스냅샷).
# 운 기반 목표(잭팟/특정 족보/특정 등급)는 기본 퀘스트에서 제외(기획 §2-2) — 전부 행동량 stat.
# 보상 재화 화이트리스트 = gold/dia/dust(우편함과 동일 경계). 기본=다이아(기획 §6).
#
# ⚠️ rewards 는 yaml 파서가 dict 리스트 미지원 → 통화키 맵 {dia:50, dust:100} 으로 저장하고
#    여기서 [{currency, amount}] 배열로 복원한다(rewards 배열 순서 = ALLOWED_CURRENCIES 고정).
# ⚠️ 퀘스트 정렬 = yaml 작성 순서(별도 order 없음 — build_data sort_keys=false 가 파일 순서 보존).
# ⚠️ 일일 `소환` 타입은 개발만 하고 1차 노출 비활성(exposed=false, 기획 §3-2·§11).

const ALLOWED_CURRENCIES: Array = ["gold", "dia", "dust"]

static var _main_cache: Array = []
static var _daily_cache: Array = []


# ---------- 카탈로그 로드 (메인/일일 시트 → 1회 빌드 캐시) ----------
static func _rewards_to_array(raw: Variant) -> Array:
	# 통화키 맵 {dia:50, dust:100} → [{currency, amount}] (whitelist 고정 순서로 안정적 출력).
	var out: Array = []
	if raw is Dictionary:
		for cur in ALLOWED_CURRENCIES:
			if (raw as Dictionary).has(cur):
				out.append({"currency": cur, "amount": float((raw as Dictionary)[cur])})
	return out


static func _build(table_name: String) -> Array:
	# 단일 퀘스트 시트(quests 맵) → 퀘스트 dict 배열. 각 dict = {id, title, desc, stat, target, rewards[], exposed}.
	# 정렬 = **yaml 작성 순서(파일 위→아래)**. 별도 order 리스트 없음 — build_data 가 sort_keys=false 로
	#   파일 순서를 json·런타임까지 보존하므로 맵 키 순회가 곧 작성 순서다.
	var t: Dictionary = GameData.table(table_name)
	var cat: Dictionary = t.get("quests", {})
	var out: Array = []
	for id in cat:
		var raw: Dictionary = cat.get(id, {})
		out.append({
			"id": id,
			"title": str(raw.get("title", id)),
			"desc": str(raw.get("desc", "")),
			"stat": str(raw.get("stat", "")),
			"target": int(raw.get("target", 0)),
			"rewards": _rewards_to_array(raw.get("rewards", {})),
			"exposed": bool(raw.get("exposed", true)),
		})
	return out


static func main_quests() -> Array:
	if _main_cache.is_empty():
		_main_cache = _build("quests_main")
	return _main_cache


static func _daily_all() -> Array:
	if _daily_cache.is_empty():
		_daily_cache = _build("quests_daily")
	return _daily_cache


static func daily_quests(include_hidden: bool = false) -> Array:
	# 1차 노출(exposed=true)만 기본 반환. include_hidden=true 면 소환 포함(개발/테스트용).
	if include_hidden:
		return _daily_all()
	var out: Array = []
	for q in _daily_all():
		if bool((q as Dictionary).get("exposed", true)):
			out.append(q)
	return out


static func daily_stat_keys() -> Array:
	# 일일 base 스냅샷에 필요한 stat 키(중복 제거) — 노출/비노출 모두 포함(소환도 base 필요).
	var seen: Dictionary = {}
	for q in _daily_all():
		seen[str((q as Dictionary).get("stat", ""))] = true
	return seen.keys()


# ---------- 진행도 / 완료 (순수 — stat 값을 인자로) ----------
static func main_progress(q: Dictionary, stats: Dictionary) -> int:
	# 절대 누적(소급 완료). target 으로 캡.
	return mini(int(stats.get(str(q.get("stat", "")), 0)), int(q.get("target", 0)))


static func main_complete(q: Dictionary, stats: Dictionary) -> bool:
	return int(stats.get(str(q.get("stat", "")), 0)) >= int(q.get("target", 0))


static func daily_delta(q: Dictionary, stats: Dictionary, base: Dictionary) -> int:
	# 그날 base 대비 증가분(음수 방지 — base 가 현재보다 클 일은 없지만 손상 방어).
	var key: String = str(q.get("stat", ""))
	return maxi(0, int(stats.get(key, 0)) - int(base.get(key, 0)))


static func daily_progress(q: Dictionary, stats: Dictionary, base: Dictionary) -> int:
	return mini(daily_delta(q, stats, base), int(q.get("target", 0)))


static func daily_complete(q: Dictionary, stats: Dictionary, base: Dictionary) -> bool:
	return daily_delta(q, stats, base) >= int(q.get("target", 0))


# ---------- 재화 화이트리스트 (우편함과 동일 경계) ----------
static func is_currency_allowed(key: String) -> bool:
	return ALLOWED_CURRENCIES.has(key)


static func valid_rewards(rewards: Array) -> Array:
	# 지급 가능한 보상만(양수 + 허용 재화). 수령 직전 이걸로 "0개면 claimed 안 찍음"(무보상 수령완료 방지, 우편함 §6).
	var out: Array = []
	for r in rewards:
		var rd := r as Dictionary
		if float(rd.get("amount", 0)) > 0.0 and is_currency_allowed(str(rd.get("currency", ""))):
			out.append(rd)
	return out


# ---------- red dot 판정 (받을 수 있는 퀘스트가 하나라도 있나) ----------
static func has_claimable_main(stats: Dictionary, main_claimed: Dictionary) -> bool:
	# 메인 = HUD 트래커가 자체 "받기!"로 표시 — 상단 버튼 red dot 엔 쓰지 않음(트래커 전용 판정).
	for q in main_quests():
		var qd := q as Dictionary
		if not bool(main_claimed.get(str(qd.get("id", "")), false)) \
				and main_complete(qd, stats) and not valid_rewards(qd.get("rewards", [])).is_empty():
			return true
	return false


static func has_claimable_daily(stats: Dictionary, daily_base: Dictionary, daily_claimed: Dictionary) -> bool:
	# 상단 "퀘스트"(일일 패널) 버튼 red dot 판정. 비노출(소환) 일일은 제외.
	for q in _daily_all():
		var qd := q as Dictionary
		if not bool(qd.get("exposed", true)):
			continue
		if not bool(daily_claimed.get(str(qd.get("id", "")), false)) \
				and daily_complete(qd, stats, daily_base) and not valid_rewards(qd.get("rewards", [])).is_empty():
			return true
	return false


static func has_claimable(stats: Dictionary, daily_base: Dictionary, main_claimed: Dictionary, daily_claimed: Dictionary) -> bool:
	# 메인+일일 통합(하위호환). 분리 판정은 has_claimable_main / has_claimable_daily.
	return has_claimable_main(stats, main_claimed) or has_claimable_daily(stats, daily_base, daily_claimed)
