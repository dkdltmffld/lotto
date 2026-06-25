extends Node

# 백엔드 파사드 (autoload "BackendService"). 게임 코드는 이 싱글톤만 호출한다.
# 실제 영속화/리더보드/로그인은 BackendProvider 구현이 담당:
#   - 웹: KplayBackendProvider (kplay.games postMessage)
#   - 비웹(에디터·데스크탑): LocalBackendProvider (user:// 파일)
# 저장 데이터는 메모리에 _data(Dictionary)로 유지하고 JSON 한 덩어리로 영속화 (kplay 한도 10KB).
#
# ⚠️ class_name 없음 — autoload 이름과 충돌 방지. 전역 식별자 BackendService 로 접근.

signal save_ready                                     # 최초 로드 완료
signal login_changed(logged_in: bool)                 # 인증 로그인 상태 변화
signal logged_out                                     # 로그아웃 완료 → 로그인 화면 복귀 신호
signal account_deleted                                # 계정 탈퇴(로컬+서버 삭제) 완료 → 로그인 화면 복귀
signal score_submitted(success: bool, rank: int)      # 랭킹 점수 제출 결과

const SAVE_VERSION := 1
const GachaScript = preload("res://scripts/gacha.gd")  # 장착 보너스·강화비용·합성·등급 계산용
const RelicsScript = preload("res://scripts/relics.gd")  # 유물 슬롯 수·등급 인덱스 (단일 출처 = Relics)
const DungeonDataScript = preload("res://scripts/dungeon_data.gd")  # 던전 층 보상(첫 돌파) 조회

# 계정 종류 (로그인 시스템 정리본 §2)
const ACCOUNT_NONE := ""
const ACCOUNT_GOOGLE := "google"
const ACCOUNT_KPLAY := "kplay"
const ACCOUNT_GUEST := "guest"

var is_ready: bool = false
var is_fresh_save: bool = false       # 현재 슬롯 첫 시작(저장 데이터 없음). 튜토리얼 등장 조건
var is_logged_in: bool = false        # 인증 계정(google/kplay)만 true. 게스트는 false
var user_name: String = ""
var account_type: String = ACCOUNT_NONE

var _provider: BackendProvider
var _data: Dictionary = {}
var _dirty: bool = false
var _js_flush_cb = null  # 웹 전용 JavaScriptObject(콜백) — GC 방지용 보관

# 저장 트리거(이중): 이산 이벤트는 즉시 flush(), 연속 변동은 주기적 autosave.
const AUTOSAVE_INTERVAL: float = 15.0  # 초. dirty면 주기적으로 저장
var _autosave_accum: float = 0.0


func _ready() -> void:
	# 로드 완료 전에도 스키마가 유효하도록 먼저 기본값으로 초기화
	_data = _migrate({})
	if OS.has_feature("web"):
		_provider = KplayBackendProvider.new()
	else:
		_provider = LocalBackendProvider.new()
	_provider.login_changed.connect(_on_provider_login_changed)
	_provider.score_submitted.connect(_on_provider_score_submitted)
	_provider.resync_needed.connect(_on_provider_resync_needed)
	_setup_web_lifecycle_flush()
	await _load()


func _on_provider_resync_needed() -> void:
	# (웹) 로그인 타임아웃 뒤 늦게 클라우드가 localStorage에 반영됨 → 현재 슬롯을 다시 읽어 stale _data 교체.
	# (이게 없으면 다음 저장이 stale _data 로 방금 받은 클라우드 데이터를 덮어써 진행도 롤백)
	# save_ready 는 재발화하지 않는다(최초 로드용) — _data 만 최신으로 스왑.
	var loaded: Dictionary = await _provider.load_all()
	if not loaded.is_empty():
		_data = _migrate(loaded)
		_dirty = false


func _setup_web_lifecycle_flush() -> void:
	# 브라우저는 탭 전환/종료 시 WM_CLOSE/APP_PAUSED 알림을 안정적으로 보내지 않는다.
	# → visibilitychange(hidden)·pagehide 에서 best-effort flush 를 걸어, ~15s autosave 사이
	#   닫으면 그만큼 골드가 유실되던 문제를 줄인다. (웹 전용)
	if not OS.has_feature("web"):
		return
	_js_flush_cb = JavaScriptBridge.create_callback(_on_web_hide)
	var win = JavaScriptBridge.get_interface("window")
	if win != null:
		win.addEventListener("visibilitychange", _js_flush_cb)
		win.addEventListener("pagehide", _js_flush_cb)


func _on_web_hide(args: Array) -> void:
	# visibilitychange 는 show/hide 양쪽에서 발화 → 숨김일 때만 저장. pagehide(종료)는 항상.
	var ev_type := ""
	if args.size() > 0 and args[0] != null:
		ev_type = str(args[0].type)
	if ev_type == "visibilitychange":
		var doc = JavaScriptBridge.get_interface("document")
		if doc != null and str(doc.visibilityState) == "visible":
			return  # 다시 보이게 된 경우(show)는 저장 불필요
	if _dirty and _provider != null:
		_persist_now()


func _process(delta: float) -> void:
	# 주기적 autosave (연속 골드 수입 등). dirty일 때만 실제 저장.
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		flush()


func _load() -> void:
	var loaded: Dictionary = await _provider.load_all()
	# 현재 슬롯에 저장 데이터가 없으면(첫 시작) true. 튜토리얼 등장 조건 등에 사용.
	is_fresh_save = loaded.is_empty()
	_data = _migrate(loaded)
	_dirty = false
	is_ready = true
	save_ready.emit()


# _migrate 숫자 키 기본값 테이블 (기본값의 int/float 타입이 _num_or 폴백 타입이 된다).
#   dia = 다이아(장비 뽑기 재화) / equip_seq = 인스턴스 uid 시퀀스(고유 id 발급)
#   dust = 유물 가루(유물 가챠/합성 재화) / relic_seq = 유물 인스턴스 uid 시퀀스
#   dust_boss_max = 가루를 지급한 최고 보스 스테이지(보스 첫 클리어 가루 재파밍 차단, 진행 선형이라 단일 int로 충분)
#   relic_free_used = 사용한 무료 확정 소환 횟수(초반 부트스트랩 — Relics.free_pull_count 까지)
const _NUM_DEFAULTS := {"high_score": 0, "gold": 0.0, "dia": 0.0, "stage": 1, "last_seen": 0, "equip_seq": 0, "dust": 0.0, "relic_seq": 0, "dust_boss_max": 0, "relic_free_used": 0, "dungeon_max_cleared": 0}


func _migrate(data: Dictionary) -> Dictionary:
	# 기본 스키마 보장 + 향후 버전 마이그레이션 자리. (idempotent)
	# ⚠️ 손상/구버전 세이브 방어: 키가 없거나 **타입이 어긋나면** 기본값으로 복구한다.
	#    (이전엔 has()만 검사 → 잘못된 타입[예: gold가 문자열, equips가 배열]이 그대로 통과해
	#     이후 캐스팅·연산에서 깨질 수 있었음. JSON 숫자는 float로 로드되므로 int/float 모두 허용.)
	var d := data.duplicate(true)
	d["version"] = SAVE_VERSION
	for k in _NUM_DEFAULTS:
		d[k] = _num_or(d.get(k), _NUM_DEFAULTS[k])
	_ensure_container(d, "relics", [])                            # 보유 유물 인스턴스 [{uid,effect,grade}]
	_ensure_container(d, "relic_slots", [])                       # 장착 슬롯(유물 uid 배열, 최대 slot_count)
	_ensure_container(d, "equips", {"weapon": [], "armor": []})   # 종류별 보유 장비 인스턴스 [{uid,item,level}]
	for pk in ["weapon", "armor"]:
		if not ((d["equips"] as Dictionary).get(pk) is Array):
			(d["equips"] as Dictionary)[pk] = []
	_ensure_container(d, "equipped", {"weapon": "", "armor": ""}) # 종류별 장착 uid("" = 미장착)
	_ensure_container(d, "stats", {})
	_ensure_container(d, "achievements", {})
	_ensure_container(d, "settings", {})
	_ensure_container(d, "mail_claimed", {})  # 수령한 우편 id 도장 {id:true} (우편함 — 카탈로그 제거 GC로 누적 완화)
	_ensure_container(d, "quests_daily", {"date": "", "base": {}, "claimed": {}})  # 일일 퀘스트 {날짜, base 스냅샷, 수령 도장}
	_ensure_container(d, "quests_main_claimed", {})  # 메인 퀘스트 수령 도장 {id:true}
	_ensure_container(d, "dungeon", _default_dungeon())  # 던전 데일리: 입장권/리셋날짜/자동등반(기본 켜짐)
	# 자동 등반 기본 켜짐 1회 마이그레이션: 구버전(기본 off로 저장된)·토글 추가 이전 세이브를
	# 한 번만 on 으로. auto_init 마커가 없으면 강제 on + 마커 → 이후 설정에서 끈 건 그대로 유지된다.
	var dgc: Dictionary = d["dungeon"]
	if not dgc.has("auto_init"):
		dgc["auto"] = true
		dgc["auto_init"] = true
	return d


func _num_or(v: Variant, default_value: Variant) -> Variant:
	# 숫자(int/float)면 그대로, 아니면 기본값. 손상 세이브의 잘못된 타입 방어.
	if v is int or v is float:
		return v
	return default_value


func _ensure_container(d: Dictionary, key: String, default_value: Variant) -> void:
	# 키가 없거나 타입이 어긋나면 기본값 컨테이너로 복구. 손상 세이브 방어.
	# ⚠️ 컨테이너 전용 — 스칼라엔 쓰지 말 것(_num_or가 int/float 모두 허용하는 것과 달리 typeof 비교는 int↔float를 구분).
	# ⚠️ 기본값 컨테이너는 반드시 호출부 리터럴로 — const 테이블에 넣으면 Godot 4 const 컨테이너의
	#    재귀 read-only가 세이브 데이터에 전파돼 이후 append/수정이 깨짐.
	if typeof(d.get(key)) != typeof(default_value):
		d[key] = default_value


# ---------- 저장 데이터: 점수/통계/설정 ----------

func get_high_score() -> int:
	return int(_data.get("high_score", 0))


func try_set_high_score(score: int) -> bool:
	# 신기록이면 갱신하고 true 반환.
	if score > get_high_score():
		_data["high_score"] = score
		_mark_dirty()
		return true
	return false


func get_stat(key: String) -> int:
	# level_<track> = 강화 트랙의 현재 레벨(파생 stat — 퀘스트 "N단계 도달"용, 실제 레벨이라 소급/리셋 반영).
	# 그 외는 저장된 누적 stat. (upgrades_bought_<track> = 구매 횟수 누적과 구분 — 환생 시 달라짐)
	if key.begins_with("level_"):
		return Upgrades.get_level(key.trim_prefix("level_"))
	return int((_data["stats"] as Dictionary).get(key, 0))


func add_stat(key: String, amount: int = 1) -> int:
	var stats: Dictionary = _data["stats"]
	var v := int(stats.get(key, 0)) + amount
	stats[key] = v
	_mark_dirty()
	return v


func get_stats() -> Dictionary:
	# 누적 stat + 파생 stat(`level_<track>` = 트랙 현재 레벨). 퀘스트 진행도 일괄 계산용(읽기 전용).
	# ⚠️ _data["stats"] 사본 + 레벨 머지를 반환 — 반환 dict 를 변형하지 말 것(저장/누적은 add_stat/_data["stats"]만).
	var out: Dictionary = (_data["stats"] as Dictionary).duplicate()
	for tid in Upgrades.all_ids():
		out["level_" + str(tid)] = Upgrades.get_level(str(tid))
	return out


# ---------- 재화 (통화) — 키 = 통화 이름. 골드 / 다이아 등. ----------
# 통화 일반화: 새 재화 추가 시 _migrate 기본값만 넣으면 됨(별도 함수 불필요).

const CUR_GOLD := "gold"
const CUR_DIA := "dia"   # 다이아(임시 명칭) — 장비 뽑기 등 BM 재화
const CUR_DUST := "dust" # 유물 가루 — 유물 가챠/합성 재화(중복 분해로 획득)

func get_currency(name: String) -> float:
	return float(_data.get(name, 0.0))


func add_currency(name: String, amount: float) -> void:
	# 메모리 반영 + dirty. 영속화는 주기 autosave/즉시 flush가 담당.
	# 음수 인자는 무시(획득 함수로 차감하는 오용 방지 — 차감은 spend_currency 사용).
	if amount < 0.0:
		push_warning("[Backend] add_currency 음수 무시: %s %f" % [name, amount])
		return
	_data[name] = get_currency(name) + amount
	_mark_dirty()


func grant_currencies(valid: Array, acc: Dictionary) -> void:
	# 이미 valid_rewards로 필터된 보상(양수+허용 재화)만 받음 — 메모리 가산 + acc 합산.
	# mark_claimed/flush/Events emit 은 호출부 책임(우편함/퀘스트 §6-0 수령 시퀀스).
	for r in valid:
		var rd := r as Dictionary
		var cur: String = str(rd.get("currency", ""))
		var amt: float = float(rd.get("amount", 0))
		add_currency(cur, amt)
		acc[cur] = float(acc.get(cur, 0.0)) + amt


func spend_currency(name: String, amount: float) -> bool:
	# 부족하면 false(미차감). 음수 인자는 거부(차감 함수로 가산하는 오용/익스플로잇 방지).
	if amount < 0.0:
		push_warning("[Backend] spend_currency 음수 거부: %s %f" % [name, amount])
		return false
	var c := get_currency(name)
	if c < amount:
		return false
	_data[name] = c - amount
	_mark_dirty()
	return true


# 골드 별칭 (기존 호출부 호환)
func get_gold() -> float:
	return get_currency(CUR_GOLD)
func add_gold(amount: float) -> void:
	add_currency(CUR_GOLD, amount)
func spend_gold(amount: float) -> bool:
	return spend_currency(CUR_GOLD, amount)

# 다이아 별칭
func get_dia() -> float:
	return get_currency(CUR_DIA)
func add_dia(amount: float) -> void:
	add_currency(CUR_DIA, amount)
func spend_dia(amount: float) -> bool:
	return spend_currency(CUR_DIA, amount)

# 유물 가루 별칭
func get_dust() -> float:
	return get_currency(CUR_DUST)
func add_dust(amount: float) -> void:
	add_currency(CUR_DUST, amount)
func spend_dust(amount: float) -> bool:
	return spend_currency(CUR_DUST, amount)


func buy_dust_with_dia(dust_amount: float, dia_cost: float) -> bool:
	# 상점 > 재화: 다이아로 유물 가루 구매(일단 다이아 결제). 다이아 부족 시 false(가루 미지급).
	# 이산 이벤트 → flush. (지급량/비용은 호출부가 Relics.dust_shop_pack 에서 결정)
	if not spend_dia(dia_cost):
		return false
	add_dust(dust_amount)
	flush()
	return true


# ---------- 인스턴스 컬렉션 공용 헬퍼 (장비/유물) ----------

func _find_inst(arr: Array, field: String, value: String) -> Dictionary:
	# field 값이 일치하는 첫 인스턴스 반환(살아있는 Dictionary 참조 — 호출부 직접 변경이 세이브에 반영). 없으면 {}.
	for inst in arr:
		if str((inst as Dictionary).get(field, "")) == value:
			return inst
	return {}


func _alloc_uid(seq_key: String, prefix: String) -> String:
	# 시퀀스 증가 + 고유 uid 발급 (equip_seq→"eN" / relic_seq→"rN").
	var seq := int(_data.get(seq_key, 0)) + 1
	_data[seq_key] = seq
	return prefix + str(seq)


# ---------- 보유 장비 ({id: 개수}) ----------

func get_equips(pool: String) -> Array:
	# 종류별 보유 인스턴스 배열 [{uid,item,level}] (실배열 참조 — 변경 시 _mark_dirty 필요).
	return ((_data.get("equips", {}) as Dictionary).get(pool, []) as Array)


func get_equipped(pool: String) -> String:
	return str((_data.get("equipped", {}) as Dictionary).get(pool, ""))


func set_equipped(pool: String, uid: String) -> void:
	# 장착(빈 문자열이면 해제). 이산 이벤트 → 즉시 flush.
	(_data["equipped"] as Dictionary)[pool] = uid
	_commit()


func get_equip_by_uid(pool: String, uid: String) -> Dictionary:
	return _find_inst(get_equips(pool), "uid", uid)


func add_equip(pool: String, item_id: String, level: int = 0) -> String:
	# 인스턴스 생성 → equips[pool]에 추가. uid 반환. (영속화는 호출부 flush — 소환 묶음 1회 flush)
	# ⚠️ 신화(최상위) 돌파: 같은 종류 신화를 이미 보유하면 새 인스턴스 대신 그 신화의 별(stars) +1
	#    (중복 흡수 = 클러터 0). 별 상한(star_cap>0) 도달 시엔 흡수 안 하고 별도 인스턴스로 둠.
	var equips: Dictionary = _data.get("equips", {})
	if not equips.has(pool):
		equips[pool] = []
	var arr: Array = equips[pool]
	var grade: String = str(GachaScript.item_info(item_id).get("grade", ""))
	var is_top: bool = grade != "" and GachaScript.is_top_grade(grade)
	if is_top:
		var existing := _find_top_grade_inst(arr)
		if not existing.is_empty():
			var cap := GachaScript.star_cap()
			var cur := int(existing.get("stars", 0))
			if cap <= 0 or cur < cap:
				existing["stars"] = cur + 1   # 중복 신화 흡수 → 별 +1
				_mark_dirty()
				return str(existing.get("uid", ""))
	var uid := _alloc_uid("equip_seq", "e")
	var inst := {"uid": uid, "item": item_id, "level": level}
	if is_top:
		inst["stars"] = 0   # 신화 인스턴스는 별 추적
	arr.append(inst)
	_mark_dirty()
	return uid


func _find_top_grade_inst(arr: Array) -> Dictionary:
	# 배열에서 최상위(신화) 등급 인스턴스 첫 개 — 돌파 흡수 대상. 없으면 {}.
	for inst in arr:
		var d := inst as Dictionary
		if GachaScript.is_top_grade(_equip_grade(d)):
			return d
	return {}


func get_equip_stars(pool: String, uid: String) -> int:
	return int(get_equip_by_uid(pool, uid).get("stars", 0))


func _equip_grade(inst: Dictionary) -> String:
	# 장비 인스턴스 → 등급 문자열 (카탈로그 조회 단일 지점. 미존재 아이템은 "").
	return str(GachaScript.item_info(str(inst.get("item", ""))).get("grade", ""))


func equip_bonus(pool: String, uid: String) -> float:
	# 특정 인스턴스의 장착 보너스(없으면 0).
	var inst := get_equip_by_uid(pool, uid)
	if inst.is_empty():
		return 0.0
	var grade := _equip_grade(inst)
	return GachaScript.equip_bonus(grade, int(inst.get("level", 0)), int(inst.get("stars", 0)))


func equipped_bonus(pool: String) -> float:
	# 현재 장착 중인 장비의 보너스(미장착 0). 전투 계산(공격력/체력 곱)에서 사용.
	return equip_bonus(pool, get_equipped(pool))


func enhance_equip(pool: String, uid: String) -> bool:
	# 강화 1레벨(골드 소모). 성공 시 true. 이산 이벤트 → flush.
	var inst := get_equip_by_uid(pool, uid)
	if inst.is_empty():
		return false
	var lv := int(inst.get("level", 0))
	if lv >= GachaScript.enhance_max():
		return false
	var grade := _equip_grade(inst)
	var c := GachaScript.enhance_cost(grade, lv)
	if not spend_gold(float(c)):
		return false
	inst["level"] = lv + 1   # 인스턴스는 배열 내 Dictionary 참조 → 직접 변경 반영
	_commit()
	return true


func combine_equips(pool: String, grade: String) -> Dictionary:
	# 단일 합성(공개 API) — 코어 1회 + 즉시 flush. 결과 inst({} 실패).
	var res := _combine_one(pool, grade)
	if not res.is_empty():
		flush()
	return res


func _combine_one(pool: String, grade: String) -> Dictionary:
	# 합성 코어(영속화 없음 — 전체 합성이 반복 호출 후 1회 flush). 같은 종류·등급 비장착 N개 → 상위 무작위 1개.
	var next_g := GachaScript.next_grade(grade)
	if next_g == "":
		return {}   # 최상위(신화) — 합성 불가
	var n := GachaScript.combine_n()
	var equipped_uid := get_equipped(pool)
	var arr: Array = get_equips(pool)
	var mats: Array = []
	for inst in arr:
		var d := inst as Dictionary
		if str(d.get("uid", "")) == equipped_uid:
			continue  # 장착 중은 재료에서 제외(보호)
		if _equip_grade(d) == grade:
			mats.append(d)
			if mats.size() >= n:
				break
	if mats.size() < n:
		return {}
	# 결과 아이템을 재료 소모 "전에" 확정 — 상위 풀이 비면 재료 보존하고 조기 반환(데이터 손실 방지).
	var new_item := GachaScript.random_item_of_grade(pool, next_g)
	if new_item == "":
		return {}
	for m in mats:
		arr.erase(m)
	var uid := add_equip(pool, new_item, 0)  # 결과가 신화면 기존 신화에 별 흡수될 수 있음(uid=기존)
	return get_equip_by_uid(pool, uid)


func combine_all_equips(pool: String) -> Dictionary:
	# 합성 가능한 모든 장비를 한 번에 — 저등급→고등급 cascade(common 합성으로 생긴 rare도 이어서 합성).
	# 반복 합성 후 1회만 flush(kplay 과호출 방지). 반환 {combines, produced{등급:개수}}.
	var summary := {"combines": 0, "produced": {}}
	for g in GachaScript.grade_ids():
		if GachaScript.next_grade(g) == "":
			continue  # 최상위는 합성 대상 아님
		while count_grade(pool, g) >= GachaScript.combine_n():
			var res := _combine_one(pool, g)
			if res.is_empty():
				break  # 실패/상위 풀 빔 — 무한루프 방지
			summary["combines"] = int(summary["combines"]) + 1
			var ng := GachaScript.next_grade(g)
			var prod: Dictionary = summary["produced"]
			prod[ng] = int(prod.get(ng, 0)) + 1
	if int(summary["combines"]) > 0:
		flush()
	return summary


func count_grade(pool: String, grade: String, exclude_equipped: bool = true) -> int:
	# 해당 종류·등급 보유 수(합성 가능 판정용). exclude_equipped면 장착 중 제외.
	var equipped_uid := get_equipped(pool)
	var cnt := 0
	for inst in get_equips(pool):
		var d := inst as Dictionary
		if exclude_equipped and str(d.get("uid", "")) == equipped_uid:
			continue
		if _equip_grade(d) == grade:
			cnt += 1
	return cnt


# ---------- 보유 유물 (족보 커스텀) ----------
# 인스턴스 [{uid, effect, grade}]. 파워=등급으로만(레벨 없음). 장착=relic_slots(uid 배열, 최대 slot_count).

func get_relics() -> Array:
	return (_data.get("relics", []) as Array)


func _get_relic_by_uid(uid: String) -> Dictionary:
	return _find_inst(get_relics(), "uid", uid)


func add_relic(effect: String, grade: String) -> String:
	# 보유 목록에 인스턴스 추가. uid 반환. (영속화는 호출부 flush — 획득 묶음 1회)
	var uid := _alloc_uid("relic_seq", "r")
	(_data["relics"] as Array).append({"uid": uid, "effect": effect, "grade": grade})
	_mark_dirty()
	return uid


func get_relic_slots() -> Array:
	return (_data.get("relic_slots", []) as Array)


func relic_slot_count() -> int:
	return RelicsScript.slot_count()


func is_relic_equipped(uid: String) -> bool:
	return get_relic_slots().has(uid)


func get_equipped_relics() -> Array:
	# 장착 슬롯 uid → 인스턴스 {uid,effect,grade}. 효과 계산(분포·보정 등)용.
	var out: Array = []
	for uid in get_relic_slots():
		var inst := _get_relic_by_uid(str(uid))
		if not inst.is_empty():
			out.append(inst)
	return out


func equip_relic(uid: String) -> bool:
	# 빈 슬롯에 장착(상한=relic_slot_count). 없는/이미 장착 유물이면 false. 즉시 flush.
	if _get_relic_by_uid(uid).is_empty() or is_relic_equipped(uid):
		return false
	var slots: Array = _data["relic_slots"]
	if slots.size() >= relic_slot_count():
		return false
	slots.append(uid)
	_commit()
	return true


func unequip_relic(uid: String) -> void:
	(_data["relic_slots"] as Array).erase(uid)
	_commit()


func _relic_grade_index(grade: String) -> int:
	# 등급 인덱스 단일 출처 = Relics.grade_index (grade_order↔grades 정합은 build_data 검증 게이트가 보장).
	return RelicsScript.grade_index(grade)


func _relic_dust_value(grade: String) -> float:
	# 가루 환산(잠정): common=10, 등급마다 ×3 (10/30/90/270/810). ⏸ 추후 데이터화.
	return 10.0 * pow(3.0, _relic_grade_index(grade))


func acquire_relic(effect: String, grade: String) -> Dictionary:
	# 유물 획득(가챠/지급). **같은 효과는 가장 높은 등급 1개만 유지** — 중복/하위는 자동 가루 환급.
	# 반환 {outcome:new|upgrade|dust, uid, effect, grade, dust}. (영속화는 호출부 flush)
	var existing: Dictionary = _find_inst(get_relics(), "effect", effect)
	if existing.is_empty():
		var uid: String = add_relic(effect, grade)
		return {"outcome": "new", "uid": uid, "effect": effect, "grade": grade, "dust": 0.0}
	var cur_grade: String = str(existing.get("grade", ""))
	if _relic_grade_index(grade) > _relic_grade_index(cur_grade):
		# 업그레이드: 보유 유물 등급 상승(장착 중이면 슬롯에서 자동 반영), 밀려난 낮은 등급 → 가루
		existing["grade"] = grade
		var refund: float = _relic_dust_value(cur_grade)
		add_dust(refund)
		_mark_dirty()
		return {"outcome": "upgrade", "uid": str(existing.get("uid", "")), "effect": effect, "grade": grade, "dust": refund}
	# 동급/하위 = 중복 → 자동 가루(보유 변화 없음)
	var refund2: float = _relic_dust_value(grade)
	add_dust(refund2)
	return {"outcome": "dust", "uid": "", "effect": effect, "grade": grade, "dust": refund2}


func relic_unlocked() -> bool:
	# 유물 시스템 전체 해금 = **첫 보스(10스테이지) 처치 후**. 그 전엔 유물 탭·유물 소환 모두 잠금.
	# (기본 전투를 먼저 익히고 첫 보스에서 유물 소개 — 무료 확정 소환 해금과 동일 기준.)
	return get_stat("boss_kills") >= 1


func _relic_free_unlocked() -> bool:
	# 무료 확정 소환 해금 — 유물 시스템 전체 해금과 동일(첫 보스 처치 후).
	return relic_unlocked()


func dungeon_unlocked() -> bool:
	# 던전("시련의 탑") 해금 = **첫 보스(10스테이지) 처치 후** — 유물과 동일 기준(2026-06-18).
	# (별도 메서드로 둠 — 추후 던전 해금 시점을 유물과 다르게 바꾸려면 여기만 수정.)
	return get_stat("boss_kills") >= 1


func relic_free_pulls_left() -> int:
	# 남은 무료 확정 소환 횟수. 첫 보스 처치 전엔 0(잠금). 0이면 무료 소환 불가(이후 가루 가챠만).
	if not _relic_free_unlocked():
		return 0
	return max(0, RelicsScript.free_pull_count() - int(_data.get("relic_free_used", 0)))


func next_free_relic_grant() -> Dictionary:
	# 다음 무료 확정 소환이 줄 **사전 설정** 유물(UI 안내용). 잠금/소진이면 {}.
	if relic_free_pulls_left() <= 0:
		return {}
	return RelicsScript.free_pull_grant(int(_data.get("relic_free_used", 0)))


func do_free_relic_pull() -> Dictionary:
	# 무료 확정 소환: 첫 보스 처치 후 + 남은 횟수 있으면 **사전 설정 유물**(relics.yaml free_pull 순서대로) 1개 지급.
	# 반환 = acquire_relic 결과(+name) / 불가 시 {}. 이산 이벤트 → flush.
	if relic_free_pulls_left() <= 0:
		return {}
	var idx := int(_data.get("relic_free_used", 0))
	var g := RelicsScript.free_pull_grant(idx)
	if g.is_empty():
		return {}
	var res := acquire_relic(str(g.get("effect", "")), str(g.get("grade", "")))
	res["name"] = g.get("name", "?")
	_data["relic_free_used"] = idx + 1
	flush()
	return res


func grant_boss_dust(stage: int) -> float:
	# 보스 첫 클리어 유물 가루 지급(주 획득 리듬, 2026-06-17). 이미 지급한 보스면 0.
	# dust_boss_max(단일 int) 가드로 재파밍 차단 — 진행이 선형이라 "현재 보스 > 지급한 최고 보스"면 첫 클리어.
	# DEATH_SETBACK 후퇴와 무관(보스20 사망→17 밀려 재클리어해도 dust_boss_max≥20이라 안 줌).
	# 가루 지급 = 이산 이벤트 → 즉시 flush(현행 저장 정책). 지급액 반환(없으면 0).
	if not Balance.is_boss_stage(stage):
		return 0.0
	var prev: int = int(get_value("dust_boss_max", 0))
	if stage <= prev:
		return 0.0
	var amount: float = Balance.boss_dust(stage)
	set_value("dust_boss_max", stage)
	if amount > 0.0:
		add_dust(amount)
	flush()
	return amount


# ---------- 던전 "시련의 탑" (별개 진행 — 메인 stage 와 독립) ----------

func get_dungeon_max_cleared() -> int:
	# 첫 돌파한 최고 층(1-based). 0 = 아직 1층도 못 깸. 다음 도전 가능 층 = 이 값 + 1.
	return int(get_value("dungeon_max_cleared", 0))


func _default_dungeon() -> Dictionary:
	# 던전 데일리 기본 상태. 매번 새 mutable 리터럴 반환 — const 금지(Godot4 const 컨테이너의
	# 재귀 read-only 가 세이브 데이터에 전파돼 이후 수정이 깨짐, _ensure_container 주석과 동일).
	return {"tickets": 0, "date": "", "auto": true, "auto_init": true}


func get_dungeon_state() -> Dictionary:
	# 던전 데일리 상태 {tickets:int, date:str, auto:bool} 라이브 참조(손상 복구).
	var dg: Variant = _data.get("dungeon")
	if not (dg is Dictionary):
		dg = _default_dungeon()
		_data["dungeon"] = dg
	return dg


func get_dungeon_tickets() -> int:
	return int(get_dungeon_state().get("tickets", 0))


func consume_dungeon_ticket() -> bool:
	# 입장권 1 소모(>0 일 때만). 부족하면 false(미소모). 입장(도전/재도전) 시 호출.
	var dg := get_dungeon_state()
	var t := int(dg.get("tickets", 0))
	if t <= 0:
		return false
	dg["tickets"] = t - 1
	_mark_dirty()
	return true


func add_dungeon_tickets(n: int) -> void:
	# 입장권 추가(추후 광고/IAP 충전용). 음수 무시.
	if n <= 0:
		return
	var dg := get_dungeon_state()
	dg["tickets"] = int(dg.get("tickets", 0)) + n
	_mark_dirty()


func roll_dungeon_tickets_if_needed(today: String, daily_grant: int) -> bool:
	# 날짜 바뀌면 입장권을 일일 무료 수량으로 리셋(use-it-or-lose-it). 변경 시 true(호출부가 그때만 flush).
	var dg := get_dungeon_state()
	if str(dg.get("date", "")) == today:
		return false
	dg["date"] = today
	dg["tickets"] = daily_grant
	_mark_dirty()
	return true


func get_dungeon_auto() -> bool:
	# 기본 켜짐(자동 등반) — 끄기는 설정에만. 구버전 세이브(키 없음)도 켜짐으로 본다.
	return bool(get_dungeon_state().get("auto", true))


func set_dungeon_auto(on: bool) -> void:
	get_dungeon_state()["auto"] = on
	_mark_dirty()


func grant_dungeon_repeat(floor_n: int) -> Dictionary:
	# 이미 깬 층 재도전 보상 = 골드(stage_equiv 스케일) + 소량 가루. 입장권으로 게이트되므로 무한 파밍 아님.
	# (첫 돌파 마일스톤[다이아·가루]과 별개 — grant_dungeon_clear 가 {} 반환할 때만 이걸 호출.)
	var se: int = DungeonDataScript.stage_equiv(floor_n)
	var gold_amt: float = Balance.gold_reward(se) * Balance.DUNGEON_REPEAT_GOLD_MULT
	var dust_amt: float = float(int(DungeonDataScript.dust(floor_n) * Balance.DUNGEON_REPEAT_DUST_RATIO))
	if gold_amt > 0.0:
		add_gold(gold_amt)
	if dust_amt > 0.0:
		add_dust(dust_amt)
	flush()
	return {"gold": gold_amt, "dust": dust_amt, "floor": floor_n}


func grant_dungeon_clear(floor: int) -> Dictionary:
	# 던전 층 클리어 보상 — **첫 돌파만**(이미 깬 층 = {} 반환, 재파밍 차단).
	# grant_boss_dust 와 동일 패턴: 단일 int dungeon_max_cleared 가드(선형 진행). 보상=첫 돌파 1회성 dia·dust.
	# 재도전 보상 없음(클리어=완료, 재입장 불가 설계). 이산 이벤트 → 즉시 flush. 지급액 {dia,dust,floor} / 미지급 {}.
	var prev: int = int(get_value("dungeon_max_cleared", 0))
	if floor <= prev:
		return {}
	var dia_amt: float = DungeonDataScript.dia(floor)
	var dust_amt: float = DungeonDataScript.dust(floor)
	set_value("dungeon_max_cleared", floor)
	if dia_amt > 0.0:
		add_dia(dia_amt)
	if dust_amt > 0.0:
		add_dust(dust_amt)
	flush()
	return {"dia": dia_amt, "dust": dust_amt, "floor": floor}


# ---------- 우편함 (수령 도장만 저장 — 카탈로그는 Mailbox 코드 상수) ----------
# 우편함은 보상 전달 통로. 재화 지급은 add_currency, 수령 여부만 여기 mail_claimed 에 저장한다.
# ⚠️ 수령 시퀀스(재화+claimed 메모리 일괄 반영 → flush 1회)는 호출부(mailbox_panel)가 소유 — 여기는 저장소만.

func get_mail_claimed() -> Dictionary:
	return _data.get("mail_claimed", {})


func is_mail_claimed(id: String) -> bool:
	return bool((_data["mail_claimed"] as Dictionary).get(id, false))


func mark_mail_claimed(id: String) -> void:
	# 메모리에만 도장 + dirty. 영속화는 호출부 flush()(수령 시퀀스 마지막 1회).
	(_data["mail_claimed"] as Dictionary)[id] = true
	_mark_dirty()


func gc_mail_claimed(valid_ids: Array) -> bool:
	# 카탈로그에 더 이상 없는 id의 도장 제거(누적 완화). 변경 있으면 true 반환(호출부가 변경 시에만 flush).
	# ⚠️ 안전 전제 = mail id 재사용 금지(Mailbox).
	var m: Dictionary = _data["mail_claimed"]
	var valid: Dictionary = {}
	for v in valid_ids:
		valid[v] = true
	var changed: bool = false
	for id in m.keys():
		if not valid.has(id):
			m.erase(id)
			changed = true
	if changed:
		_mark_dirty()
	return changed


# ---------- 퀘스트 (수령 도장 + 일일 base/날짜 저장 — 카탈로그는 Quests 코드 상수) ----------
# 우편함과 동일 패턴: 진행도 stat 은 stats 컨테이너에서 읽고, 수령 여부만 여기 저장한다.
# 수령 시퀀스(재화+claimed 메모리 일괄 반영 → flush 1회)는 호출부(quest_panel)가 소유 — 여기는 저장소만.

func get_quests_main_claimed() -> Dictionary:
	return _data.get("quests_main_claimed", {})


func is_quest_main_claimed(id: String) -> bool:
	return bool((_data["quests_main_claimed"] as Dictionary).get(id, false))


func mark_quest_main_claimed(id: String) -> void:
	(_data["quests_main_claimed"] as Dictionary)[id] = true
	_mark_dirty()


func get_quests_daily() -> Dictionary:
	# {date, base, claimed} 라이브 참조. 하위 키 손상 방어(컨테이너 누락 시 복구).
	var dq: Dictionary = _data["quests_daily"]
	if not (dq.get("base") is Dictionary):
		dq["base"] = {}
	if not (dq.get("claimed") is Dictionary):
		dq["claimed"] = {}
	return dq


func get_quests_daily_base() -> Dictionary:
	return (get_quests_daily()["base"] as Dictionary)


func get_quests_daily_claimed() -> Dictionary:
	return (get_quests_daily()["claimed"] as Dictionary)


func is_quest_daily_claimed(id: String) -> bool:
	return bool(get_quests_daily_claimed().get(id, false))


func mark_quest_daily_claimed(id: String) -> void:
	get_quests_daily_claimed()[id] = true
	_mark_dirty()


func roll_daily_quests_if_needed(today: String, stat_keys: Array) -> bool:
	# 날짜가 바뀌었으면 일일 퀘스트 리셋: base = 현재 stat 스냅샷, claimed 비움, date 갱신.
	# 변경 시 true 반환(호출부가 변경 시에만 flush). 기획 §5(앱 실행 중 날짜 변경 시 갱신).
	var dq: Dictionary = get_quests_daily()
	if str(dq.get("date", "")) == today:
		return false
	var base: Dictionary = {}
	for k in stat_keys:
		base[str(k)] = get_stat(str(k))
	dq["date"] = today
	dq["base"] = base
	dq["claimed"] = {}
	_mark_dirty()
	return true


# ---------- 진행 스테이지 ----------

func get_stage() -> int:
	return int(_data.get("stage", 1))


func set_stage(stage: int) -> void:
	var s: int = max(1, stage)
	_data["stage"] = s
	# 최고 도달 스테이지(monotonic max) stat — 퀘스트 "스테이지 N 도달"용.
	# 사망·블록 복귀로 현재 stage 가 내려가도 줄지 않는다(도달 기록 보존).
	var stats: Dictionary = _data["stats"]
	if s > int(stats.get("stage_reached", 0)):
		stats["stage_reached"] = s
	_mark_dirty()


# ---------- 오프라인 정산 ----------

func consume_offline_seconds() -> float:
	# 마지막 저장(last_seen) 이후 경과 시간(초)을 반환. 0 이하면 0.
	var last: int = int(_data.get("last_seen", 0))
	if last <= 0:
		return 0.0
	var now: int = int(Time.get_unix_time_from_system())
	return max(0.0, float(now - last))


# ---------- 범용 저장소 (프론트엔드 시스템이 자유롭게 키-값 저장) ----------
# 업적 등 게임 규칙은 프론트엔드가 처리하고, 그 결과만 여기에 저장/불러온다.

func get_value(key: String, default_value: Variant = null) -> Variant:
	return _data.get(key, default_value)


func set_value(key: String, value: Variant) -> void:
	# 메모리에만 반영하고 dirty 표시. 영속화는 flush()(즉시/주기)가 담당.
	_data[key] = value
	_mark_dirty()


# ---------- 계정 / 랭킹 ----------

func is_guest() -> bool:
	return account_type == ACCOUNT_GUEST


func _is_auth_provider(p: String) -> bool:
	return p == ACCOUNT_GOOGLE or p == ACCOUNT_KPLAY


func begin_login(provider: String) -> void:
	# 인증 계정 로그인 시작 (google/kplay). 완료는 login_changed(true) 시그널로 통지.
	# google/kplay는 방식만 다르고 동작 동일 — account_type만 다르게 보관.
	if not _is_auth_provider(provider):
		push_warning("[Backend] 알 수 없는 로그인 provider: %s" % provider)
		return
	account_type = provider
	_provider.login(provider)


func commit_auth_session(provider: String) -> void:
	# 이미 플랫폼 인증된 상태(is_logged_in)에서 인증 계정으로 진입/변경할 때.
	# 재인증 없이 ①계정 표기 갱신 + ②인증 슬롯(클라우드)으로 전환 + ③그 데이터 로드.
	# (게스트 슬롯에서 넘어올 때 데이터가 섞이지 않게 인증 슬롯을 다시 읽는다.)
	# kplay는 게임 로드 시 user-info를 자동 전송해 is_logged_in이 먼저 true가 될 수 있어,
	# login의 begin_login 단축 경로에서 account_type/슬롯이 안 바뀌던 문제도 함께 보정.
	if not _is_auth_provider(provider):
		return
	account_type = provider
	await _switch_to_auth_slot()


func _switch_to_auth_slot() -> void:
	# 인증 슬롯(클라우드 동기)으로 전환 후 그 데이터를 로드한다.
	_provider.set_slot(BackendProvider.SLOT_AUTH, true)
	await _load()


func continue_as_guest() -> void:
	# 게스트 진입 — 게스트 슬롯(로컬 전용)으로 전환 후 그 데이터를 로드(인증 데이터와 분리).
	account_type = ACCOUNT_GUEST
	is_logged_in = false
	_provider.set_slot(BackendProvider.SLOT_GUEST, false)
	await _load()


func logout() -> void:
	# 로그아웃 = 로컬(이 기기) 세션/캐시만 정리 후 로그인 화면 복귀.
	# 인증 계정의 클라우드 사본은 유지되어 재로그인 시 복원된다.
	_provider.clear_local()
	_reset_session()
	logged_out.emit()


func delete_account() -> void:
	# 계정 탈퇴 = 로컬 + 서버 데이터 모두 삭제. 구글/kplay/게스트 공통.
	# 재로그인하면 저장된 데이터가 없어 신규 계정처럼 시작된다.
	_provider.clear_account()
	_reset_session()
	account_deleted.emit()


func _reset_session() -> void:
	_data = _migrate({})
	_dirty = false
	is_logged_in = false
	user_name = ""
	account_type = ACCOUNT_NONE


func submit_score(score: int) -> void:
	# 랭킹 현재 비활성(게임 컨셉 정리본 §11). 게스트도 no-op.
	if is_guest():
		return
	_provider.submit_score(score)


func show_ranking() -> void:
	# 랭킹 표시 (구 show_leaderboard). 보기는 게스트도 허용.
	_provider.show_leaderboard()


# ---------- 영속화 ----------

func _mark_dirty() -> void:
	_dirty = true


func _commit() -> void:
	# 이산 이벤트(장착/강화/유물 슬롯 등) 저장 관용구 — dirty 마킹 + 즉시 flush (저장 트리거 정책 참조).
	_mark_dirty()
	flush()


func flush() -> void:
	# 변경분을 영속화. 변경 없으면 skip. (save_all은 await 불필요)
	if not _dirty:
		return
	_persist_now()


func _persist_now() -> void:
	# 저장 단일 출처: last_seen(오프라인 정산 기준) 갱신 + provider 저장.
	# ⚠️ dirty 해제는 **저장 성공 시에만**. 실패 시 dirty 유지 → 다음 autosave(주기)/flush가 재시도
	#    (먼저 _dirty=false 하면 실패해도 flush의 `if not _dirty: return` 때문에 영영 재시도 안 됨).
	_data["last_seen"] = int(Time.get_unix_time_from_system())
	var ok: bool = _provider.save_all(_data)
	_dirty = not ok


func _on_provider_login_changed(logged_in: bool, provider_user_name: String) -> void:
	is_logged_in = logged_in
	user_name = provider_user_name
	# 인증 의도일 때만(begin_login으로 account_type이 이미 auth) 인증 슬롯으로 전환·로드한다.
	# ⚠️ kplay는 게스트로 시작해도 user-info를 자동 전송하므로, 게스트/미선택 상태의 자동 로그인은
	#    슬롯을 바꾸지 않는다(게스트 데이터 보호). 데이터 준비 후 통지(씬 전환 전 보장).
	if logged_in and _is_auth_provider(account_type):
		await _switch_to_auth_slot()
	login_changed.emit(logged_in)


func _on_provider_score_submitted(success: bool, rank: int) -> void:
	score_submitted.emit(success, rank)


func _notification(what: int) -> void:
	# 종료 직전 best-effort 저장 (await 불가 상황)
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_APPLICATION_PAUSED:
		# 앱 종료/백그라운드 전환 시 best-effort 저장 (생애주기 트리거)
		if _dirty and _provider != null:
			_persist_now()
