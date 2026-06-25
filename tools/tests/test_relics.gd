extends SceneTree
# 대상 모듈: scripts/relics.gd — 유물 데이터·가챠·효과 강도 (데이터: res://data/relics.json)
# 단독 실행 (headless, autoload 불필요 — 대상이 순수 static 모듈):
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_relics.gd
# 전부 통과 → "[test_relics] PASS" + exit 0 / 실패 → FAIL 목록 + exit 1.
# 기대값은 코드/데이터의 실제 동작 기준(characterization) — relics.json 수치 변경 시 함께 갱신.

const RelicsScript := preload("res://scripts/relics.gd")
const GameDataScript := preload("res://scripts/game_data.gd")

# 카탈로그 kind 유효 집합 (relics.gd 주석 기준: ①dist_suppress ⑤grade_mult ④wild ②expand)
const VALID_KINDS := ["dist_suppress", "grade_mult", "wild", "expand"]
const VALID_BANDS := ["low", "mid", "high"]
const VALID_PATTERNS := ["two_pair", "full_house"]
const ROLL_N := 2000
const SEED := 20260611


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []
	_case_grades(fails)
	_case_catalog(fails)
	_case_roll(fails)
	_case_intensity(fails)
	_case_constants(fails)
	_case_unknown_inputs(fails)
	return fails


# ---------- ① 등급 데이터 로드: grade_order ↔ grades 정합 + grade_index 단조 ----------

static func _case_grades(fails: Array) -> void:
	var t: Dictionary = GameDataScript.table("relics")
	var grades: Dictionary = t.get("grades", {})
	var order: Array = t.get("grade_order", [])
	var ids: Array = RelicsScript.grade_ids()
	_check(not ids.is_empty(), "grade_ids 가 비어 있음 — data/relics.json 로드 실패?", fails)
	# grade_order ↔ grades 상호 누락 없음
	for g in order:
		_check(grades.has(g), "grade_order 의 '%s' 가 grades 에 없음" % g, fails)
	for g in grades:
		_check(order.has(g), "grades 의 '%s' 가 grade_order 에 없음" % g, fails)
	# 정합 시 grade_ids = grade_order 순서 그대로 (ordered_ids: order 우선)
	_check(ids.size() == grades.size(), "grade_ids 개수(%d) != grades 개수(%d)" % [ids.size(), grades.size()], fails)
	for i in range(min(ids.size(), order.size())):
		_check(str(ids[i]) == str(order[i]), "grade_ids[%d]='%s' != grade_order[%d]='%s'" % [i, ids[i], i, order[i]], fails)
	# grade_index 단조: 순서대로 0,1,2,...
	for i in range(ids.size()):
		_check(RelicsScript.grade_index(ids[i]) == i, "grade_index('%s') != %d" % [ids[i], i], fails)


# ---------- ② 카탈로그 로드: kind/band/pattern 유효성 + catalog_order 정렬 ----------

static func _case_catalog(fails: Array) -> void:
	var t: Dictionary = GameDataScript.table("relics")
	var catalog: Dictionary = t.get("catalog", {})
	var order: Array = t.get("catalog_order", [])
	var ids: Array = RelicsScript.catalog_ids()
	_check(not ids.is_empty(), "catalog_ids 가 비어 있음", fails)
	_check(ids.size() == catalog.size(), "catalog_ids 개수(%d) != catalog 개수(%d)" % [ids.size(), catalog.size()], fails)
	# catalog_order 가 앞부분 순서를 결정
	for i in range(min(ids.size(), order.size())):
		_check(str(ids[i]) == str(order[i]), "catalog_ids[%d]='%s' != catalog_order[%d]='%s'" % [i, ids[i], i, order[i]], fails)
	# 효과별 메타 유효성
	for id in ids:
		var kind: String = RelicsScript.relic_kind(id)
		_check(VALID_KINDS.has(kind), "'%s' kind='%s' 가 유효 집합에 없음" % [id, kind], fails)
		_check(RelicsScript.relic_name(id) != "", "'%s' 의 name 이 빈 문자열" % id, fails)
		if kind == "grade_mult":
			_check(VALID_BANDS.has(RelicsScript.relic_band(id)), "'%s'(grade_mult) band='%s' 무효" % [id, RelicsScript.relic_band(id)], fails)
		if kind == "expand":
			_check(VALID_PATTERNS.has(RelicsScript.relic_pattern(id)), "'%s'(expand) pattern='%s' 무효" % [id, RelicsScript.relic_pattern(id)], fails)


# ---------- ③ roll(): seed 고정 다회 — 유효 effect/grade 불변식 + 가중치 통계 ----------

static func _case_roll(fails: Array) -> void:
	seed(SEED)
	var ids: Array = RelicsScript.catalog_ids()
	var gids: Array = RelicsScript.grade_ids()
	var first: Dictionary = RelicsScript.roll()
	_check(first.has("effect") and first.has("grade") and first.has("name") and first.has("kind"),
		"roll() 반환 키 누락: %s" % str(first.keys()), fails)
	var all_valid := true
	var counts: Dictionary = {}
	for i in range(ROLL_N):
		var r: Dictionary = RelicsScript.roll()
		if r.is_empty() \
				or not ids.has(r.get("effect")) \
				or not gids.has(r.get("grade")) \
				or r.get("name") != RelicsScript.relic_name(r.get("effect")) \
				or r.get("kind") != RelicsScript.relic_kind(r.get("effect")):
			all_valid = false
			break
		var g: String = r.get("grade")
		counts[g] = int(counts.get(g, 0)) + 1
	_check(all_valid, "roll() %d회 중 무효 결과 발생 (effect/grade/name/kind 불변식 위반)" % ROLL_N, fails)
	# 가중치 통계(데이터: common 60 / mythic 0.5, 합 100) — 넉넉한 허용오차
	var common_ratio := float(int(counts.get("common", 0))) / float(ROLL_N)
	var mythic_ratio := float(int(counts.get("mythic", 0))) / float(ROLL_N)
	_check(common_ratio > 0.5 and common_ratio < 0.7,
		"common 비율 %.3f 이 기대(0.60±0.10) 밖" % common_ratio, fails)
	_check(mythic_ratio <= 0.03, "mythic 비율 %.3f 이 과다(기대 ~0.005)" % mythic_ratio, fails)
	# roll_many: 개수 보장 + 음수/0 안전
	var many: Array = RelicsScript.roll_many(11)
	_check(many.size() == 11, "roll_many(11) 크기 %d != 11" % many.size(), fails)
	var many_valid := true
	for r in many:
		if not (r is Dictionary) or r.is_empty() or not ids.has(r.get("effect")):
			many_valid = false
	_check(many_valid, "roll_many(11) 결과에 무효 항목 존재", fails)
	_check((RelicsScript.roll_many(0) as Array).is_empty(), "roll_many(0) 이 비어 있지 않음", fails)
	_check((RelicsScript.roll_many(-5) as Array).is_empty(), "roll_many(-5) 가 비어 있지 않음", fails)


# ---------- ④ 효과 강도 테이블: 등급 오름차순 = 강도 강증가(단조) + 끝값 ----------

static func _check_monotone_up(fn: String, fails: Array) -> void:
	# 등급이 오를수록 값이 strictly 증가해야 함 (코드 실제 데이터 기준)
	var gids: Array = RelicsScript.grade_ids()
	var prev := -INF
	var fn_call := Callable(RelicsScript, fn)
	for g in gids:
		var v := float(fn_call.call(g))
		_check(v > prev, "%s('%s')=%.3f 이 이전 등급 값(%.3f)보다 크지 않음 — 단조성 위반" % [fn, g, v, prev], fails)
		prev = v


static func _case_intensity(fails: Array) -> void:
	var gids: Array = RelicsScript.grade_ids()
	# 4종 전부 등급 단조 증가
	_check_monotone_up("dist_reduction", fails)   # ① 저숫자 억제 램프
	_check_monotone_up("grade_bonus", fails)      # ⑤ 밴드 배율 보너스
	_check_monotone_up("wild_chance", fails)      # ④ 와일드 발생 확률
	_check_monotone_up("expand_bonus", fails)     # ② 족보 확장 배율
	# 끝값/범위: 신화=최대 (dist 1.0=완전 제거, wild 1.0=항상 발동)
	_check(is_equal_approx(RelicsScript.dist_reduction("mythic"), 1.0), "dist_reduction(mythic) != 1.0", fails)
	_check(is_equal_approx(RelicsScript.wild_chance("mythic"), 1.0), "wild_chance(mythic) != 1.0", fails)
	var ratios_in_range := true
	var bonus_positive := true
	for g in gids:
		var d := float(RelicsScript.dist_reduction(g))
		var w := float(RelicsScript.wild_chance(g))
		if d < 0.0 or d > 1.0 or w < 0.0 or w > 1.0:
			ratios_in_range = false
		if float(RelicsScript.grade_bonus(g)) <= 0.0 or float(RelicsScript.expand_bonus(g)) <= 0.0:
			bonus_positive = false
	_check(ratios_in_range, "dist_reduction/wild_chance 가 [0,1] 범위 밖", fails)
	_check(bonus_positive, "grade_bonus/expand_bonus 에 0 이하 값 존재", fails)
	# ⑤ 밴드 범위: [lo, hi] 형식 + 저<중<고 순 비겹침 + 카드 count(2~9) 안
	var lo_band: Array = RelicsScript.band_range("low")
	var mid_band: Array = RelicsScript.band_range("mid")
	var hi_band: Array = RelicsScript.band_range("high")
	for pair in [["low", lo_band], ["mid", mid_band], ["high", hi_band]]:
		var b: Array = pair[1]
		_check(b.size() == 2, "band_range('%s') 크기 %d != 2" % [pair[0], b.size()], fails)
		if b.size() == 2:
			_check(int(b[0]) <= int(b[1]), "band_range('%s') lo(%d) > hi(%d)" % [pair[0], int(b[0]), int(b[1])], fails)
	if lo_band.size() == 2 and mid_band.size() == 2 and hi_band.size() == 2:
		_check(int(lo_band[1]) < int(mid_band[0]), "저밴드 hi(%d) 가 중밴드 lo(%d) 와 겹침" % [int(lo_band[1]), int(mid_band[0])], fails)
		_check(int(mid_band[1]) < int(hi_band[0]), "중밴드 hi(%d) 가 고밴드 lo(%d) 와 겹침" % [int(mid_band[1]), int(hi_band[0])], fails)
		_check(int(lo_band[0]) >= 2, "저밴드 lo(%d) < 2 (같은 숫자 2개 미만은 족보 아님)" % int(lo_band[0]), fails)
		_check(int(hi_band[1]) <= 9, "고밴드 hi(%d) > 9 (3×3 최대 count)" % int(hi_band[1]), fails)


# ---------- ⑤ 상수 getter (현재 데이터 기준 characterization) ----------

static func _case_constants(fails: Array) -> void:
	_check(RelicsScript.slot_count() == 5, "slot_count() %d != 5" % RelicsScript.slot_count(), fails)
	_check(RelicsScript.wild_cap() == 2, "wild_cap() %d != 2" % RelicsScript.wild_cap(), fails)
	_check(RelicsScript.pool_floor() == 3, "pool_floor() %d != 3" % RelicsScript.pool_floor(), fails)
	_check(RelicsScript.gacha_cost() == 100, "gacha_cost() %d != 100" % RelicsScript.gacha_cost(), fails)
	_check(RelicsScript.gacha_cost_11() == 1000, "gacha_cost_11() %d != 1000" % RelicsScript.gacha_cost_11(), fails)
	_check(RelicsScript.gacha_cost_11() >= RelicsScript.gacha_cost(), "11연차 비용이 1회 비용보다 쌈", fails)
	# 무료 확정 소환(초반 부트스트랩, 사전 설정): count = effects 길이, grant 가 사전 설정 효과/등급을 그대로 반환.
	_check(RelicsScript.free_pull_count() == 1, "free_pull_count() %d != 1" % RelicsScript.free_pull_count(), fails)
	var g0: Dictionary = RelicsScript.free_pull_grant(0)
	_check(not g0.is_empty(), "free_pull_grant(0) 가 비어 있음", fails)
	_check(str(g0.get("effect", "")) == "r_dist_low", "free_pull_grant(0).effect %s != r_dist_low" % str(g0.get("effect", "")), fails)
	_check(str(g0.get("grade", "")) == "rare", "free_pull_grant(0).grade %s != rare" % str(g0.get("grade", "")), fails)
	_check(RelicsScript.catalog_ids().has(str(g0.get("effect", ""))), "free_pull 효과가 카탈로그에 없음", fails)
	_check(RelicsScript.grade_ids().has(str(g0.get("grade", ""))), "free_pull 등급이 grades에 없음", fails)
	_check(str(g0.get("name", "")) == RelicsScript.relic_name(str(g0.get("effect", ""))), "free_pull_grant name 불일치", fails)
	# 범위 밖 인덱스 → {}
	_check(RelicsScript.free_pull_grant(RelicsScript.free_pull_count()).is_empty(), "free_pull_grant(범위밖)이 비어있지 않음", fails)
	_check(RelicsScript.free_pull_grant(-1).is_empty(), "free_pull_grant(-1)이 비어있지 않음", fails)
	# 가루 구매(상점 재화): 팩 개수>0, 각 팩 amount/cost 양수, 범위 밖 {}.
	_check(RelicsScript.dust_shop_count() == 2, "dust_shop_count() %d != 2" % RelicsScript.dust_shop_count(), fails)
	for i in range(RelicsScript.dust_shop_count()):
		var pk: Dictionary = RelicsScript.dust_shop_pack(i)
		_check(int(pk.get("amount", 0)) > 0, "dust_shop_pack(%d).amount 양수 아님" % i, fails)
		_check(int(pk.get("cost", 0)) > 0, "dust_shop_pack(%d).cost 양수 아님" % i, fails)
	_check(RelicsScript.dust_shop_pack(RelicsScript.dust_shop_count()).is_empty(), "dust_shop_pack(범위밖)이 비어있지 않음", fails)
	_check(RelicsScript.dust_shop_pack(-1).is_empty(), "dust_shop_pack(-1)이 비어있지 않음", fails)


# ---------- ⑥ 알 수 없는 effect/grade 입력 안전 동작 (코드 기준 기본값) ----------

static func _case_unknown_inputs(fails: Array) -> void:
	var nope := "__no_such_id__"
	_check(RelicsScript.grade_index(nope) == 0, "grade_index(미지 등급) != 0", fails)
	_check(RelicsScript.dist_reduction(nope) == 0.0, "dist_reduction(미지 등급) != 0.0", fails)
	_check(RelicsScript.grade_bonus(nope) == 0.0, "grade_bonus(미지 등급) != 0.0", fails)
	_check(RelicsScript.wild_chance(nope) == 0.0, "wild_chance(미지 등급) != 0.0", fails)
	_check(RelicsScript.expand_bonus(nope) == 0.0, "expand_bonus(미지 등급) != 0.0", fails)
	_check(RelicsScript.relic_name(nope) == nope, "relic_name(미지 효과)이 입력 id 폴백이 아님", fails)
	_check(RelicsScript.relic_kind(nope) == "", "relic_kind(미지 효과) != \"\"", fails)
	_check(RelicsScript.relic_band(nope) == "", "relic_band(미지 효과) != \"\"", fails)
	_check(RelicsScript.relic_pattern(nope) == "", "relic_pattern(미지 효과) != \"\"", fails)
	_check(RelicsScript.relic_desc(nope, "common") == "", "relic_desc(미지 효과) != \"\"", fails)
	_check((RelicsScript.band_range(nope) as Array).is_empty(), "band_range(미지 밴드)가 빈 Array 아님", fails)
	_check(RelicsScript.band_name("xyz") == "xyz", "band_name 미지 입력 passthrough 실패", fails)
	_check(RelicsScript.pattern_name("xyz") == "xyz", "pattern_name 미지 입력 passthrough 실패", fails)
	# relic_desc 정상 경로 (kind 4종 + 신화 완전제거 분기) — 현재 데이터 수치 기준
	_check(RelicsScript.relic_desc("r_dist_low", "common") == "낮은 숫자 -30%",
		"relic_desc(r_dist_low, common) = '%s'" % RelicsScript.relic_desc("r_dist_low", "common"), fails)
	_check(RelicsScript.relic_desc("r_dist_low", "mythic") == "낮은 숫자 제거",
		"relic_desc(r_dist_low, mythic) = '%s'" % RelicsScript.relic_desc("r_dist_low", "mythic"), fails)
	_check(RelicsScript.relic_desc("r_boost_mid", "mythic") == "중족보 배율 +200%",
		"relic_desc(r_boost_mid, mythic) = '%s'" % RelicsScript.relic_desc("r_boost_mid", "mythic"), fails)
	_check(RelicsScript.relic_desc("r_wild", "common") == "와일드 40% (매칭+1)",
		"relic_desc(r_wild, common) = '%s'" % RelicsScript.relic_desc("r_wild", "common"), fails)
	_check(RelicsScript.relic_desc("r_expand_2pair", "rare") == "투페어 인정 +100%",
		"relic_desc(r_expand_2pair, rare) = '%s'" % RelicsScript.relic_desc("r_expand_2pair", "rare"), fails)


func _initialize() -> void:
	var fails: Array = run()
	for f in fails:
		printerr("  FAIL: %s" % f)
	if fails.is_empty():
		print("[test_relics] PASS")
	else:
		print("[test_relics] FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
