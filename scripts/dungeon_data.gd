class_name DungeonData
extends RefCounted

# 던전 "시련의 탑" 층 데이터 (data/dungeon.json ← data/src/dungeon.yaml, 변환 tools/build_data.gd).
# 메인 스테이지 환산(stage_equiv)으로 Balance 곡선을 재사용한다 — 던전 전용 밸런스 곡선 신설 안 함.
# 층 번호는 1-based(1층 = 파일의 첫 floor). 정렬 = yaml 작성 순서(JSON 키 순서 보존).
# autoload 무참조 → 헤드리스 --script 테스트 가능. 수치 잠정(밸런스 보류).
# 기획서: docs/design/던전 시스템 정리본.md
#
# ⚠️ class_name 은 등록용 — 소비처(game/backend/패널)는 stale 캐시 회피 위해 preload 로 참조한다.

const BalanceMod := preload("res://scripts/balance.gd")

static var _floors: Array = []   # 순서대로 [{floor data}…] (index 0 = 1층)
static var _loaded: bool = false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_floors = []
	var t: Variant = GameData.table("dungeon")
	var fmap: Variant = (t as Dictionary).get("floors", {}) if t is Dictionary else {}
	if fmap is Dictionary:
		for fid in fmap:
			if fmap[fid] is Dictionary:
				_floors.append(fmap[fid])


static func floor_count() -> int:
	_ensure()
	return _floors.size()


static func _floor(n: int) -> Dictionary:
	# 1-based 층 → 데이터. 범위 밖이면 {}.
	_ensure()
	if n < 1 or n > _floors.size():
		return {}
	return _floors[n - 1]


static func stage_equiv(n: int) -> int:
	return int(_floor(n).get("stage_equiv", 1))


static func hp_mult(n: int) -> float:
	return float(_floor(n).get("hp_mult", 1.0))


static func hand_gate(n: int) -> int:
	return int(_floor(n).get("hand_gate", 0))   # 0 = 없음(족보 제한 없음)


static func time_limit(n: int) -> float:
	return float(_floor(n).get("time_limit", 0.0))  # 0 = 없음(시간 제한 없음)


static func pc_atk_down(n: int) -> float:
	return float(_floor(n).get("pc_atk_down", 0.0))  # 0 = 없음(자동공격 감쇠 비율)


static func dia(n: int) -> float:
	return float(_floor(n).get("dia", 0.0))


static func dust(n: int) -> float:
	return float(_floor(n).get("dust", 0.0))


static func boss_hp(n: int) -> int:
	# 던전 보스 HP = 메인 비보스 base(stage_equiv) × BOSS_HP_MULT × hp_mult.
	# (enemy_hp 는 stage_equiv 가 보스배수면 BOSS_HP_MULT 이중계상 → base_enemy_hp 사용.)
	var base: float = BalanceMod.base_enemy_hp(stage_equiv(n))
	return int(ceil(base * BalanceMod.BOSS_HP_MULT * hp_mult(n)))


static func boss_attack(n: int) -> int:
	# 던전 보스 PC 공격 데미지 = 보스 공격 곡선(stage_equiv). boss_attack_damage 는 보스배수 게이트 없음.
	return int(ceil(BalanceMod.boss_attack_damage(stage_equiv(n))))


static func rule_text(n: int) -> String:
	# HUD/패널 표기용 룰 요약(짧게). ⚠️ 번들폰트에 없는 가운데점(·) 금지 → " / " 구분.
	var parts: Array = []
	var hg: int = hand_gate(n)
	if hg > 0:
		parts.append("스킬은 족보 %d+ 만" % hg)
	var tl: float = time_limit(n)
	if tl > 0.0:
		parts.append("제한 %d초" % int(tl))
	var pd: float = pc_atk_down(n)
	if pd > 0.0:
		parts.append("자동공격 -%d%%" % int(round(pd * 100.0)))
	if parts.is_empty():
		return "제한 없음"
	return " / ".join(parts)
