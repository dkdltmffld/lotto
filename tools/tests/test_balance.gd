extends SceneTree

# ============================================================================
# 대상 모듈: res://scripts/balance.gd (스테이지/전투 밸런스 — static var + _static_init)
#   데이터 출처: res://data/balance.json (GameData.table("balance") 경유 1회 로드)
#   autoload 미사용 — headless --script 모드에서 단독 실행 가능.
# 단독 실행:
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_balance.gd
# 출력: 전부 통과 시 "[test_balance] PASS" + exit 0 / 실패 시 FAIL 목록 + exit 1
# ============================================================================

const BalanceMod := preload("res://scripts/balance.gd")
const GameDataMod := preload("res://scripts/game_data.gd")

const EPS := 0.000001  # 상대 오차 허용치 (기하 스케일 비율 비교용)


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func _approx(a: float, b: float) -> bool:
	# 상대 오차 비교 — 기하 성장 후반의 큰 수에서도 안전
	if a == b:
		return true
	var s: float = max(abs(a), abs(b), 1.0)
	return abs(a - b) <= s * EPS


static func run() -> Array:
	var fails: Array = []

	# ===== 1. JSON 테이블 로드 성공 =====
	# 비어 있으면 _static_init 이 폴백 기본값을 쓴 것 → 데이터 파이프라인 깨짐 신호
	var table: Dictionary = GameDataMod.table("balance")
	_check(not table.is_empty(), "GameData.table(\"balance\") 가 비어 있음 — data/balance.json 로드 실패", fails)

	# ===== 2. 상수가 전부 양수로 채워짐 =====
	var positives: Dictionary = {
		"BLOCK_SIZE": BalanceMod.BLOCK_SIZE,
		"MOBS_PER_STAGE": BalanceMod.MOBS_PER_STAGE,
		"ENEMY_BASE_HP": BalanceMod.ENEMY_BASE_HP,
		"BOSS_HP_MULT": BalanceMod.BOSS_HP_MULT,
		"GOLD_BASE": BalanceMod.GOLD_BASE,
		"BOSS_GOLD_MULT": BalanceMod.BOSS_GOLD_MULT,
		"JACKPOT_GOLD_MULT": BalanceMod.JACKPOT_GOLD_MULT,
		"BOSS_ATTACK_INTERVAL": BalanceMod.BOSS_ATTACK_INTERVAL,
		"BOSS_ATK_BASE": BalanceMod.BOSS_ATK_BASE,
		"BOSS_ATTACK_WINDUP": BalanceMod.BOSS_ATTACK_WINDUP,
		"MOB_ATTACK_INTERVAL": BalanceMod.MOB_ATTACK_INTERVAL,
		"MOB_ATK_BASE": BalanceMod.MOB_ATK_BASE,
		"MOB_ATTACK_WINDUP": BalanceMod.MOB_ATTACK_WINDUP,
		"AUTO_ATK_COEF": BalanceMod.AUTO_ATK_COEF,
		"EST_SECONDS_PER_MOB": BalanceMod.EST_SECONDS_PER_MOB,
		"RELIC_DUST_PER_BOSS_BASE": BalanceMod.RELIC_DUST_PER_BOSS_BASE,
	}
	for k in positives:
		_check(float(positives[k]) > 0.0, "%s 가 양수가 아님: %s" % [k, str(positives[k])], fails)

	# 성장률은 1 초과 (스테이지 단조 증가의 전제 — build_data 검증 게이트와 동일 기준)
	var growths: Dictionary = {
		"ENEMY_HP_GROWTH": BalanceMod.ENEMY_HP_GROWTH,
		"GOLD_GROWTH": BalanceMod.GOLD_GROWTH,
		"BOSS_ATK_GROWTH": BalanceMod.BOSS_ATK_GROWTH,
		"MOB_ATK_GROWTH": BalanceMod.MOB_ATK_GROWTH,
	}
	for k in growths:
		_check(float(growths[k]) > 1.0, "%s 가 1 초과가 아님: %s" % [k, str(growths[k])], fails)

	# ===== 3. 로드된 static var == JSON 파일 값 (핵심 키 매핑 대조) =====
	if not table.is_empty():
		var stage_d: Dictionary = table.get("stage", {})
		_check(BalanceMod.BLOCK_SIZE == int(stage_d.get("block_size", -1)), "BLOCK_SIZE != json stage.block_size", fails)
		_check(BalanceMod.MOBS_PER_STAGE == int(stage_d.get("mobs_per_stage", -1)), "MOBS_PER_STAGE != json stage.mobs_per_stage", fails)
		var eh: Dictionary = table.get("enemy_hp", {})
		_check(_approx(BalanceMod.ENEMY_BASE_HP, float(eh.get("base", -1.0))), "ENEMY_BASE_HP != json enemy_hp.base", fails)
		_check(_approx(BalanceMod.ENEMY_HP_GROWTH, float(eh.get("growth", -1.0))), "ENEMY_HP_GROWTH != json enemy_hp.growth", fails)
		_check(_approx(BalanceMod.BOSS_HP_MULT, float(eh.get("boss_mult", -1.0))), "BOSS_HP_MULT != json enemy_hp.boss_mult", fails)
		var g: Dictionary = table.get("gold", {})
		_check(_approx(BalanceMod.GOLD_BASE, float(g.get("base", -1.0))), "GOLD_BASE != json gold.base", fails)
		_check(_approx(BalanceMod.GOLD_GROWTH, float(g.get("growth", -1.0))), "GOLD_GROWTH != json gold.growth", fails)
		_check(_approx(BalanceMod.BOSS_GOLD_MULT, float(g.get("boss_mult", -1.0))), "BOSS_GOLD_MULT != json gold.boss_mult", fails)
		_check(_approx(BalanceMod.JACKPOT_GOLD_MULT, float(g.get("jackpot_mult", -1.0))), "JACKPOT_GOLD_MULT != json gold.jackpot_mult", fails)
		_check(_approx(BalanceMod.AUTO_ATK_COEF, float((table.get("auto_attack", {}) as Dictionary).get("coef", -1.0))), "AUTO_ATK_COEF != json auto_attack.coef", fails)
		_check(_approx(BalanceMod.EST_SECONDS_PER_MOB, float((table.get("idle", {}) as Dictionary).get("est_seconds_per_mob", -1.0))), "EST_SECONDS_PER_MOB != json idle.est_seconds_per_mob", fails)

	# ===== 4. is_boss_stage: BLOCK_SIZE(=10) 배수만 보스 =====
	for s in [1, 9, 11, 15, 99]:
		_check(not BalanceMod.is_boss_stage(s), "is_boss_stage(%d) 가 true (비보스여야 함)" % s, fails)
	for s in [10, 20, 100]:
		_check(BalanceMod.is_boss_stage(s), "is_boss_stage(%d) 가 false (보스여야 함)" % s, fails)

	# ===== 5. block_start: 블록=10 — 보스10 사망→1, 15→11, 보스20→11 =====
	var block_cases: Array = [
		[1, 1], [5, 1], [9, 1], [10, 1],
		[11, 11], [15, 11], [19, 11], [20, 11],
		[21, 21], [100, 91], [101, 101],
	]
	for c in block_cases:
		_check(BalanceMod.block_start(c[0]) == c[1], "block_start(%d) != %d (실제 %d)" % [c[0], c[1], BalanceMod.block_start(c[0])], fails)

	# ===== 5-2. retry_stage: 사망 시 소폭 후퇴 = max(block_start, stage-DEATH_SETBACK) =====
	for s in [1, 5, 7, 9, 10, 11, 14, 17, 20, 100]:
		var expect: int = max(BalanceMod.block_start(s), s - BalanceMod.DEATH_SETBACK)
		_check(BalanceMod.retry_stage(s) == expect, "retry_stage(%d) != %d (실제 %d)" % [s, expect, BalanceMod.retry_stage(s)], fails)
	# 핵심 특성: 후퇴 후 스테이지는 블록 첫 미만으로 안 내려감 + 원래 스테이지 이하
	for s in range(1, 101):
		_check(BalanceMod.retry_stage(s) >= BalanceMod.block_start(s), "retry_stage(%d) 가 블록 첫 미만으로 내려감" % s, fails)
		_check(BalanceMod.retry_stage(s) <= s, "retry_stage(%d) 가 원래 스테이지보다 높음" % s, fails)

	# ===== 6. enemy_hp: 기하 스케일 BASE×GROWTH^(s-1) + 보스 배수 =====
	_check(_approx(BalanceMod.enemy_hp(1), BalanceMod.ENEMY_BASE_HP), "enemy_hp(1) != ENEMY_BASE_HP", fails)
	for s in range(1, 9):  # 1..8 → s, s+1 모두 비보스: 인접 비율 = 성장률 (단조 증가 함의)
		_check(_approx(BalanceMod.enemy_hp(s + 1) / BalanceMod.enemy_hp(s), BalanceMod.ENEMY_HP_GROWTH), "enemy_hp 비율(%d→%d) != ENEMY_HP_GROWTH" % [s, s + 1], fails)
	var hp_geo_10: float = BalanceMod.ENEMY_BASE_HP * pow(BalanceMod.ENEMY_HP_GROWTH, 9)
	_check(_approx(BalanceMod.enemy_hp(10), hp_geo_10 * BalanceMod.BOSS_HP_MULT), "enemy_hp(10) != 기하×BOSS_HP_MULT", fails)
	_check(BalanceMod.enemy_hp(10) > BalanceMod.enemy_hp(9), "보스(10) HP 가 직전 스테이지보다 크지 않음", fails)
	# 특성: 보스 직후(11)는 보스(10)보다 HP 낮음 — 보스 배수 스파이크(의도된 설계, 전구간 단조 아님)
	_check(BalanceMod.enemy_hp(11) < BalanceMod.enemy_hp(10), "enemy_hp(11) >= enemy_hp(10) — 보스 스파이크 특성 변화", fails)

	# ===== 7. gold_reward: 기하 스케일 + 보스 배수 =====
	_check(_approx(BalanceMod.gold_reward(1), BalanceMod.GOLD_BASE), "gold_reward(1) != GOLD_BASE", fails)
	for s in range(1, 9):
		_check(_approx(BalanceMod.gold_reward(s + 1) / BalanceMod.gold_reward(s), BalanceMod.GOLD_GROWTH), "gold_reward 비율(%d→%d) != GOLD_GROWTH" % [s, s + 1], fails)
	var gold_geo_20: float = BalanceMod.GOLD_BASE * pow(BalanceMod.GOLD_GROWTH, 19)
	_check(_approx(BalanceMod.gold_reward(20), gold_geo_20 * BalanceMod.BOSS_GOLD_MULT), "gold_reward(20) != 기하×BOSS_GOLD_MULT", fails)

	# ===== 8. 적 공격: 일반몹 < 보스 (현저히 약함) + 양수·단조·성장률 =====
	for s in [1, 5, 10, 25, 50]:
		var mob_d: float = BalanceMod.mob_attack_damage(s)
		var boss_d: float = BalanceMod.boss_attack_damage(s)
		_check(mob_d > 0.0, "mob_attack_damage(%d) 가 양수가 아님" % s, fails)
		_check(boss_d > 0.0, "boss_attack_damage(%d) 가 양수가 아님" % s, fails)
		_check(mob_d < boss_d, "mob_attack_damage(%d) >= boss_attack_damage(%d) — '현저히 약함' 위배" % [s, s], fails)
	for s in [1, 9, 30]:
		_check(BalanceMod.mob_attack_damage(s + 1) > BalanceMod.mob_attack_damage(s), "mob_attack_damage 단조 증가 위배(%d→%d)" % [s, s + 1], fails)
		_check(BalanceMod.boss_attack_damage(s + 1) > BalanceMod.boss_attack_damage(s), "boss_attack_damage 단조 증가 위배(%d→%d)" % [s, s + 1], fails)
		_check(_approx(BalanceMod.mob_attack_damage(s + 1) / BalanceMod.mob_attack_damage(s), BalanceMod.MOB_ATK_GROWTH), "mob_attack_damage 비율(%d→%d) != MOB_ATK_GROWTH" % [s, s + 1], fails)
		_check(_approx(BalanceMod.boss_attack_damage(s + 1) / BalanceMod.boss_attack_damage(s), BalanceMod.BOSS_ATK_GROWTH), "boss_attack_damage 비율(%d→%d) != BOSS_ATK_GROWTH" % [s, s + 1], fails)

	# ===== 9. offline_rate: 양수 + 정의식(골드/처치추정시간) 일치 =====
	for s in [1, 10, 37]:
		var r: float = BalanceMod.offline_rate(s)
		_check(r > 0.0, "offline_rate(%d) 가 양수가 아님" % s, fails)
		_check(_approx(r, BalanceMod.gold_reward(s) / BalanceMod.EST_SECONDS_PER_MOB), "offline_rate(%d) != gold_reward/EST_SECONDS_PER_MOB" % s, fails)

	# ===== 10. reward_gold: 스테이지 1 미만 클램프 + 배수 적용 =====
	_check(_approx(BalanceMod.reward_gold(0, 2.0), BalanceMod.gold_reward(1) * 2.0), "reward_gold(0,2.0) 가 스테이지 1로 클램프되지 않음", fails)
	_check(_approx(BalanceMod.reward_gold(-3, 1.0), BalanceMod.gold_reward(1)), "reward_gold(-3,1.0) 가 스테이지 1로 클램프되지 않음", fails)
	_check(_approx(BalanceMod.reward_gold(7, 1.5), BalanceMod.gold_reward(7) * 1.5), "reward_gold(7,1.5) != gold_reward(7)×1.5", fails)

	# ===== 11. boss_dust: 비보스=0 / 보스=base+step×(블록인덱스-1) / 보스 간 비감소 =====
	for s in [1, 5, 9, 11, 15, 99]:
		_check(BalanceMod.boss_dust(s) == 0.0, "boss_dust(%d) 가 0 이 아님(비보스)" % s, fails)
	var base: float = BalanceMod.RELIC_DUST_PER_BOSS_BASE
	var step: float = BalanceMod.RELIC_DUST_PER_BOSS_STEP
	var dust_cases: Array = [[10, base], [20, base + step], [30, base + step * 2.0], [100, base + step * 9.0]]
	for c in dust_cases:
		_check(_approx(BalanceMod.boss_dust(c[0]), c[1]), "boss_dust(%d) != %s (실제 %s)" % [c[0], str(c[1]), str(BalanceMod.boss_dust(c[0]))], fails)
	_check(BalanceMod.boss_dust(10) > 0.0, "boss_dust(10) 가 양수가 아님", fails)
	for b in [10, 20, 30, 40, 50]:
		_check(BalanceMod.boss_dust(b + 10) >= BalanceMod.boss_dust(b), "boss_dust 가 보스 간 감소(%d→%d)" % [b, b + 10], fails)

	return fails


func _initialize() -> void:
	var fails: Array = run()
	for msg in fails:
		printerr("  FAIL: %s" % msg)
	if fails.is_empty():
		print("[test_balance] PASS")
	else:
		print("[test_balance] FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
