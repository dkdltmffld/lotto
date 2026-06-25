extends SceneTree
# ============================================================
# build_data.gd — data/src/*.yaml → data/*.json 변환 + 가벼운 검증.
# 실행: godot --headless --path . --script res://tools/build_data.gd
#
# Python 불필요 — Godot 내부(순수 GDScript)에서 변환한다. 게임 런타임은 data/*.json
# 만 읽는다(YAML 파서를 웹에 싣지 않기 위함). 여기 파서는 우리가 쓰는 YAML 서브셋만
# 지원한다: 중첩 맵 / 인라인 스칼라 리스트([a, b, c]) / 스칼라(int·float·bool·null·문자열) /
# 주석(#, 따옴표 안은 보존). 블록 리스트(- item)·앵커·멀티독은 미지원(카탈로그는 맵으로 작성).
# ============================================================

const SRC_DIR := "res://data/src/"
const OUT_DIR := "res://data/"
const FILES := ["balance", "upgrades", "achievements", "enemies", "equipment", "relics", "quests_main", "quests_daily", "dungeon"]

var _yaml_warns: Array = []  # 파서가 조용히 무시한 구조(과들여쓰기 등) — 검증 단계에서 표면화


func _initialize() -> void:
	var errors: Array = []
	var warns: Array = []
	print("[build_data] 변환 시작")
	for fname in FILES:
		var src_path: String = SRC_DIR + fname + ".yaml"
		var f := FileAccess.open(src_path, FileAccess.READ)
		if f == null:
			errors.append("열기 실패: " + src_path)
			continue
		var text := f.get_as_text()
		f.close()
		var data: Dictionary = _parse_yaml(text)
		for sw in _yaml_warns:
			warns.append("%s: %s" % [fname, sw])
		_validate(fname, data, errors, warns)
		var out_path: String = OUT_DIR + fname + ".json"
		var jf := FileAccess.open(out_path, FileAccess.WRITE)
		if jf == null:
			errors.append("쓰기 실패: " + out_path)
			continue
		# sort_keys=false: 키를 알파벳 정렬하지 않고 **YAML 작성 순서(파일 순서)를 보존**한다.
		# (퀘스트 등은 별도 order 리스트 없이 yaml 위→아래 순서를 그대로 정렬로 쓴다.)
		# ⚠️ 모든 data/*.json 에 적용 — 런타임 코드가 json 키 순서에 의존하면 안 됨(순서가 필요하면
		#    명시 order 배열 + GameData.ordered_ids 를 써라. upgrades/relics/equipment 가 그 방식).
		jf.store_string(JSON.stringify(data, "  ", false))
		jf.close()
		print("  ✓ %s → %s" % [src_path, out_path])
	for w in warns:
		print("  ⚠ ", w)
	if errors.is_empty():
		print("[build_data] 완료 (errors 0, warns %d)" % warns.size())
		quit(0)
	else:
		printerr("[build_data] 실패 (errors %d):" % errors.size())
		for e in errors:
			printerr("  ✗ ", e)
		quit(1)


# ── YAML 서브셋 파서 ─────────────────────────────────────────────────────────

func _parse_yaml(text: String) -> Dictionary:
	_yaml_warns = []
	var lines: Array = []  # [{indent:int, text:String}]
	for raw in text.split("\n"):
		var line := _strip_comment(raw)
		if line.strip_edges() == "":
			continue
		var indent := 0
		while indent < line.length() and line[indent] == " ":
			indent += 1
		lines.append({"indent": indent, "text": line.substr(indent).strip_edges()})
	return _parse_map(lines, 0, 0)[0]


func _parse_map(lines: Array, i: int, indent: int) -> Array:
	var out: Dictionary = {}
	while i < lines.size():
		var ln: Dictionary = lines[i]
		if int(ln["indent"]) < indent:
			break
		if int(ln["indent"]) > indent:
			# 정상 입력엔 없음 — 과들여쓰기는 조용히 버리지 말고 경고로 표면화(오타/구조 실수 탐지).
			_yaml_warns.append("들여쓰기 과다로 무시된 줄: '%s'" % ln["text"])
			i += 1
			continue
		var t: String = ln["text"]
		var colon := t.find(":")
		if colon < 0:
			i += 1
			continue
		var key := _unquote(t.substr(0, colon).strip_edges())
		var rest := t.substr(colon + 1).strip_edges()
		if rest == "":
			# 다음 줄이 더 깊으면 중첩 맵, 아니면 빈 값
			if i + 1 < lines.size() and int(lines[i + 1]["indent"]) > indent:
				var child := _parse_map(lines, i + 1, int(lines[i + 1]["indent"]))
				out[key] = child[0]
				i = int(child[1])
			else:
				out[key] = null
				i += 1
		else:
			out[key] = _parse_value(rest)
			i += 1
	return [out, i]


func _strip_comment(line: String) -> String:
	# 따옴표 밖의 첫 '#'부터 주석. 전체줄 주석이면 "" 반환(→ 스킵됨).
	var in_s := false
	var q := ""
	for j in line.length():
		var c := line[j]
		if in_s:
			if c == q:
				in_s = false
		elif c == "\"" or c == "'":
			in_s = true
			q = c
		elif c == "#":
			return line.substr(0, j)
	return line


func _parse_value(s: String) -> Variant:
	s = s.strip_edges()
	if s.begins_with("[") and s.ends_with("]"):
		var inner := s.substr(1, s.length() - 2).strip_edges()
		var arr: Array = []
		if inner != "":
			for part in inner.split(","):
				arr.append(_parse_scalar(part.strip_edges()))
		return arr
	return _parse_scalar(s)


func _parse_scalar(s: String) -> Variant:
	s = s.strip_edges()
	if s.length() >= 2 and ((s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'"))):
		return s.substr(1, s.length() - 2)
	if s == "true":
		return true
	if s == "false":
		return false
	if s == "null" or s == "~" or s == "":
		return null
	if not s.contains(".") and not s.contains("e") and not s.contains("E") and s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	return s


func _unquote(s: String) -> String:
	if s.length() >= 2 and ((s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'"))):
		return s.substr(1, s.length() - 2)
	return s


# ── 검증 (lotto_compile.py 가드레일 이식) ────────────────────────────────────

func _validate(fname: String, data: Dictionary, errors: Array, warns: Array) -> void:
	match fname:
		"quests_main", "quests_daily":
			# 단일 퀘스트 시트(quests 맵, 정렬=yaml 파일 순서). 메인/일일 분리.
			# 보상=통화키 맵({dia:50}). stat 화이트리스트로 오타 차단.
			var qallowed := ["gold", "dia", "dust"]
			var qstats := ["total_kills", "upgrades_bought", "boss_kills", "gold_earned", "equipment_pulls", "relic_pulls", "summon_pulls", "stage_reached"]
			# 트랙별 강화 통계 upgrades_bought_<track> (퀘스트 "공격력 강화 N회" 등). upgrades.yaml tracks 와 동기화.
			for trk in ["attack", "hp", "hp_regen", "card_mult", "auto_speed", "brush", "storage"]:
				qstats.append("upgrades_bought_" + trk)
				qstats.append("level_" + trk)  # 강화 N단계 도달 퀘스트용(파생 stat)
			var qcat: Dictionary = data.get("quests", {})
			if qcat.is_empty():
				errors.append("%s.quests: 비어있음" % fname)
			for qid in qcat:
				var q: Dictionary = qcat[qid] if qcat[qid] is Dictionary else {}
				if q.is_empty():
					errors.append("%s.%s: 맵이 아님/비어있음 — 들여쓰기 확인" % [fname, qid])
					continue
				for k in ["title", "desc", "stat", "target"]:
					if not q.has(k):
						errors.append("%s.%s: 필수 필드 '%s' 누락" % [fname, qid, k])
				if int(q.get("target", 0)) <= 0:
					errors.append("%s.%s: target<=0" % [fname, qid])
				# stat 오타 = 진행도 영영 0(잠복 버그, Codex #15 P2 류) → 빌드 시 표면화.
				if not qstats.has(str(q.get("stat", ""))):
					warns.append("%s.%s: 알 수 없는 stat '%s' (오타?)" % [fname, qid, q.get("stat", "")])
				# exposed 따옴표 오타("false" 문자열 → bool true 평가로 숨김 의도 깨짐) 방지.
				if q.has("exposed") and not (q["exposed"] is bool):
					warns.append("%s.%s: exposed 가 bool 아님(따옴표 오타?)" % [fname, qid])
				var rw: Dictionary = q.get("rewards", {}) if q.get("rewards") is Dictionary else {}
				if rw.is_empty():
					warns.append("%s.%s: 보상 없음(무보상 수령 불가)" % [fname, qid])
				for cur in rw:
					if not qallowed.has(str(cur)):
						errors.append("%s.%s: 허용 안 된 보상 통화 '%s'" % [fname, qid, cur])
					elif float(rw[cur]) <= 0.0:
						errors.append("%s.%s: 보상 '%s' 금액<=0" % [fname, qid, cur])
		"upgrades":
			var tracks: Dictionary = data.get("tracks", {})
			if tracks.is_empty():
				errors.append("upgrades.tracks: 비어있음")
			for tid in tracks:
				if not (tracks[tid] is Dictionary):
					errors.append("upgrades.%s: 트랙이 맵이 아님(null/스칼라) — 들여쓰기 확인" % tid)
					continue
				var tr: Dictionary = tracks[tid]
				for k in ["base_cost", "cost_growth", "base_val", "per_level"]:
					if not tr.has(k):
						errors.append("upgrades.%s: 필수 필드 '%s' 누락" % [tid, k])
				# 비용이 안 늘어나는 강화 = 무한 저가 구매(설계 붕괴) → 경고가 아니라 빌드 차단.
				if float(tr.get("cost_growth", 1.0)) <= 1.0:
					errors.append("upgrades.%s: cost_growth<=1 → 비용이 안 늘어남" % tid)
				if float(tr.get("per_level", 0.0)) < 0.0:
					warns.append("upgrades.%s: per_level<0 → 강화할수록 약해짐" % tid)
			# order 와 tracks 키 일치
			for oid in data.get("order", []):
				if not tracks.has(oid):
					errors.append("upgrades.order: '%s' 가 tracks 에 없음" % oid)
		"balance":
			for sec in ["enemy_hp", "gold"]:
				var g := float((data.get(sec, {}) as Dictionary).get("growth", 1.0))
				# 스케일이 평평하면 무한 스테이지 진행이 무의미 → 경고가 아니라 빌드 차단.
				if g <= 1.0:
					errors.append("balance.%s.growth<=1 → 스테이지 스케일이 평평함" % sec)
		"achievements":
			var cat: Dictionary = data.get("catalog", {})
			if cat.is_empty():
				errors.append("achievements.catalog: 비어있음")
			for aid in cat:
				var a: Dictionary = cat[aid]
				if a.has("stat") and not (a.get("threshold") is int):
					errors.append("achievements.%s: stat형인데 threshold 가 정수 아님" % aid)
		"enemies":
			var v: Variant = data.get("variants")
			if not (v is Array) or (v as Array).is_empty():
				errors.append("enemies.variants: 비어있거나 배열이 아님")
		"relics":
			var rgrades: Dictionary = data.get("grades", {})
			if rgrades.is_empty():
				errors.append("relics.grades empty")
			var rcat: Dictionary = data.get("catalog", {})
			if rcat.is_empty():
				errors.append("relics.catalog empty")
			for rid in rcat:
				if not (rcat[rid] is Dictionary) or not (rcat[rid] as Dictionary).has("kind"):
					errors.append("relics.%s: kind missing" % rid)
			if int(data.get("slots", 0)) <= 0:
				errors.append("relics.slots must be >= 1")
			# grade_order ↔ grades 정합 게이트 — 등급 인덱스(가루 환산·업그레이드 판정)가 grade_ids() 기준이라
			# 둘이 어긋나면 영속 세이브 경제 분기가 갈라짐 → 런타임 무음 분기 대신 빌드 에러로 차단.
			for oid in data.get("grade_order", []):
				if not rgrades.has(oid):
					errors.append("relics.grade_order: '%s' not in grades" % oid)
			for gid in rgrades:
				if not (data.get("grade_order", []) as Array).has(gid):
					errors.append("relics.grades: '%s' not in grade_order" % gid)
				# 무료 확정 소환(사전 설정) 가드레일 — effects 는 catalog 키, grades 는 grades 키, 길이 일치.
			var raw_fp: Variant = data.get("free_pull")
			if raw_fp is Dictionary:
				var fp: Dictionary = raw_fp
				var fe_raw: Variant = fp.get("effects")
				var fg_raw: Variant = fp.get("grades")
				if (fe_raw != null and not (fe_raw is Array)) or (fg_raw != null and not (fg_raw is Array)):
					errors.append("relics.free_pull: effects/grades 는 인라인 리스트여야 함(예: [r_dist_low])")
				else:
					var fe: Array = fe_raw if fe_raw is Array else []
					var fg: Array = fg_raw if fg_raw is Array else []
					if fe.size() != fg.size():
						errors.append("relics.free_pull: effects(%d) 와 grades(%d) 길이 불일치" % [fe.size(), fg.size()])
					for e in fe:
						if not rcat.has(e):
							errors.append("relics.free_pull.effects: '%s' 가 catalog 에 없음" % e)
					for fgr in fg:
						if not rgrades.has(fgr):
							errors.append("relics.free_pull.grades: '%s' 가 grades 에 없음" % fgr)
			elif raw_fp != null:
				errors.append("relics.free_pull: 맵이어야 함(effects/grades)")
			# 가루 구매(상점 재화) 가드레일 — amounts/grades 인라인 리스트·길이 일치·양수.
			var raw_ds: Variant = data.get("dust_shop")
			if raw_ds is Dictionary:
				var da_raw: Variant = (raw_ds as Dictionary).get("amounts")
				var dc_raw: Variant = (raw_ds as Dictionary).get("costs")
				if (da_raw != null and not (da_raw is Array)) or (dc_raw != null and not (dc_raw is Array)):
					errors.append("relics.dust_shop: amounts/costs 는 인라인 리스트여야 함")
				else:
					var da: Array = da_raw if da_raw is Array else []
					var dc: Array = dc_raw if dc_raw is Array else []
					if da.size() != dc.size():
						errors.append("relics.dust_shop: amounts(%d) 와 costs(%d) 길이 불일치" % [da.size(), dc.size()])
					for v in da:
						if float(v) <= 0.0:
							errors.append("relics.dust_shop.amounts: 양수여야 함 (%s)" % str(v))
					for v in dc:
						if float(v) <= 0.0:
							errors.append("relics.dust_shop.costs: 양수여야 함 (%s)" % str(v))
			elif raw_ds != null:
				errors.append("relics.dust_shop: 맵이어야 함(amounts/costs)")
		"equipment":
			# 등급(공용) + 풀별 카탈로그. 각 항목 grade가 grades에 있는지.
			var grades: Dictionary = data.get("grades", {})
			if grades.is_empty():
				errors.append("equipment.grades: 비어있음")
			var pools: Dictionary = data.get("pools", {})
			if pools.is_empty():
				errors.append("equipment.pools: 비어있음")
			for pid in pools:
				var p: Dictionary = pools[pid]
				var cat: Dictionary = p.get("catalog", {})
				if cat.is_empty():
					errors.append("equipment.pools.%s.catalog: 비어있음" % pid)
				if not p.has("stat"):
					warns.append("equipment.pools.%s: stat 누락(곱 적용 대상 미지정)" % pid)
				for eid in cat:
					var g := str((cat[eid] as Dictionary).get("grade", ""))
					if g == "" or not grades.has(g):
						warns.append("equipment.pools.%s.%s: grade '%s' 가 grades에 없음" % [pid, eid, g])
			for oid in data.get("grade_order", []):
				if not grades.has(oid):
					warns.append("equipment.grade_order: '%s' 가 grades에 없음" % oid)
			for oid2 in data.get("pool_order", []):
				if not pools.has(oid2):
					warns.append("equipment.pool_order: '%s' 가 pools에 없음" % oid2)
		"dungeon":
			# 던전 "시련의 탑" — 층 맵(floors). 각 층 = 보스 1체 + 룰 + 첫 돌파 보상.
			# stage_equiv>0, hp_mult>0, 룰 범위 검증, 보상 통화·금액 검증. 정렬=파일 순서.
			var floors: Dictionary = data.get("floors", {}) if data.get("floors") is Dictionary else {}
			if floors.is_empty():
				errors.append("dungeon.floors: 비어있음")
			for fid in floors:
				var fl: Dictionary = floors[fid] if floors[fid] is Dictionary else {}
				if fl.is_empty():
					errors.append("dungeon.%s: 맵이 아님/비어있음 — 들여쓰기 확인" % fid)
					continue
				if int(fl.get("stage_equiv", 0)) <= 0:
					errors.append("dungeon.%s: stage_equiv<=0 (메인 환산 난이도 필수)" % fid)
				if fl.has("hp_mult") and float(fl.get("hp_mult", 0.0)) <= 0.0:
					errors.append("dungeon.%s: hp_mult<=0" % fid)
				# 룰 범위(있을 때만): hand_gate 1~9 / time_limit>0 / pc_atk_down 0~1.
				if fl.has("hand_gate"):
					var hg := int(fl.get("hand_gate", 0))
					if hg < 1 or hg > 9:
						errors.append("dungeon.%s: hand_gate 는 1~9 (실제 %d)" % [fid, hg])
				if fl.has("time_limit") and float(fl.get("time_limit", 0.0)) <= 0.0:
					errors.append("dungeon.%s: time_limit<=0 (제거하려면 키 삭제)" % fid)
				if fl.has("pc_atk_down"):
					var pd := float(fl.get("pc_atk_down", 0.0))
					if pd <= 0.0 or pd >= 1.0:
						errors.append("dungeon.%s: pc_atk_down 은 0 초과 1 미만 (실제 %s)" % [fid, str(pd)])
				# 보상(첫 돌파): dia/dust 음수 금지(0 허용 = 미지급). 둘 다 없으면 무보상 경고.
				for cur in ["dia", "dust"]:
					if fl.has(cur) and float(fl.get(cur, 0.0)) < 0.0:
						errors.append("dungeon.%s: 보상 '%s' 음수" % [fid, cur])
				if float(fl.get("dia", 0.0)) <= 0.0 and float(fl.get("dust", 0.0)) <= 0.0:
					warns.append("dungeon.%s: 첫 돌파 보상 없음(dia·dust 둘 다 0)" % fid)
