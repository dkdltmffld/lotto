extends Node

# 개발용 치트 컨트롤러 (god object 티어2 분리, 2026-06-11) — 씬 소유 Node(autoload 아님, 메모리 결정).
# game.gd 가 치트 활성(CHEAT_ENABLED + 디버그 빌드)일 때만 생성:
#   좌상단 "치트" 버튼 + 치트 패널(UIManager 오버레이) 빌드 + 패널 시그널 → 치트 동작 배선.
# dev 전용(릴리즈 export 에선 생성 자체가 안 됨)이라 game 내부 멤버/메서드 직접 접근을 허용한다(blast radius 작음).
# ⚠️ game 은 의도적으로 비타입 — Control 로 타입하면 game.gd 전용 멤버 접근이 분석기 에러.
#    (cheat_controller ← game 단방향 preload — game.gd 를 preload 하지 않아 순환 없음.)

const CheatPanelScript = preload("res://scripts/cheat_panel.gd")
const RelicsScript = preload("res://scripts/relics.gd")

var game  # game.gd(Control) back-ref — _init 주입
var _panel: Control = null


func _init(game_node) -> void:
	game = game_node


func _ready() -> void:
	# 좌상단 "치트" 버튼 — game(Control)에 부착(컨트롤러는 Node 라 직접 그리지 않음).
	var b := Button.new()
	b.text = "치트"
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.offset_left = 8
	b.offset_top = 82  # 다이아 라벨(56~78) 아래로
	b.offset_right = 72
	b.offset_bottom = 108
	game.add_child(b)
	# 치트 패널 — UIManager 오버레이로 등록(버튼보다 뒤에 부착 → 패널이 버튼 위에 그려짐).
	_panel = UIManager.register_overlay("cheat", CheatPanelScript.new(), game)
	b.pressed.connect(func() -> void: UIManager.open_overlay("cheat"))
	_panel.add_gold.connect(_add_gold)
	_panel.add_dia.connect(_add_dia)
	_panel.boost_upgrades.connect(_boost_upgrades)
	_panel.goto_stage_delta.connect(_stage_delta)
	_panel.jump_to_boss.connect(_jump_boss)
	_panel.reset_stage.connect(_reset)
	_panel.heal.connect(_heal)
	_panel.wipe_save.connect(_wipe)
	_panel.set_number_dist.connect(_number_dist)
	_panel.set_auto_fast.connect(_set_auto_fast)
	_panel.set_pose_attack.connect(_set_pose_attack)
	_panel.add_dust.connect(_add_dust)
	_panel.grant_relic.connect(_grant_relic)
	_panel.clear_relics.connect(_clear_relics)
	# (closed → 숨김은 register_overlay 가 배선)


func _commit(refresh_upgrade_panel: bool = false) -> void:
	# 치트 공통 마무리: 즉시 저장 + HUD 갱신 (+ 강화 패널 열려 있으면 비용/구매가능 갱신).
	BackendService.flush()
	game._refresh_hud()
	if refresh_upgrade_panel:
		var up: Control = UIManager.get_panel("upgrade")
		if up != null and up.visible:
			up.refresh()


func _add_gold(amount: float) -> void:
	# 치트: 골드 즉시 지급(+저장).
	BackendService.add_gold(amount)
	_commit(true)


func _add_dia(amount: float) -> void:
	# 치트: 다이아 즉시 지급(+저장). 장비 뽑기 테스트용.
	BackendService.add_dia(amount)
	_commit()


func _boost_upgrades(levels: int) -> void:
	# 치트: 모든 강화 트랙을 levels만큼 올림(골드 차감 없음). 상한 트랙은 max_level로 clamp.
	for id in Upgrades.all_ids():
		var ml: int = Upgrades.max_level(id)
		var lv: int = Upgrades.get_level(id) + levels
		if ml >= 0:
			lv = min(lv, ml)
		BackendService.set_value("upg_" + id, lv)
	BackendService.flush()
	# 즉시 반영 (구매 핸들러와 동일)
	game._apply_upgrade_stats(true)
	game._refresh_hud()
	var up: Control = UIManager.get_panel("upgrade")
	if up != null and up.visible:
		up.refresh()


func _stage_delta(d: int) -> void:
	# 치트: 현재 스테이지 ±d 이동.
	_goto_stage(game.stage + d)


func _jump_boss() -> void:
	# 치트: 다음 보스 스테이지(다음 10단위)로 점프.
	_goto_stage((game.stage / 10 + 1) * 10)


func _reset() -> void:
	# 치트: 스테이지를 1로.
	_goto_stage(1)


func _goto_stage(s: int) -> void:
	# 치트 공용: 지정 스테이지로 즉시 이동(현재 적·이펙트 정리 후 재스폰).
	if game._player_dying:
		return
	game.stage = max(1, s)
	game.mobs_killed_in_stage = 0
	game.in_boss = false
	BackendService.set_stage(game.stage)
	BackendService.flush()
	game._clear_wave()  # 웨이브 전체(앞+대기열) 제거
	game._clear_arena_effects()
	game.player.set_hp_visible(false)
	game._refresh_hud()
	game._enter_run()
	game._spawn_next()


func _number_dist(spec: Dictionary) -> void:
	# 치트: 스크래치 숫자 분포 변경 + 현재 카드 즉시 재발행(is_locked 유지).
	match String(spec.get("type", "")):
		"range":
			game.scratch_card.set_number_range(int(spec.get("min", 1)), int(spec.get("max", 9)))
		"weights":
			game.scratch_card.set_number_weights(spec.get("weights", {}))
		"pool":
			game.scratch_card.set_number_pool(spec.get("values", []))
	game.scratch_card.new_card()  # 즉시 반영 (reset_card와 달리 잠금 상태는 유지)


func _heal() -> void:
	# 치트: PC HP 풀 회복(보스전 테스트용).
	game._restore_full_hp()


func _set_auto_fast(on: bool) -> void:
	# 치트: 자동긁기 속도를 8.0(테스트용 빠른 속도)으로 강제(ON) / 강화값 복귀(OFF).
	# ⚠️ 정식 강화 트랙은 안 건드림 — 자동이 수동보다 빨라지면 안 되므로 빠른 자동은 치트 전용.
	game._cheat_auto_rate = 8.0 if on else 0.0
	game.refresh_auto_rate_live()  # 교전 idle 중이면 즉시 반영(다음 _enter_idle 안 기다리고)


func _set_pose_attack(on: bool) -> void:
	# 치트[프로토타입]: PC 공격을 포즈투포즈(3포즈+홀드+슬래시) 모드로 토글 — 현재 방식과 비교용(2026-06-19).
	game.player.pose_mode = on


func _add_dust(amount: float) -> void:
	# 치트: 유물 가루 지급.
	BackendService.add_dust(amount)
	_commit()


func _grant_relic(effect: String, grade: String) -> void:
	# 치트: 유물 지급 + 빈 슬롯 자동 장착(테스트). effect=="" 면 랜덤 뽑기.
	var eff: String = effect
	var grd: String = grade
	if eff == "":
		var r: Dictionary = RelicsScript.roll()
		if r.is_empty():
			return
		eff = str(r.get("effect", ""))
		grd = str(r.get("grade", ""))
	var res: Dictionary = BackendService.acquire_relic(eff, grd)  # 중복이면 자동 가루
	var uid: String = str(res.get("uid", ""))
	if uid != "":
		BackendService.equip_relic(uid)  # 슬롯 가득이면 보유만(장착 안 됨)
	BackendService.flush()
	game._on_relic_changed()  # ①분포·④와일드 즉시 반영 + 카드 재발행 + HUD (패널 핸들러와 동일 본문)


func _clear_relics() -> void:
	# 치트: 보유/장착 유물 전부 비움(분포 균등 복귀).
	BackendService.set_value("relics", [])
	BackendService.set_value("relic_slots", [])
	BackendService.flush()
	game._on_relic_changed()


func _wipe() -> void:
	# 치트: 세이브 초기화 — 골드·강화 레벨·스테이지를 처음 상태로(계정/로그인은 유지).
	BackendService.set_value("gold", 0.0)
	BackendService.set_value("dia", 0.0)
	BackendService.set_value("dust", 0.0)
	BackendService.set_value("equips", {"weapon": [], "armor": []})
	BackendService.set_value("equipped", {"weapon": "", "armor": ""})
	BackendService.set_value("equip_seq", 0)
	BackendService.set_value("relics", [])
	BackendService.set_value("relic_slots", [])
	BackendService.set_value("relic_seq", 0)
	BackendService.set_value("relic_free_used", 0)  # 무료 확정 소환 사용 횟수도 리셋(안 하면 유물0인데 무료 소환만 사라짐)
	BackendService.set_value("dust_boss_max", 0)    # 보스 가루 첫클리어 가드도 리셋(재파밍 방지값 — 와이프 시 처음 상태로)
	BackendService.set_value("dungeon_max_cleared", 0)  # 던전 진행도(최고 클리어 층)도 리셋
	BackendService.set_value("dungeon", {"tickets": 0, "date": "", "auto": true, "auto_init": true})  # 던전 입장권/리셋날짜/자동등반(기본 켜짐) 리셋
	for id in Upgrades.all_ids():
		BackendService.set_value("upg_" + id, 0)
	# 퀘스트/통계 초기화 — 안 하면 진행도·수령 도장이 남아 퀘스트가 리셋 안 됨.
	BackendService.set_value("stats", {})  # 진행도 통계(퀘스트·업적: total_kills/upgrades_bought_*/boss_kills 등)
	BackendService.set_value("quests_daily", {"date": "", "base": {}, "claimed": {}})  # 일일 퀘스트(다음 롤오버 체크에 재롤)
	BackendService.set_value("quests_main_claimed", {})  # 메인 퀘스트 수령 도장
	BackendService.set_value("mail_claimed", {})  # 우편 수령 도장(초기화 = 처음 상태)
	BackendService.set_stage(1)
	BackendService.flush()
	game._apply_upgrade_stats(false)  # 세이브 초기화: HP는 _goto_stage 스폰에서 처리(여기선 미변경)
	_goto_stage(1)
