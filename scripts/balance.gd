class_name Balance
extends RefCounted

# 방치형 전투 밸런스 — 전부 잠정값(튜닝 전). 스테이지 스케일·보스·골드·보스공격.
# 데이터는 data/balance.json (원본 data/src/balance.yaml, 변환 tools/build_data.gd).
# 기획서: docs/design/전투 시스템 정리본.md §4, 게임 컨셉 정리본.md §9·§10.
#
# ⚠️ 이 값들은 static var 다 — game.gd 등이 Balance.MOBS_PER_STAGE 처럼 직접 참조하므로,
#    클래스 로드 시 _static_init()에서 JSON으로 채운다. JSON 누락 시 아래 기본값 유지(폴백).

# ===== 스테이지 / 블록 =====
static var BLOCK_SIZE: int = 10          # 보스 = BLOCK_SIZE 배수 스테이지 (10·20·30…)
static var MOBS_PER_STAGE: int = 5       # 일반 스테이지당 잡몹 수 N
static var DEATH_SETBACK: int = 3        # 사망 시 후퇴 스테이지 수(블록 첫 통째 복귀 X). 블록 첫이 바닥선.

# ===== 적 HP =====  HP(s) = BASE × GROWTH^(s-1)
static var ENEMY_BASE_HP: float = 40.0
static var ENEMY_HP_GROWTH: float = 1.18
static var BOSS_HP_MULT: float = 12.0    # 보스는 같은 스테이지 일반 대비 배수

# ===== 골드 보상 =====  gold(s) = BASE × GROWTH^(s-1)
static var GOLD_BASE: float = 8.0
static var GOLD_GROWTH: float = 1.14
static var BOSS_GOLD_MULT: float = 15.0
static var JACKPOT_GOLD_MULT: float = 3.0  # 잭팟(9칸 동일) 처치 시 골드 보너스 배수

# ===== 적 공격 (보스 + 일반몹) =====
# 일반몹도 PC를 공격하되 보스보다 빈도·데미지가 현저히 낮다(찔끔찔끔, 위협은 작게).
static var BOSS_ATTACK_INTERVAL: float = 1.6
static var BOSS_ATK_BASE: float = 6.0
static var BOSS_ATK_GROWTH: float = 1.16
static var BOSS_ATTACK_WINDUP: float = 0.4
static var MOB_ATTACK_INTERVAL: float = 2.6
static var MOB_ATK_BASE: float = 1.0
static var MOB_ATK_GROWTH: float = 1.12
static var MOB_ATTACK_WINDUP: float = 0.35

# ===== 일반 공격(자동) =====  데미지 = 공격력 × AUTO_ATK_COEF, 발동 주기 = 1/AUTO_ATK_SPEED 초
static var AUTO_ATK_COEF: float = 1.0
static var AUTO_ATK_SPEED: float = 3.3   # 자동공격 초당 횟수(고정 — 옛 attack_speed 강화 폐지, 그 max값을 기본값화)

# ===== 오프라인 정산 (대략 추정) =====
static var EST_SECONDS_PER_MOB: float = 6.0  # 자동 긁기로 잡몹 1마리 처치까지 추정 시간

# ===== 유물 가루 (보스 첫 클리어 보상) =====  dust = base + step×(블록인덱스-1)
# 가챠 비용 고정이라 완만 선형(기하 금지). 첫 클리어만 지급(backend dust_boss_max 가드).
static var RELIC_DUST_PER_BOSS_BASE: float = 50.0
static var RELIC_DUST_PER_BOSS_STEP: float = 10.0

# ===== 던전 "시련의 탑" (데일리 던전) =====
static var DUNGEON_DAILY_TICKETS: int = 10        # 일일 무료 입장권(자정 리셋)
static var DUNGEON_REPEAT_GOLD_MULT: float = 1.0  # 재도전 골드 = gold_reward(stage_equiv) × 이 값
static var DUNGEON_REPEAT_DUST_RATIO: float = 0.2 # 재도전 가루 = 첫 돌파 가루 × 이 비율


static func _static_init() -> void:
	var d: Dictionary = GameData.table("balance")
	if d.is_empty():
		return  # 폴백: 위 기본값 유지
	var stage: Dictionary = d.get("stage", {})
	BLOCK_SIZE = int(stage.get("block_size", BLOCK_SIZE))
	MOBS_PER_STAGE = int(stage.get("mobs_per_stage", MOBS_PER_STAGE))
	DEATH_SETBACK = int(stage.get("death_setback", DEATH_SETBACK))
	var eh: Dictionary = d.get("enemy_hp", {})
	ENEMY_BASE_HP = float(eh.get("base", ENEMY_BASE_HP))
	ENEMY_HP_GROWTH = float(eh.get("growth", ENEMY_HP_GROWTH))
	BOSS_HP_MULT = float(eh.get("boss_mult", BOSS_HP_MULT))
	var g: Dictionary = d.get("gold", {})
	GOLD_BASE = float(g.get("base", GOLD_BASE))
	GOLD_GROWTH = float(g.get("growth", GOLD_GROWTH))
	BOSS_GOLD_MULT = float(g.get("boss_mult", BOSS_GOLD_MULT))
	JACKPOT_GOLD_MULT = float(g.get("jackpot_mult", JACKPOT_GOLD_MULT))
	var ea: Dictionary = d.get("enemy_attack", {})
	var boss: Dictionary = ea.get("boss", {})
	BOSS_ATTACK_INTERVAL = float(boss.get("interval", BOSS_ATTACK_INTERVAL))
	BOSS_ATK_BASE = float(boss.get("base", BOSS_ATK_BASE))
	BOSS_ATK_GROWTH = float(boss.get("growth", BOSS_ATK_GROWTH))
	BOSS_ATTACK_WINDUP = float(boss.get("windup", BOSS_ATTACK_WINDUP))
	var mob: Dictionary = ea.get("mob", {})
	MOB_ATTACK_INTERVAL = float(mob.get("interval", MOB_ATTACK_INTERVAL))
	MOB_ATK_BASE = float(mob.get("base", MOB_ATK_BASE))
	MOB_ATK_GROWTH = float(mob.get("growth", MOB_ATK_GROWTH))
	MOB_ATTACK_WINDUP = float(mob.get("windup", MOB_ATTACK_WINDUP))
	var aa: Dictionary = d.get("auto_attack", {})
	AUTO_ATK_COEF = float(aa.get("coef", AUTO_ATK_COEF))
	AUTO_ATK_SPEED = float(aa.get("speed", AUTO_ATK_SPEED))
	EST_SECONDS_PER_MOB = float((d.get("idle", {}) as Dictionary).get("est_seconds_per_mob", EST_SECONDS_PER_MOB))
	var rd: Dictionary = d.get("relic_dust", {})
	RELIC_DUST_PER_BOSS_BASE = float(rd.get("per_boss_base", RELIC_DUST_PER_BOSS_BASE))
	RELIC_DUST_PER_BOSS_STEP = float(rd.get("per_boss_step", RELIC_DUST_PER_BOSS_STEP))
	var dg: Dictionary = d.get("dungeon", {})
	DUNGEON_DAILY_TICKETS = int(dg.get("daily_tickets", DUNGEON_DAILY_TICKETS))
	DUNGEON_REPEAT_GOLD_MULT = float(dg.get("repeat_gold_mult", DUNGEON_REPEAT_GOLD_MULT))
	DUNGEON_REPEAT_DUST_RATIO = float(dg.get("repeat_dust_ratio", DUNGEON_REPEAT_DUST_RATIO))


static func is_boss_stage(stage: int) -> bool:
	return stage % BLOCK_SIZE == 0


static func block_start(stage: int) -> int:
	# 해당 스테이지가 속한 블록의 첫 스테이지 (보스10→1, 20→11, 30→21)
	return ((stage - 1) / BLOCK_SIZE) * BLOCK_SIZE + 1


static func retry_stage(stage: int) -> int:
	# 사망 시 복귀 스테이지 = DEATH_SETBACK 만큼 소폭 후퇴, 단 현재 블록 첫 스테이지가 바닥선
	# (블록 경계 아래로는 안 내려감). 예) 보스10 사망 + setback3 → 7 / 보스20 + setback3 → 17.
	return max(block_start(stage), stage - DEATH_SETBACK)


static func _geo(base: float, growth: float, stage: int) -> float:
	# 기하 스케일 공통식 BASE × GROWTH^(s-1) (적HP/골드/보스공격/일반몹공격 공용).
	return base * pow(growth, stage - 1)


static func base_enemy_hp(stage: int) -> float:
	# 보스 배수 미적용 기하 HP. 던전 등 커스텀 보스 HP 산정용(stage가 보스배수여도 이중계상 방지).
	return _geo(ENEMY_BASE_HP, ENEMY_HP_GROWTH, stage)


static func enemy_hp(stage: int) -> float:
	var base: float = _geo(ENEMY_BASE_HP, ENEMY_HP_GROWTH, stage)
	if is_boss_stage(stage):
		return base * BOSS_HP_MULT
	return base


static func gold_reward(stage: int) -> float:
	var g: float = _geo(GOLD_BASE, GOLD_GROWTH, stage)
	if is_boss_stage(stage):
		return g * BOSS_GOLD_MULT
	return g


static func boss_attack_damage(stage: int) -> float:
	return _geo(BOSS_ATK_BASE, BOSS_ATK_GROWTH, stage)


static func mob_attack_damage(stage: int) -> float:
	# 일반몹 PC 공격 데미지 (보스보다 현저히 낮음).
	return _geo(MOB_ATK_BASE, MOB_ATK_GROWTH, stage)


static func offline_rate(stage: int) -> float:
	# 초당 골드(대략). 잡몹 farming 기준.
	return gold_reward(stage) / EST_SECONDS_PER_MOB


# ===== 리텐션 보상 (출석/퀘스트/업적) =====
# 고정 골드는 후반에 무의미 → 현재 스테이지 골드 보상에 비례시킨다.
# 리텐션 시스템 정리본 §5.
static func reward_gold(stage: int, mult: float) -> float:
	return gold_reward(max(1, stage)) * mult


# ===== 유물 가루 (보스 첫 클리어) =====
static func boss_dust(stage: int) -> float:
	# 보스 첫 클리어 가루 보상. 완만 선형(블록마다 +step), 기하 금지(가챠 비용 고정). 비보스=0.
	# 첫 클리어 판정(재파밍 차단)은 backend.grant_boss_dust(dust_boss_max)가 담당.
	if not is_boss_stage(stage):
		return 0.0
	var block_index: int = stage / BLOCK_SIZE  # 보스10→1, 20→2, 30→3…
	return RELIC_DUST_PER_BOSS_BASE + RELIC_DUST_PER_BOSS_STEP * float(block_index - 1)
