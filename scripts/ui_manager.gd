extends Node

# UI 매니저 (autoload "UIManager") — 2026-06-10 싱글톤 매니저 도입 1단계 (UI 우선).
# 내비 밴드 패널(강화/장비/유물/상점)의 등록·부착·상호배타 오픈을 소유한다.
# (구 game.gd `_add_band_panel`/`_open_nav_panel`/`_hide_nav_panels` 가 여기로 이동.)
#
# ⚠️ autoload 는 씬 전환을 넘어 살아남지만 패널은 씬(main) 소속 → **register/unregister 패턴**:
#    game 이 _ready 에서 register_*() 하고, 패널의 tree_exiting 에서 자동 해제된다.
#    매니저가 씬 노드를 영구 보유하면 씬 전환 후 dangling — 그래서 등록제가 필수.
# 관리 경계: **열고 닫는 UI 표면**(밴드 패널 + 전체화면 오버레이)만 소유한다.
#   상주 레이아웃(내비 도크·상단 바·스테이지 배너·게이지)과 게임플레이 연출(컷인·튜토리얼 배너)은
#   씬(game.gd) 소유 — HUD 빌더 분리는 별도 작업(god object 티어3, 노드 주입 설계 필요).
# 토스트/알림은 NotificationManager(autoload, 2026-06-11 도입)가 소유한다.

var _panels: Dictionary = {}    # id -> Control (밴드 패널 — 같은 밴드 공유, 상호배타 오픈)
var _overlays: Dictionary = {}  # id -> Control (전체화면 오버레이 — 설정/치트, 독립 표시)


func register_band_panel(id: String, panel: Control, host: Control, top_offset: float) -> Control:
	# 밴드 패널 공통 부착(숨김 생성 + 내비 바 바로 아래 ~ 화면 바닥 밴드 + 닫기 시 숨김) + 레지스트리 등록.
	# 전투/내비를 가리지 않고 스크래치 영역만 덮는다. 패널별 추가 동작은 Events 신호로(직접 connect 불필요).
	panel.visible = false
	host.add_child(panel)
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_top = top_offset
	panel.offset_bottom = 0.0
	panel.closed.connect(func() -> void: panel.visible = false)
	_panels[id] = panel
	panel.tree_exiting.connect(func() -> void: _panels.erase(id))  # 씬 전환 시 자동 해제(dangling 방지)
	return panel


func open(id: String) -> void:
	# 탭 → 해당 패널 열기. 같은 밴드를 공유하므로 나머지는 닫는다(상호배타).
	var panel: Control = _panels.get(id, null)
	if panel == null:
		return
	Audio.play_sfx("button")
	hide_all()
	panel.open()


func hide_all() -> void:
	for id in _panels:
		_panels[id].visible = false


func get_panel(id: String) -> Control:
	return _panels.get(id, null)


# ---------- 전체화면 오버레이 (설정/치트 — 게임 진행 위에 독립적으로 겹침, 밴드 패널과 상호배타 아님) ----------

func register_overlay(id: String, panel: Control, host: Control) -> Control:
	# 숨김 부착 + 닫기 시 숨김 + 레지스트리 등록. 패널 자체가 anchor fill 스캐폴드를 가진다(dim+center).
	panel.visible = false
	host.add_child(panel)
	panel.closed.connect(func() -> void: panel.visible = false)
	_overlays[id] = panel
	panel.tree_exiting.connect(func() -> void: _overlays.erase(id))  # 씬 전환 시 자동 해제
	return panel


func open_overlay(id: String) -> void:
	var panel: Control = _overlays.get(id, null)
	if panel == null:
		return
	Audio.play_sfx("button")
	panel.open()
