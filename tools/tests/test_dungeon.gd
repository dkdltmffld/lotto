extends SceneTree

# ============================================================================
# 대상 모듈: res://scripts/dungeon_data.gd (던전 "시련의 탑" 층 데이터)
#   데이터 출처: res://data/dungeon.json (GameData.table("dungeon") 경유 1회 로드)
#   autoload 미사용 — headless --script 모드에서 단독 실행 가능.
# 단독 실행:
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_dungeon.gd
# ============================================================================

const DungeonMod := preload("res://scripts/dungeon_data.gd")
const GameDataMod := preload("res://scripts/game_data.gd")
const BalanceMod := preload("res://scripts/balance.gd")


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []

	# ===== 1. JSON 테이블 로드 + 층 개수 =====
	var table: Dictionary = GameDataMod.table("dungeon")
	_check(not table.is_empty(), "GameData.table(\"dungeon\") 가 비어 있음 — data/dungeon.json 로드 실패", fails)
	var n: int = DungeonMod.floor_count()
	_check(n > 0, "floor_count()<=0 — 층 데이터 없음", fails)

	# ===== 2. 각 층 기본 무결성: stage_equiv>0, hp_mult>0, boss_hp/boss_attack>0 =====
	var prev_equiv: int = 0
	for f in range(1, n + 1):
		var se: int = DungeonMod.stage_equiv(f)
		_check(se > 0, "%d층 stage_equiv<=0" % f, fails)
		_check(se >= prev_equiv, "%d층 stage_equiv 가 직전보다 작음(난이도 역행)" % f, fails)
		prev_equiv = se
		_check(DungeonMod.hp_mult(f) > 0.0, "%d층 hp_mult<=0" % f, fails)
		_check(DungeonMod.boss_hp(f) > 0, "%d층 boss_hp<=0" % f, fails)
		_check(DungeonMod.boss_attack(f) > 0, "%d층 boss_attack<=0" % f, fails)
		# 룰 범위
		var hg: int = DungeonMod.hand_gate(f)
		_check(hg == 0 or (hg >= 1 and hg <= 9), "%d층 hand_gate 범위 밖: %d" % [f, hg], fails)
		_check(DungeonMod.time_limit(f) >= 0.0, "%d층 time_limit<0" % f, fails)
		var pd: float = DungeonMod.pc_atk_down(f)
		_check(pd >= 0.0 and pd < 1.0, "%d층 pc_atk_down 범위 밖: %s" % [f, str(pd)], fails)
		# 보상 음수 금지
		_check(DungeonMod.dia(f) >= 0.0, "%d층 dia<0" % f, fails)
		_check(DungeonMod.dust(f) >= 0.0, "%d층 dust<0" % f, fails)
		# rule_text 항상 비어 있지 않음(표기용)
		_check(DungeonMod.rule_text(f) != "", "%d층 rule_text 비어있음" % f, fails)

	# ===== 3. boss_hp 정의식: base_enemy_hp(stage_equiv) × BOSS_HP_MULT × hp_mult =====
	for f in range(1, n + 1):
		var expect: int = int(ceil(BalanceMod.base_enemy_hp(DungeonMod.stage_equiv(f)) * BalanceMod.BOSS_HP_MULT * DungeonMod.hp_mult(f)))
		_check(DungeonMod.boss_hp(f) == expect, "%d층 boss_hp 정의식 불일치(%d != %d)" % [f, DungeonMod.boss_hp(f), expect], fails)

	# ===== 4. 파일 순서 매핑(1-based) — yaml 작성 순서가 층 번호 =====
	# (data/src/dungeon.yaml 의 floor_1 stage_equiv=4, floor_5 hand_gate=2, floor_7 time_limit=60, floor_9 pc_atk_down=0.4 와 대조)
	if n >= 9:
		_check(DungeonMod.stage_equiv(1) == 4, "1층 stage_equiv != 4 (파일 순서 매핑 깨짐)", fails)
		_check(DungeonMod.hand_gate(5) == 2, "5층 hand_gate != 2", fails)
		_check(int(DungeonMod.time_limit(7)) == 60, "7층 time_limit != 60", fails)
		_check(abs(DungeonMod.pc_atk_down(9) - 0.4) < 0.001, "9층 pc_atk_down != 0.4", fails)

	# ===== 5. 범위 밖 층 = 안전 기본값(보상 0, 룰 0) — 무한 꼬리/오류 대비 =====
	var oob: int = n + 1
	_check(DungeonMod.dia(oob) == 0.0 and DungeonMod.dust(oob) == 0.0, "범위 밖 층 보상이 0이 아님", fails)
	_check(DungeonMod.hand_gate(oob) == 0 and DungeonMod.time_limit(oob) == 0.0, "범위 밖 층 룰이 0이 아님", fails)
	_check(DungeonMod.dia(0) == 0.0, "0층(무효) 보상이 0이 아님", fails)

	return fails


func _initialize() -> void:
	var fails: Array = run()
	for msg in fails:
		printerr("  FAIL: %s" % msg)
	if fails.is_empty():
		print("[test_dungeon] PASS")
	else:
		print("[test_dungeon] FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
