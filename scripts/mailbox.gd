class_name Mailbox
extends RefCounted

# 우편함 — 보상·보정·이벤트 재화를 수령식으로 전달하는 공용 통로. (기획: docs/design/우편함 시스템 정리본.md)
# 이 파일은 **우편 카탈로그(코드 상수) + 순수 판정 로직**만 소유한다(autoload 무참조 → 헤드리스 테스트 가능).
# 실제 수령(재화 지급·claimed 저장·flush)은 mailbox_panel.gd 가 BackendService API로 수행한다.
#
# 책임 경계: 우편함은 "어떤 재화 키(gold/dia/dust)를 전달할 수 있는가"(화이트리스트)만 소유.
#   지급량/대상/상한은 우편을 발행하는 주체가 정한다(재화 역할 기준은 docs/design/재화 정책 초안.md).
#
# ⚠️ mail id는 영구 유일 — 한 번 발행한 id는 재사용 금지(claimed GC의 안전 전제, 기획 §2-6·§7-1).
# ⚠️ 1차 카탈로그는 코드 상수. 데이터화 필요 시 data/src/mail.yaml 경로(기획 §7).

# 1차 허용 재화 키(화이트리스트). BackendService.add_currency 는 임의 키를 검증 없이 저장하므로,
# 우편함이 지급 직전 이 집합으로 직접 거른다(오타 'diia' 등 차단).
const ALLOWED_CURRENCIES: Array = ["gold", "dia", "dust"]

# 우편 카탈로그(1차 = 코드 상수 더미). id → 우편 정의.
#   rewards: [{currency, amount}] (currency ∈ ALLOWED_CURRENCIES, amount 양수)
#   expires_at: Unix초. 0 = 만료 없음.  source: test/event/compensation/system
# ⚠️ 더미 — 실제 운영 우편은 발행 시 [[재화 정책 초안]] 참고해 지급량 결정.
const CATALOG: Dictionary = {
	"mail_20260611_welcome": {
		"title": "환영합니다!",
		"body": "복권 키우기에 오신 것을 환영합니다.\n시작 보상을 받아 강화에 사용하세요.",
		"rewards": [{"currency": "gold", "amount": 5000.0}],
		"expires_at": 0,
		"source": "system",
	},
	"mail_20260611_test_reward": {
		"title": "테스트 보상",
		"body": "플레이 테스트 진행을 위해 보상을 지급합니다.",
		"rewards": [
			{"currency": "gold", "amount": 100000.0},
			{"currency": "dia", "amount": 5000.0},
		],
		"expires_at": 0,
		"source": "test",
	},
	"mail_20260611_firstpack": {
		"title": "첫 소환 지원",
		"body": "장비 소환을 한 번 경험해보세요.\n다이아를 드립니다.",
		"rewards": [{"currency": "dia", "amount": 100.0}],
		"expires_at": 0,
		"source": "event",
	},
}


# ---------- 시간 추상화 ----------
# ⚠️ 우편함은 시간을 이 한 지점만 거친다. 추후 리텐션 DayUtil/서버 시간이 준비되면 여기만 교체/통합(기획 §6-3).
static func now() -> int:
	return int(Time.get_unix_time_from_system())  # 1차 로컬 폴백


# ---------- 카탈로그 조회 ----------
static func all_ids() -> Array:
	return CATALOG.keys()


static func get_mail(id: String) -> Dictionary:
	# id 우편 정의(+ id 필드 포함). 없으면 {}.
	if not CATALOG.has(id):
		return {}
	var d: Dictionary = (CATALOG[id] as Dictionary).duplicate(true)
	d["id"] = id
	return d


static func has_mail(id: String) -> bool:
	return CATALOG.has(id)


# ---------- 판정 ----------
static func is_expired(def: Dictionary, at: int = -1) -> bool:
	# expires_at 이 있고(>0) 현재 시각이 지났으면 만료. at 미지정이면 now() 사용.
	var exp: int = int(def.get("expires_at", 0))
	if exp <= 0:
		return false
	var t: int = at if at >= 0 else now()
	return t >= exp


static func claimable_ids(claimed_map: Dictionary, at: int = -1) -> Array:
	# 받을 수 있는 우편 id 목록 = 카탈로그에 있고 + 아직 미수령 + 미만료.
	var t: int = at if at >= 0 else now()
	var out: Array = []
	for id in CATALOG:
		if bool(claimed_map.get(id, false)):
			continue
		if is_expired(CATALOG[id], t):
			continue
		out.append(id)
	return out


static func has_claimable(claimed_map: Dictionary, at: int = -1) -> bool:
	# 빨간 점(red dot) 판정용 — 받을 게 하나라도 있나.
	return not claimable_ids(claimed_map, at).is_empty()


# ---------- 재화 화이트리스트 ----------
static func is_currency_allowed(key: String) -> bool:
	return ALLOWED_CURRENCIES.has(key)


static func valid_rewards(rewards: Array) -> Array:
	# 실제 지급 가능한 보상만(양수 amount + 허용 재화). 오타/무보상 우편 판정·지급에 공용.
	# ⚠️ 수령 직전 이걸로 "지급 가능한 보상이 0개면 claimed를 찍지 않는다"(무보상 수령완료 방지, Codex 리뷰 #8).
	var out: Array = []
	for r in rewards:
		var rd := r as Dictionary
		if float(rd.get("amount", 0)) > 0.0 and is_currency_allowed(str(rd.get("currency", ""))):
			out.append(rd)
	return out


# ---------- claimed GC (카탈로그 제거 기준) ----------
# 카탈로그에 더 이상 없는 id의 claimed 도장을 제거한 새 맵을 반환한다(누적 완화, 기획 §7-1).
# ⚠️ 안전 전제 = mail id 재사용 금지 — 도장 지운 뒤 같은 id가 다시 카탈로그에 나타나면 재수령됨.
# 변경이 있으면 changed=true (호출부가 변경 시에만 저장하도록).
# ⚠️ 이 함수는 **순수 테스트용 미러**(autoload 무참조라 --script 헤드리스 테스트 가능, test_mailbox.gd 만 사용).
#    프로덕션 GC는 BackendService.gc_mail_claimed(in-place, game._ready 시작 시 1회) — 둘 다 "id ∈ CATALOG 이면 유지"로
#    판정 기준이 동일하다. **GC 기준을 바꾸면 두 곳을 함께 수정**할 것.
static func gc_claimed(claimed_map: Dictionary) -> Dictionary:
	var kept: Dictionary = {}
	var changed: bool = false
	for id in claimed_map:
		if CATALOG.has(id):
			kept[id] = claimed_map[id]
		else:
			changed = true  # 카탈로그에 없는 id → 정리(드롭)
	return {"map": kept, "changed": changed}
