extends Control

# 방치형 메인 오케스트레이터.
# 코어 루프: 복권 자동/수동 긁기 → 9칸 → 공격(캐릭터 공격력 × 복권 배율 × 족보배율)
#   → 적 처치 → 골드 → 강화 → 더 센 적(스테이지). 보스(10단위)만 PC 공격, 사망 시 블록 첫 스테이지로.
# 설계: docs/design/게임 컨셉 정리본.md, 전투 시스템 정리본.md

const EnemyScene: PackedScene = preload("res://scenes/enemy.tscn")
const NavDockScript = preload("res://scripts/nav_dock.gd")
const UpgradePanelScript = preload("res://scripts/upgrade_panel.gd")
const SettingsPanelScript = preload("res://scripts/settings_panel.gd")
const CheatControllerScript = preload("res://scripts/cheat_controller.gd")  # 개발용 치트(버튼+패널+동작) — god object 분리
const TutorialOverlayScript = preload("res://scripts/tutorial_overlay.gd")
const CutInScript = preload("res://scripts/cut_in.gd")
const ShopPanelScript = preload("res://scripts/shop_panel.gd")  # 상점(소환 등) 오버레이 — 장비 뽑기 이전
const EquipmentPanelScript = preload("res://scripts/equipment_panel.gd")  # 보유 장비 인벤토리 오버레이
const RelicsScript = preload("res://scripts/relics.gd")  # 유물(족보 커스텀) 데이터·효과 강도 (class_name 직접참조 회피 위해 preload)
const RelicEffectsScript = preload("res://scripts/relic_effects.gd")  # 유물 효과 계산(분포/보정/와일드/확장) — god object 완화 분리
const SceneNav = preload("res://scripts/scene_nav.gd")  # 씬 전환 공용(login과 중복 제거)
const RelicPanelScript = preload("res://scripts/relic_panel.gd")  # 유물 인벤토리·뽑기 오버레이
const MailboxScript = preload("res://scripts/mailbox.gd")  # 우편함 카탈로그+순수 로직(class_name Mailbox 직접참조 회피)
const MailboxPanelScript = preload("res://scripts/mailbox_panel.gd")  # 우편함 오버레이
const RedDotScript = preload("res://scripts/red_dot.gd")  # 공용 빨간 점 배지(우편함·리텐션 공유)
const QuestPanelScript = preload("res://scripts/quest_panel.gd")  # 일일 퀘스트 오버레이
const QuestTrackerScript = preload("res://scripts/quest_tracker.gd")  # 메인 퀘스트 HUD 트래커(우측 하단)
const QuestsScript = preload("res://scripts/quests.gd")  # 퀘스트 카탈로그+순수 로직(class_name Quests 직접참조 회피)
const DayUtilScript = preload("res://scripts/day_util.gd")  # 일일 리셋 날짜(class_name DayUtil)
const DungeonDataScript = preload("res://scripts/dungeon_data.gd")  # 던전 층 데이터(class_name DungeonData 직접참조 회피)
const DungeonPanelScript = preload("res://scripts/dungeon_panel.gd")  # 던전 진입 패널(내비 "던전" 탭)

# 첫 시작(저장 데이터 없음) 스크립트형 튜토리얼. 상단 배너 + 게임 액션으로 진행.
# 1단계: 긁기 체험(적 고HP라 한 방에 안 죽음, 자동긁기·적공격 OFF) → 9칸 완성 시
# 2단계: 강제 잭팟 카드 + 완성 시 강제 처치 → 칭찬 →
# 3단계: 강화 유도(강화 버튼 강조) → 강화 버튼 누르면 종료.
enum Tut { OFF, SCRATCH, JACKPOT, UPGRADE }

const TUT_MSG_1 := "화면 하단 복권을 긁어 적을 공격하세요!\n같은 숫자가 많을수록 공격이 강력해집니다."
const TUT_MSG_2 := "잘 하셨습니다! \n한번 더 적을 공격해보세요."
const TUT_PRAISE := "대단합니다! 정말 높은 숫자예요!"
const TUT_MSG_3 := "강화를 통해 더욱 강해지세요!"
const TUT_PRAISE_DURATION := 1.8  # 칭찬 문구 표시 시간(초) → 3단계로
const TUT_JACKPOT_MULT := 729     # 9칸 모두 9 (count²×value = 81×9). 1단계 적 HP 산정용

enum PcState { IDLE, RUN }  # PC 진행 상태: IDLE(전투 정지·교전) / RUN(다음 적으로 이동)
var pc_state: PcState = PcState.IDLE

# 게임 모드: MAIN(무한 방치 스테이지) / DUNGEON("시련의 탑" 능동 보스 도전 — 같은 아레나, 모드 분기).
# 던전 = 메인과 별개 진행(dungeon_max_cleared), 같은 스크래치/족보 전투를 룰만 바꿔 재활용.
# 기획서: docs/design/던전 시스템 정리본.md
enum Mode { MAIN, DUNGEON }
var _mode: Mode = Mode.MAIN
var _dungeon_floor: int = 0           # 현재 도전 중인 던전 층(1-based, _mode==DUNGEON일 때만 유효)
var _dungeon_time_left: float = 0.0   # time_limit 룰 남은 시간(초). 0 = 제한 없음/비활성
var _dungeon_hand_gate: int = 0       # hand_gate 룰: 이 족보 count 이상 스킬만 타격(자동공격도 봉인). 0 = 없음
var _dungeon_pc_atk_mult: float = 1.0 # pc_atk_down 룰 반영 자동공격 배수(1.0 = 없음). 메인 모드에선 항상 1.0
var _travel_overlay: CanvasLayer = null  # 던전 이동 연출(짧은 페이드 + "이동 중" 로딩) 전체화면 오버레이
var _travel_rect: ColorRect = null
var _travel_label: Label = null
var _dungeon_enter_msec: int = 0          # 던전 입장 시각(소요시간 계산용, Time.get_ticks_msec)
var _dungeon_result_overlay: Control = null  # 던전 클리어/실패 결과 모달(있으면)

var stage: int = 1                 # 현재 스테이지(무한). 10·20·30…이 보스
var mobs_killed_in_stage: int = 0  # 현재 일반 스테이지에서 처치한 잡몹 수 (MOBS_PER_STAGE 도달 시 다음 스테이지)
var in_boss: bool = false          # 현재 적이 보스인지
var current_enemy: Enemy = null    # 현재 교전 중인 적(웨이브의 맨 앞). 없으면 null
var _wave_queue: Array = []         # 뒤에서 대기 중인 같은 웨이브 적들 (앞이 죽으면 PC가 전진)

var player_hp: float = 100.0       # 보스전 PC 체력 (일반 스테이지는 위협 없음)
var player_max_hp: float = 100.0   # = Upgrades.value("hp"). 보스 진입 시 풀 충전
var _player_dying: bool = false    # 사망 연출~블록 재시작 사이. 이 동안 입력/스폰 무시

var _pending_attack_damage: int = 0  # 스크래치 스킬 데미지. attack 모션 종료 시점에 적용
var _skill_pending: bool = false     # 스크래치 스킬 발동 중(attack 모션 종료 = 버스트 적용). 자동공격 모션과 구분
var _skill_hand_count: int = 0       # 발동 중 스킬의 족보 count(연출 강도용 — 잭팟/고족보일수록 화면 흔들림 ↑)
var _auto_pending: bool = false      # 자동공격 발동 중(attack 모션 종료 시 데미지 적용 — 스킬과 동일, 한방 처치 시 스윙 안 끊기게)
var _auto_pending_damage: int = 0    # 모션 종료 시 적용할 자동공격 데미지
var _aoe_active: bool = false        # AoE(무리 전체) 스킬 처리 중 — 개별 처치(_on_enemy_died)는 골드·연출만, 대형/스테이지 정리는 _resolve_wave_after_aoe가 일괄
var _auto_atk_accum: float = 0.0     # 일반 공격(자동) 타이머 누적. 공격속도 주기마다 발동

@onready var arena: Control = $Arena
@onready var player: PlayerController = $Arena/Player
@onready var parallax_bg: ParallaxBackground = $ParallaxBackground
@onready var bg_layer: ParallaxLayer = $ParallaxBackground/ParallaxLayer
@onready var bg_sprite: Sprite2D = $ParallaxBackground/ParallaxLayer/BackgroundSprite
@onready var scratch_card_area: Control = $ScratchCardArea
@onready var ticket_bg: Sprite2D = $TicketBackground
@onready var scratch_card: ScratchCard = $ScratchCardArea/ScratchCard
@onready var gold_label: Label = $TopHUD/ScoreLabel
@onready var stage_label: Label = $TopHUD/StageLabel
@onready var account_label: Label = $TopHUD/AccountLabel
@onready var settings_button: Button = $TopHUD/SettingsButton

var _nav: Control = null          # 하단 내비 도크(코드 빌드). 강화 등 메뉴 진입점.
var _upgrade_panel: Control = null
var _settings_panel: Control = null
var _shop_panel: Control = null     # 상점(소환) 오버레이 — 내비 "상점" 탭
var _equipment_panel: Control = null  # 보유 장비 인벤토리 — 내비 "장비" 탭
var _relic_panel: Control = null      # 유물 인벤토리·뽑기 — 내비 "유물" 탭
var _dungeon_panel: Control = null    # 던전("시련의 탑") 진입 패널 — 내비 "던전" 탭
var _cheat_auto_rate: float = 0.0    # 치트: >0이면 자동긁기 속도를 이 값으로 강제(_enter_idle 우선). 0=강화값 사용. (cheat_controller가 설정)
var _cut_in: Control = null         # 고족보 컷인 오버레이(전체화면, 코드 빌드)
var _cutin_active: bool = false     # 컷인 시퀀스(공개 대기~멈춤~컷인) 진행 중 — 자동공격 억제
var _skill_resolving: bool = false  # 스킬 다타격(연타) 시퀀스 진행 중(await 기반) — 자동공격·재진입 억제. 안전장치로 _enter_idle/run에서 해제
var _bar_mask: ColorRect = null     # 스테이지 진행 바의 어두운 마스크(진행도만큼 왼쪽부터 걷힘 → 초록 노출)
var _show_full_gauge: bool = false  # 스테이지 클리어~다음 몹 조우 사이엔 게이지 100% 유지(연출)
var _hp_mask: ColorRect = null      # 좌상단 HUD PC 체력바의 마스크(HP 비율만큼 초록 노출)
var _boss_badge: Label = null       # 보스 스테이지 표시 배지
var _dia_label: Label = null        # 좌상단 다이아 재화 표시(골드 아래)
var _mailbox_panel: Control = null  # 우편함 오버레이(상단 HUD 버튼)
var _mail_button: Button = null     # 우편함 버튼(튜토리얼 중 비활성화용)
var _mail_dot: Control = null       # 우편함 버튼의 빨간 점(RedDot — 받을 보상 있음. set_active는 동적 호출)
var _quest_panel: Control = null    # 퀘스트 오버레이(상단 HUD 버튼)
var _quest_button: Button = null    # 퀘스트 버튼(튜토리얼 중 비활성화용)
var _quest_dot: Control = null      # 퀘스트 버튼의 빨간 점(받을 일일 퀘스트 있음)
var _quest_tracker: Control = null  # 메인 퀘스트 HUD 트래커(우측 하단, 다음 1개 상시)
var _quest_main_dot: Control = null  # 트래커 우상단 빨간 점(메인 퀘 완료=받기 가능 시. set_active 동적 호출)
var _quest_day_accum: float = 0.0   # 일일 퀘스트 자정 롤오버 저빈도 체크 누적(_process, Codex #15 P1)
const QUEST_DAY_CHECK_INTERVAL := 30.0  # 초 — 앱 켜둔 채 날짜 변경 감지 주기
var _tut: Tut = Tut.OFF          # 튜토리얼 단계 (Tut.OFF면 비튜토리얼)
var _tut_banner: Control = null  # 상단 안내 배너
var _tut_blink: Tween = null     # 3단계 강화 버튼 강조 트윈

const ENEMY_FLOATER_OFFSET := Vector2(15, -10)
const PLAYER_FLOATER_OFFSET := Vector2(-12, -77)
# 적 몸통(x=25) 기준 이펙트 앵커 오프셋 — 자동공격 임팩트 / 스킬 / 사망 폭발.
const ENEMY_IMPACT_OFFSET := Vector2(25, 60)
const ENEMY_SKILL_OFFSET := Vector2(25, 45)
const ENEMY_EXPLOSION_OFFSET := Vector2(25, 39)

# 족보 count 임계치 — 잭팟(보너스 골드·강한 흔들림) / 고족보(업적·중간 흔들림).
const JACKPOT_COUNT := 9
const HIGH_HAND_COUNT := 4
# 이 족보 count 이상이면 스킬이 **웨이브 전체 타격(AoE)** — 무리 전부에게 같은 데미지. 현재=잭팟(9)만.
# ⚠️ 추후 확장: 이 값만 낮추면 더 낮은 족보부터 AoE 발동(예: 5 = 컷인 족보부터).
const AOE_MIN_COUNT := 9
# 고족보 컷인(일러스트 연출) 발동 최소 count. 방치라 너무 자주 뜨면 피로 → 높게 잡고 튜닝.
# ⚠️ 현재는 max-count 신호 기준(족보 분류기 도입 후 족보 종류로 리매핑). 더미 연출.
const CUTIN_MIN_COUNT := 5
# 컷인 전 스크래치 완전 공개 대기(초). 셀 완료=70%+페이드 연출이 끝나고 9칸 숫자가 다 보인 뒤 컷인. (튜닝 노브)
const CUTIN_REVEAL_DELAY := 0.4
# 개발용: true면 컷인을 주기적으로 재생(연출 확인용 — MCP 클릭 불가 보완). 정상/배포 시 false.
const CUTIN_SELFTEST := false

const INTRO_IDLE_DURATION: float = 0.6
const POST_KILL_DELAY: float = 0.6     # (스테이지 내) 잡몹 처치 → run 재개
const SKILL_HIT_INTERVAL: float = 0.05 # 스킬 다타격(연타) 한 타 간격(초) — 다다다닥 템포. 타수 = 족보 count.
const STAGE_CLEAR_DELAY: float = 1.3   # 스테이지 클리어 → 다음 스테이지 이동까지(게이지 100% 보여줄 여유)
const DEATH_RESTART_DELAY: float = 0.8 # PC 사망 모션 후 블록 재시작까지

# 적 웨이브(여러 마리, 같은 종류) — 잡몹만. 보스/튜토리얼은 1마리. 앞에서부터 1마리씩 교전(나머지는 대기).
const WAVE_MIN: int = 2
const WAVE_MAX: int = 4
const WAVE_SPACING: float = 105.0    # 대형 내 적 간 가로 간격(STOP_X 기준 뒤로 누적) = 70 × 1.5. ⚠️ 빠른 이동감 묶음 — PlayerData.RUN_SPEED·EnemyData.SPAWN_OFFSET_FROM_RIGHT와 같은 배율 K로 함께 키워 호흡(run 시간) 불변. ⚠️ 클수록 뒤 적이 화면 밖에서 시작(전진하며 등장).

const DUNGEON_ENEMY_TINT: Color = Color(1.0, 0.32, 0.3)  # 던전 몬스터 빨강 틴트(보스처럼 색 덮어씌움 — 임시, 기존 몬스터 재활용)
# 던전 이동 연출(스테이지→던전 전환을 "이동"처럼) — 검은 화면 페이드 + 짧은 "이동 중" 로딩.
const TRAVEL_COVER_TIME: float = 0.35   # 화면 어두워지는 시간
const TRAVEL_HOLD_TIME: float = 0.55    # 검은 화면 "이동 중" 홀드(의미상 짧은 로딩)
const TRAVEL_REVEAL_TIME: float = 0.35  # 화면 밝아지는 시간
const DUST_COLOR: Color = Color(0.7, 0.95, 1.0)  # 유물 가루 표시색(상점/유물 패널과 통일)

const LOCKED_TINT: Color = Color(0.45, 0.45, 0.45, 1.0)
const ACTIVE_FLASH_TINT: Color = Color(1.5, 1.5, 0.8, 1.0)

# 재화 텍스트 색 — 골드=노란색, 다이아=하늘색 (항상 고정).
const GOLD_COLOR: Color = Color(1.0, 0.84, 0.25)
const DIA_COLOR: Color = Color(0.45, 0.8, 1.0)
# 재화 표시 포맷은 UISkin.fmt_currency 단일 출처 — _fmt 가 위임(HUD·패널 통일). 구 FMT_* 상수/_comma 제거.

# TEST: 보스 첫 공격에 PC 즉사 (보스 사망→블록 재시작 흐름 검증용). 검증 끝나면 false로.
const BOSS_ONESHOT_TEST: bool = false
# TEST: >0이면 저장값 대신 이 스테이지에서 시작 (보스전 즉시 진입용, 10=보스). 0이면 정상(저장값).
const START_STAGE_TEST: int = 0
# 개발용 치트(좌상단 "치트" 버튼+패널 — cheat_controller.gd). 배포 시 false로.
# + OS.is_debug_build() 이중 게이트: release export(배포 빌드)에선 true여도 자동 비활성.
#   (deploy_kplay.ps1 의 업로드 하드 차단과 이중 안전. 로컬 웹 테스트는 build_web.ps1 이 debug export라 치트 유지.)
const CHEAT_ENABLED: bool = true
# 개발용: true면 시작 시 상점 패널 자동 오픈(MCP 스크린샷 검증용 — 클릭 불가 보완). 검증 후 false.
const SHOP_DEBUG_OPEN: bool = false
# 개발용: true면 시작 시 유물 패널 자동 오픈 + 샘플 유물 지급(MCP 시각 검증용). 검증 후 false.
const RELIC_DEBUG_OPEN: bool = false

# 스크래치 칸에 들어갈 숫자 분포(집합/가중치). {} = 균등 1~9(기본).
#   예) {7:3.0, 8:2.0, 9:2.0} → 7·8·9가 더 자주(가중치). 특정 집합만은 set_number_pool 사용.
# 강화/복권 등급 연동 시 _apply_scratch_numbers()에서 이 분포를 구성한다.
const SCRATCH_NUMBER_WEIGHTS: Dictionary = {}


func _ready() -> void:
	randomize()
	# 게임 씬은 불투명. (로그인 화면이 frame_bg를 비추려고 켠 투명을 되돌림)
	get_tree().root.transparent_bg = false
	player.attack_motion_completed.connect(_on_player_attack_completed)
	scratch_card.card_completed.connect(_on_card_completed)
	settings_button.pressed.connect(_on_settings_pressed)
	UISkin.skin_button(settings_button, "settings", 3)  # #19 스킨
	settings_button.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	settings_button.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7))
	settings_button.add_theme_color_override("font_pressed_color", Color(1, 0.95, 0.7))
	# 골드 = 노란색 고정(+그림자로 가독성)
	gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	Effects.apply_label_shadow(gold_label, 0.7, 1)
	# 골드 뒤 검은 반투명 백판 제거 (그림자로 가독성 확보하므로 불필요)
	var score_bg := $TopHUD.get_node_or_null("ScoreBackground")
	if score_bg != null:
		score_bg.queue_free()
	BackendService.logged_out.connect(_return_to_login)
	BackendService.account_deleted.connect(_return_to_login)

	_refresh_account_label()
	_setup_background()
	_setup_scratch_card_layout()
	_build_scratch_bg()  # 스크래치 영역 뒤 배경(#16) — 티켓/카드보다 뒤에 깔림
	_build_nav_dock()  # 패널보다 먼저 add → 패널 오버레이가 도크 위로 덮임
	_build_stage_banner()
	# _build_hp_bar()  # 상단 HUD 체력바 비활성(언제 쓸지 미정). 함수·머리위 바는 유지.
	_build_top_bar()  # 레퍼런스식 상단 바(#23): [왼쪽 비움] 닉네임(계정) · 골드/다이아 칩 · 설정(오른끝)
	_build_nav_panels()  # 강화/상점/장비/유물 — UIManager 등록 + Events 구독
	_build_quest_tracker()  # 메인 퀘스트 HUD 트래커(오버레이보다 먼저 add → 오버레이 dim 이 덮음)
	_build_settings_panel()
	_build_mailbox_panel()
	_build_quest_panel()
	if CHEAT_ENABLED and OS.is_debug_build():
		add_child(CheatControllerScript.new(self))  # 치트 버튼/패널/동작 일체 — cheat_controller.gd
	_cut_in = CutInScript.new()  # 고족보 컷인 오버레이 (z_index=200, 입력 통과). 마지막에 add.
	add_child(_cut_in)
	_build_travel_overlay()  # 던전 이동 연출(페이드+로딩) 오버레이
	if CUTIN_SELFTEST:
		_run_cutin_selftest()  # 개발용 연출 확인(await 루프 — 호출만 하고 _ready는 계속 진행)

	# 진행 상태 로드
	stage = BackendService.get_stage()
	if START_STAGE_TEST > 0:
		stage = START_STAGE_TEST  # TEST: 보스전 즉시 진입
	_restore_full_hp(false)  # 시각 동기화는 _spawn_next 가 수행
	player.set_hp_visible(false)
	# 우편함 claimed GC: 카탈로그에 없는 도장 정리(누적 완화, 안전 전제=id 재사용 금지). 변경 시에만 flush.
	if BackendService.gc_mail_claimed(MailboxScript.all_ids()):
		BackendService.flush()
	# 일일 퀘스트 롤오버(날짜 바뀌면 base 스냅샷·claimed 리셋). 변경 시에만 flush.
	if BackendService.roll_daily_quests_if_needed(DayUtilScript.today(), QuestsScript.daily_stat_keys()):
		BackendService.flush()
	# 던전 입장권 일일 리셋(자정 지나면 무료 N개로 충전).
	if BackendService.roll_dungeon_tickets_if_needed(DayUtilScript.today(), Balance.DUNGEON_DAILY_TICKETS):
		BackendService.flush()
	_settle_offline()
	_refresh_hud()

	# 첫 시작(저장 데이터 없음)이면 스크립트형 튜토리얼 시작.
	if BackendService.is_fresh_save:
		_start_tutorial()

	Audio.play_bgm("main")  # 배경음 시작 (로그인 클릭 이후 진입이라 웹 autoplay 정책 안전)

	if SHOP_DEBUG_OPEN:
		_shop_panel.open()  # 개발용 자동 오픈(검증). 평소 SHOP_DEBUG_OPEN=false.

	if RELIC_DEBUG_OPEN:
		# 개발용: 샘플 유물 지급(4개 장착 + 2개 보유) 후 유물 패널 자동 오픈. 평소 false.
		BackendService.add_dust(5000.0)
		var _seeds: Array = [["r_dist_low", "mythic"], ["r_boost_high", "legendary"], ["r_wild", "epic"], ["r_boost_low", "rare"]]
		for s in _seeds:
			BackendService.equip_relic(BackendService.add_relic(s[0], s[1]))
		BackendService.add_relic("r_expand_2pair", "legendary")  # 보유만(장착 버튼 확인)
		BackendService.add_relic("r_expand_full", "common")
		BackendService.flush()
		_apply_scratch_numbers()
		_relic_panel.open()

	# 시작: 잠깐 idle → run → 현재 스테이지 첫 적
	pc_state = PcState.IDLE
	_lock_card()
	await get_tree().create_timer(INTRO_IDLE_DURATION).timeout
	if is_inside_tree():
		_enter_run()
		_spawn_next()


func _process(delta: float) -> void:
	# run 시뮬레이션: PC 속도에 맞춰 적·배경이 좌로 흘러옴
	# ⚠️ 컷인(트리 pause·공개 대기) 중엔 전진 정지 — 전진이 컷인과 겹쳐 _enter_idle이 끼어들면 pause/펜딩 고착(프리징).
	if pc_state == PcState.RUN and not _cutin_active:
		parallax_bg.scroll_offset.x -= PlayerData.RUN_SPEED * BackgroundData.SCROLL_SPEED_RATIO * delta
		var step: float = PlayerData.RUN_SPEED * delta
		# 웨이브 전체(대기열 포함)가 대형을 유지하며 좌로 흘러온다.
		for q in _wave_queue:
			if is_instance_valid(q):
				q.position.x -= step
		if current_enemy != null and not current_enemy.is_dead:
			current_enemy.position.x -= step
			if current_enemy.position.x <= EnemyData.STOP_X:
				_snap_wave_positions()  # front=STOP_X, 대기열은 뒤로 정렬
				_on_enemy_reached_position()
		_auto_atk_accum = 0.0
	elif pc_state == PcState.IDLE and _tut == Tut.OFF and not _player_dying and not _cutin_active and not _skill_resolving \
			and current_enemy != null and not current_enemy.is_dead:
		# 교전 중: 일반 공격(자동)을 고정 주기(Balance.AUTO_ATK_SPEED, 초당 횟수)마다 발동. (스크래치 스킬과 독립)
		# 컷인 시퀀스(공개 대기~컷인) 중엔 억제 — PC를 idle로 유지해 컷인 후 깨끗한 스윙.
		_auto_atk_accum += delta
		var aps: float = Balance.AUTO_ATK_SPEED
		var interval: float = 1.0 / max(0.1, aps)
		if _auto_atk_accum >= interval:
			_auto_atk_accum = 0.0
			_auto_attack()
	else:
		_auto_atk_accum = 0.0

	# 던전 time_limit 룰 카운트다운 — 교전(IDLE·적 생존) 중에만 감소. 0 도달 = 실패(입구로).
	# ⚠️ 게임시간 기준: 컷인 pause(get_tree().paused) 중엔 game._process 자체가 안 돌아 자동 정지(공정).
	if _mode == Mode.DUNGEON and _dungeon_time_left > 0.0 and not _player_dying and not _cutin_active and not _skill_resolving \
			and pc_state == PcState.IDLE and current_enemy != null and not current_enemy.is_dead:
		# ⚠️ not _skill_resolving: 다타격 시퀀스(≤0.4s) 중엔 타이머 정지 — 그 await 창에 시간초과가 걸리면
		#    _dungeon_fail 이 _skill_multihit 코루틴을 어긋난 상태로 재개시켜 상태가 손상됨(자동공격 분기와 대칭).
		_dungeon_time_left = max(0.0, _dungeon_time_left - delta)
		_update_dungeon_hud()
		if _dungeon_time_left <= 0.0:
			_dungeon_fail("시간 초과")
			return

	# HP 자동 재생(초당 hp_regen) — 일반 스테이지 진행 중 깎인 HP를 메우는 생존 유지축.
	# 사망 연출·튜토리얼 중엔 안 함. HP가 가득이면 스킵(매 프레임 바 갱신 비용 회피).
	if not _player_dying and _tut == Tut.OFF and player_hp < player_max_hp:
		var regen: float = Upgrades.value("hp_regen")
		if regen > 0.0:
			player_hp = min(player_max_hp, player_hp + regen * delta)
			player.set_hp(player_hp)
			_update_hp_hud()

	# 일일 퀘스트 자정 롤오버 — 앱 켜둔 채 날짜가 바뀌면 패널 열기 전에도 갱신(기획 §5, Codex #15 P1).
	# 저빈도 체크(날짜 문자열 비교는 쌈). 날짜 바뀐 시점의 stat을 새 base로 → 자정~체크 사이(≤간격) 행동만 흡수.
	_quest_day_accum += delta
	if _quest_day_accum >= QUEST_DAY_CHECK_INTERVAL:
		_quest_day_accum = 0.0
		var today: String = DayUtilScript.today()
		var day_changed: bool = false
		if BackendService.roll_daily_quests_if_needed(today, QuestsScript.daily_stat_keys()):
			day_changed = true
		if BackendService.roll_dungeon_tickets_if_needed(today, Balance.DUNGEON_DAILY_TICKETS):
			day_changed = true  # 던전 입장권도 자정 충전
		if day_changed:
			BackendService.flush()
			_refresh_hud()


func _run_cutin_selftest() -> void:
	# 개발용: 컷인 freeze 시퀀스를 주기적으로 재생해 확인(MCP 클릭 보완). CUTIN_SELFTEST=true일 때만.
	while is_inside_tree():
		await get_tree().create_timer(2.0).timeout
		if _cut_in != null and not get_tree().paused:
			_skill_hand_count = 9
			await _play_cutin_then_attack()


# --------- 오프라인 정산 ---------

func _settle_offline() -> void:
	var elapsed: float = BackendService.consume_offline_seconds()
	if elapsed < 60.0:
		return
	var rate: float = Balance.offline_rate(stage)
	var cap: float = Upgrades.value("storage")
	var gain: float = min(rate * elapsed, cap)
	if gain <= 0.0:
		return
	_grant_gold(gain)
	BackendService.flush()
	Audio.play_sfx("reward")
	NotificationManager.reward("오프라인 보상\n+%s 골드" % _fmt(gain))


# --------- 배경 / 스크래치 레이아웃 ---------

func _setup_background() -> void:
	# 배경 스프라이트 스케일·위치 적용 + 가로 무한 타일링(motion_mirroring)으로 run 스크롤에 대응.
	bg_sprite.scale = Vector2(BackgroundData.SCALE, BackgroundData.SCALE)
	bg_sprite.position = Vector2(0.0, BackgroundData.Y_OFFSET)
	var scaled_w: float = bg_sprite.texture.get_width() * BackgroundData.SCALE
	bg_layer.motion_mirroring = Vector2(scaled_w, 0)


func _setup_scratch_card_layout() -> void:
	# 스크래치 영역/티켓 배경 위치·크기를 ScratchCardLayout 상수로 배치하고, 카드 격자를 명시 크기로 빌드.
	# (웹에서 anchor 기반 size가 0으로 남는 문제 회피 — configure로 크기 직접 지정)
	scratch_card_area.offset_top = -ScratchCardLayout.BOTTOM_MARGIN - ScratchCardLayout.HEIGHT
	scratch_card_area.offset_bottom = -ScratchCardLayout.BOTTOM_MARGIN
	if ScratchCardLayout.WIDTH > 0.0:
		scratch_card_area.anchor_right = 0.0
		scratch_card_area.offset_left = 0.0
		scratch_card_area.offset_right = ScratchCardLayout.WIDTH
	else:
		scratch_card_area.anchor_right = 1.0
		scratch_card_area.offset_left = 0.0
		scratch_card_area.offset_right = 0.0
	scratch_card_area.scale = Vector2(ScratchCardLayout.SCALE, ScratchCardLayout.SCALE)
	scratch_card_area.position += Vector2(ScratchCardLayout.X_OFFSET, ScratchCardLayout.Y_OFFSET)
	ticket_bg.scale = Vector2(ScratchCardLayout.TICKET_BG_SCALE, ScratchCardLayout.TICKET_BG_SCALE)
	ticket_bg.position = Vector2(ScratchCardLayout.TICKET_BG_X, ScratchCardLayout.TICKET_BG_Y)
	var grid_w: float = ScratchCardLayout.WIDTH if ScratchCardLayout.WIDTH > 0.0 else scratch_card_area.size.x
	_apply_scratch_numbers()  # 숫자 분포 먼저 (configure의 new_card가 사용)
	scratch_card.configure(Vector2(grid_w, ScratchCardLayout.HEIGHT))
	scratch_card.auto_rate = Upgrades.value("auto_speed")
	scratch_card.brush_radius = Upgrades.value("brush")


func _apply_scratch_numbers() -> void:
	# 스크래치 칸 숫자 분포 적용. 우선순위: 치트 상수(SCRATCH_NUMBER_WEIGHTS) > 유물 ①분포 > 균등 1~9.
	# 강화·복권 등급 연동도 여기서. 런타임 변경 후엔 reset_card()로 즉시 반영.
	# ④ 와일드: 장착된 wild 유물들의 발생확률 + 상한을 스크래치에 전달(카드마다 재추첨).
	# 유물 효과 계산은 RelicEffectsScript(scripts/relic_effects.gd)로 분리 — 여기는 scratch_card 배선만.
	scratch_card.wild_chances = RelicEffectsScript.wild_chances()
	scratch_card.wild_cap = RelicsScript.wild_cap()
	if not SCRATCH_NUMBER_WEIGHTS.is_empty():
		scratch_card.set_number_weights(SCRATCH_NUMBER_WEIGHTS)
		return
	var w: Dictionary = RelicEffectsScript.number_weights()
	if w.is_empty():
		scratch_card.set_number_range(1, 9)
	else:
		scratch_card.set_number_weights(w)


# --------- PC 상태 전이 ---------

func _reset_pending_attack_flags() -> void:
	# 끊긴 공격 pending/AoE 플래그 일괄 정리 — 스윙이 상태 전환에 끊겨 종료 시그널이 안 와도
	# 플래그 고착 방지(프리징 안전장치). _auto_atk_accum/_cutin_active/_show_full_gauge 는 호출부가 별도 관리.
	_skill_pending = false
	_pending_attack_damage = 0
	_auto_pending = false
	_auto_pending_damage = 0
	_aoe_active = false
	_skill_resolving = false


func _enter_idle() -> void:
	# 적 조우 → 정지. 카드 잠금 해제 + 활성화 강조(노란 펑 → 흰색). 자동 긁기 속도 최신값 반영.
	# 교전 (재)진입 시 끊긴 공격 pending 정리 — 스윙이 상태 전환에 끊겨 종료 시그널이 안 와도 플래그 고착 방지(프리징 안전장치).
	_reset_pending_attack_flags()
	pc_state = PcState.IDLE
	player.play_idle()
	# 튜토리얼 1·2단계는 자동 긁기 OFF(직접 긁도록 유도). 그 외엔 정상.
	scratch_card.auto_rate = 0.0 if (_tut == Tut.SCRATCH or _tut == Tut.JACKPOT) else _effective_auto_rate()
	# 잠긴(완성·소비) 카드면 교전 진입 시 새 카드로 — 스킬 모션이 전환에 끊겨 리셋을 못 받았더라도 고착 해소(안전장치).
	# (안 잠긴 = 웨이브 내 부분 긁기 보존분 → 그대로 유지.)
	if scratch_card.is_locked:
		scratch_card.reset_card()  # is_locked=false + 새 카드
	scratch_card.modulate = ACTIVE_FLASH_TINT
	var tw := create_tween()
	tw.tween_property(scratch_card, "modulate", Color(1, 1, 1, 1), 0.4)
	_show_full_gauge = false  # 다음 몹 조우 → 게이지 100% 해제(새 스테이지 진행도 0%부터)
	_refresh_hud()


func _enter_run(lock_and_reset: bool = true) -> void:
	# 다음 적으로 이동. lock_and_reset=true(웨이브 간 이동·인트로·부활 등): 카드 잠금 + 새 카드 리셋.
	#   false(웨이브 내 다음 적으로 PC 전진): 카드 그대로 둠 — 덩어리 전멸 전엔 잠금/초기화 안 함(연속 조작).
	_reset_pending_attack_flags()  # 진행 중 스킬·자동공격·AoE pending 정리(이동/전진 시)
	_auto_atk_accum = 0.0
	pc_state = PcState.RUN
	player.play_run()
	if lock_and_reset:
		_lock_card()
		scratch_card.reset_card()  # reset_card가 내부에서 is_locked=false로 푸므로 직후 다시 잠근다
		scratch_card.is_locked = true


# --------- 적 스폰 / 조우 ---------

func _spawn_next() -> void:
	# 현재 스테이지의 적 웨이브 스폰. 보스=1마리, 잡몹=같은 종류 2~4마리(앞부터 1마리씩 교전, 뒤는 대기).
	# 적은 화면 우측 밖에서 스폰 → run 시뮬레이션으로 STOP_X까지 좌로 흘러온다.
	_clear_wave()  # 남은 적 정리(치트·재스폰 안전)
	if _mode == Mode.DUNGEON:
		_spawn_dungeon_boss()  # 던전 = 보스 1체(룰·빨강 틴트), 웨이브 미사용
		return
	var boss: bool = Balance.is_boss_stage(stage)
	in_boss = boss
	# 잡몹만 여러 마리. 보스·튜토리얼 중엔 1마리(플로우 보호).
	var count: int = 1 if (boss or _tut != Tut.OFF) else randi_range(WAVE_MIN, WAVE_MAX)
	var wave_variant: String = "" if boss else Enemy.pick_variant()  # 웨이브 외형 통일(보스는 전용 틴트·단독)
	if boss:
		# 보스전 진입: PC HP 풀 충전 (시각 동기화는 아래 공통 코드가 수행)
		_restore_full_hp(false)
		Audio.play_sfx("boss")  # 보스 등장
	for i in count:
		var e := _make_wave_enemy(boss, wave_variant, i)
		if i == 0:
			current_enemy = e
		else:
			_wave_queue.append(e)
	# PC 체력바: 머리 위 바(교전 중 표시, 튜토리얼 중 숨김) + 좌상단 HUD 바 둘 다 갱신.
	player.set_max_hp(player_max_hp)
	player.set_hp(player_hp)
	player.set_hp_visible(_tut == Tut.OFF)
	_update_hp_hud()
	_refresh_hud()


func _make_wave_enemy(boss: bool, wave_variant: String, slot: int) -> Enemy:
	# 웨이브 1마리 생성. slot=0 맨 앞(교전), slot>0 뒤 대기. spawn_x를 slot만큼 더 우측으로(대형).
	var e: Enemy = EnemyScene.instantiate()
	e.max_hp = int(ceil(Balance.enemy_hp(stage)))  # 스테이지 스케일 HP
	e.is_boss = boss
	if wave_variant != "":
		e.variant = wave_variant  # 웨이브 외형 통일
	if boss:
		e.attack_interval = Balance.BOSS_ATTACK_INTERVAL
		e.attack_windup = Balance.BOSS_ATTACK_WINDUP
		e.attack_damage = 999999 if BOSS_ONESHOT_TEST else int(ceil(Balance.boss_attack_damage(stage)))
	else:
		# 일반몹도 PC를 공격(앞 1마리만 start_attacking). HP는 유지(블록 누적).
		e.attack_interval = Balance.MOB_ATTACK_INTERVAL
		e.attack_windup = Balance.MOB_ATTACK_WINDUP
		e.attack_damage = max(1, int(ceil(Balance.mob_attack_damage(stage))))
	if _tut == Tut.SCRATCH:
		e.max_hp = _tutorial_mob_hp()  # 튜토리얼 1단계 고HP
	e.z_index = -slot  # 맨 앞(slot 0)이 위에 그려지게(뒤 적은 아래)
	var spawn_x: float = arena.size.x + EnemyData.SPAWN_OFFSET_FROM_RIGHT + float(slot) * WAVE_SPACING
	e.position = Vector2(spawn_x, arena.size.y - EnemyData.SPAWN_Y_FROM_BOTTOM)
	arena.add_child(e)
	e.died.connect(_on_enemy_died.bind(e))
	e.attacked_player.connect(_on_enemy_attacked_player)
	return e


func _clear_wave() -> void:
	# 현재 적(맨 앞) + 대기열 전부 제거(웨이브 리셋 — 사망/치트/재스폰 안전).
	# ⚠️ queue_free 전 is_dead=true로 — 적이 공격 windup(await) 중이면 그 코루틴이 재개 시 조기 return하게
	#    (안 그러면 free된 노드에서 await 재개 → "script object freed" 콘솔 에러).
	if is_instance_valid(current_enemy):
		current_enemy.is_dead = true
		current_enemy.queue_free()
	current_enemy = null
	for q in _wave_queue:
		if is_instance_valid(q):
			q.is_dead = true
			q.queue_free()
	_wave_queue.clear()


func _snap_wave_positions() -> void:
	# run 종료 시 대형 정렬: front=STOP_X, 대기열은 뒤로 WAVE_SPACING씩.
	if is_instance_valid(current_enemy):
		current_enemy.position.x = EnemyData.STOP_X
	for i in _wave_queue.size():
		if is_instance_valid(_wave_queue[i]):
			_wave_queue[i].position.x = EnemyData.STOP_X + float(i + 1) * WAVE_SPACING


func _on_enemy_reached_position() -> void:
	_enter_idle()
	# 튜토리얼 중엔 적이 PC를 공격하지 않는다(1·2단계). 그 외엔 보스·일반몹 모두 공격.
	if current_enemy != null and _tut == Tut.OFF:
		current_enemy.start_attacking()


# --------- 전투 흐름 ---------

func _on_card_completed(result: Dictionary) -> void:
	if _player_dying:
		return
	var hand_count: int = int(result["count"])
	NotificationManager.hand_result(int(result["value"]), hand_count, hand_count >= JACKPOT_COUNT)  # 족보 결과 토스트(중앙)
	# 던전 hand_gate 룰: 최소 족보 미달 스킬은 무효(데미지 0). 기본(자동)공격은 그대로 동작 — 게이트는 스킬에만.
	if _mode == Mode.DUNGEON and _dungeon_hand_gate > 0 and hand_count < _dungeon_hand_gate:
		Audio.play_sfx("hand")
		NotificationManager.info("족보 부족! (무효)")
		if current_enemy != null and not current_enemy.is_dead:
			scratch_card.reset_card()  # 새 카드로 재시도
		return
	# 잭팟 보너스 골드 (즉시) — 던전은 골드 미지급(첫 돌파 다이아·가루만)이라 메인에서만.
	if hand_count >= JACKPOT_COUNT:
		Audio.play_sfx("jackpot")
		NotificationManager.achievement(Achievements.unlock("jackpot"))
		if _mode == Mode.MAIN:
			_grant_gold(Balance.gold_reward(stage) * Balance.JACKPOT_GOLD_MULT)
			_refresh_hud()
	else:
		Audio.play_sfx("hand")
		if hand_count >= HIGH_HAND_COUNT:
			NotificationManager.achievement(Achievements.unlock("four_kind"))
	# 스크래치 스킬(버스트) = 캐릭터 공격력(무기 보너스 포함) × 복권 배율 × 족보배율
	var atk: float = _attack_power()
	var card_mult: float = Upgrades.value("card_mult")
	var mult: int = int(result.get("mult", 1))
	var relic_mult: float = RelicEffectsScript.skill_mult(hand_count)  # ⑤ 등급 보정(밴드)
	var expand_mult: float = RelicEffectsScript.expand_mult(result.get("groups", []))  # ② 족보 확장(투페어/풀하우스)
	_pending_attack_damage = int(round(atk * card_mult * float(mult) * relic_mult * expand_mult))
	_skill_pending = true  # attack 모션 종료 시 버스트 적용(자동공격 모션과 구분)
	_skill_hand_count = hand_count  # 연출 강도(화면 흔들림)용
	# 고족보면: 화면 일시멈춤 + 컷인 먼저 재생 → 끝나면 공격. 그 외엔 바로 공격.
	if _cut_in != null and hand_count >= CUTIN_MIN_COUNT and not _cutin_active:
		await _play_cutin_then_attack()
	else:
		_start_attack_swing()


func _play_cutin_then_attack() -> void:
	# 고족보 컷인 시퀀스: 화면 일시멈춤(트리 pause — 컷인만 PROCESS_MODE_ALWAYS라 멈춤 중에도 재생) →
	# 컷인 종료 대기 → 멈춤 해제 → 공격 재생. 멈춤 동안 PC·몬스터·자동공격·입력 전부 정지.
	# 공격 버스트는 공격 모션 종료 시 _on_player_attack_completed에서 적용된다(컷인 뒤 "공격 재생").
	if _cut_in.is_playing():
		# (이론상 멈춤 전이라 재생 중일 수 없음) 안전망: 멈춤 없이 바로 공격.
		_start_attack_swing()
		return
	# 1) 공개 대기: 스크래치가 완전히 공개될 때까지 잠깐(셀 페이드 끝나고 9칸 숫자 다 보인 뒤 컷인).
	#    그 동안 PC는 idle 대기 + 자동공격 억제(_cutin_active) → 진행 중이던 attack 모션 정리.
	_cutin_active = true
	_auto_atk_accum = 0.0
	player.play_idle()
	await get_tree().create_timer(CUTIN_REVEAL_DELAY).timeout
	if not is_inside_tree() or _player_dying:
		_cutin_active = false
		return
	# 2) 화면 멈춤 + 컷인 재생 → 종료 대기 → 멈춤 해제.
	# ⚠️ play()가 false(busy/트리밖 → finished 미발화)면 await를 건너뛰어 pause 영구 고착(프리징)을 구조적으로 차단.
	get_tree().paused = true
	if _cut_in.play(_skill_hand_count):
		await _cut_in.finished
	# ⚠️ pause는 트리 전역 플래그이고 씬 전환에도 유지된다. 트리 밖이어도(teardown 경합) 무조건 해제 —
	#    안 그러면 다음 씬(login)이 멈춘 채 로드돼 영구 프리징. get_tree()는 노드가 트리 밖이어도 유효.
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	_cutin_active = false
	if not is_inside_tree() or _player_dying:
		return
	# 3) 컷인 후 깨끗한 새 스윙(idle→attack이라 replay 됨). 버스트는 attack 모션 종료 시 적용.
	_start_attack_swing()


func _auto_attack() -> void:
	# 일반 공격(자동) 1회 시작. 데미지 = 공격력 × AUTO_ATK_COEF.
	# **데미지·이펙트는 attack 모션 종료 시 적용**(스킬과 동일) — 한 방 처치 시 전진(run)이 스윙을 끊지 않게.
	if _skill_pending or _auto_pending or _skill_resolving:
		return  # 진행 중인 공격 모션·스킬 연타가 있으면 새 자동공격 시작 안 함(중복 방지)
	# 던전 hand_gate 층: 자동공격(기본공격)은 그대로 동작 — 게이트는 스크래치 "스킬"에만 적용(사용자 결정).
	# pc_atk_down 배수만 적용(메인은 _dungeon_pc_atk_mult=1.0).
	var e: Enemy = current_enemy
	if e == null or e.is_dead:
		return
	_auto_pending = true
	_auto_pending_damage = max(1, int(round(_attack_power() * Balance.AUTO_ATK_COEF * _dungeon_pc_atk_mult)))
	player.play_auto_attack()  # 데미지/이펙트는 _on_player_attack_completed(모션 종료)에서


func _on_player_attack_completed() -> void:
	# attack 모션 종료 시 데미지 적용 (스킬·자동공격 공통 — 스윙이 끝난 뒤 처치/전진).
	if _player_dying:
		_skill_pending = false
		_auto_pending = false
		return
	# 1) 스크래치 스킬(버스트) — 금색 팝 + 족보 이펙트 + 화면 흔들림
	if _skill_pending:
		_skill_pending = false
		_auto_pending = false  # 스킬 우선 — 대기 중 자동공격은 폐기
		var dmg: int = _pending_attack_damage
		_pending_attack_damage = 0
		# ⚠️ take_damage가 적을 죽이면 died가 "동기" 발화 → _on_enemy_died가 current_enemy=null. 이후 로컬 e로 판정.
		var e: Enemy = current_enemy
		if e == null or e.is_dead:
			return
		Audio.play_sfx("hit")
		# 족보별 화면 흔들림: 잭팟(≥9) 화면 전체 강하게 / 고족보(≥4) 전투영역 중간 / 그 외 약하게
		if _skill_hand_count >= JACKPOT_COUNT:
			Effects.screen_shake(self, 10.0)
		elif _skill_hand_count >= HIGH_HAND_COUNT:
			Effects.screen_shake(arena, 6.0)
		else:
			Effects.screen_shake(arena, 3.0)
		# 튜토리얼 = 스크립트 단일 타격(다타격 안 함 — 연출 단순·확정 처치).
		if _tut == Tut.JACKPOT:
			# 2단계: 잭팟 강제 처치(적 고HP라 정상 데미지론 안 죽음 → 확정 처치, 1마리)
			_spawn_skill_hit_fx(e, dmg)
			e.take_damage(e.current_hp)  # → _on_enemy_died
			return
		if _tut == Tut.SCRATCH:
			# 1단계: 단일 타격(적 고HP라 생존) → 2단계로 전환
			_spawn_skill_hit_fx(e, dmg)
			e.take_damage(dmg)
			if not e.is_dead:
				_enter_tut_jackpot()
			elif current_enemy != null:
				scratch_card.reset_card()
			return
		# 정상 플레이 = 다타격(쪼개기): 타수 = 족보 count, 한 타 = 총딜/타수(누적 반올림 → 총합 유지).
		# 잭팟(count ≥ AOE_MIN_COUNT) = 무리 전체 연타 / 그 외 = 앞 1마리 연타.
		var targets: Array = _alive_wave_enemies() if _skill_hand_count >= AOE_MIN_COUNT else [e]
		_skill_multihit(targets, dmg, _skill_hand_count)
		return
	# 2) 일반 공격(자동) — 작은 버스트 + 작은 플로터 (스윙 종료 시점에 데미지)
	if _auto_pending:
		_auto_pending = false
		var admg: int = _auto_pending_damage
		_auto_pending_damage = 0
		# ⚠️ take_damage가 죽이면 died 동기 발화 → _on_enemy_died(전진/스폰). 이후 로컬 ae로만 판정.
		var ae: Enemy = current_enemy
		if ae == null or ae.is_dead:
			return
		Audio.play_sfx("hit")
		Effects.spawn_impact_burst(arena, ae.position + ENEMY_IMPACT_OFFSET, 14.0)  # 자동공격 = 작은 버스트
		Effects.spawn_damage_floater(arena, ae.position + ENEMY_FLOATER_OFFSET, admg, false)  # big=false(작게)
		ae.take_damage(admg)


func _skill_multihit(targets: Array, total: int, hits: int) -> void:
	# 스킬 버스트 = 족보 count만큼 연타(다다다닥). **총딜 유지(쪼개기)**: 한 타 = 누적 반올림 차분 → 합 = total.
	#   (기존 족보배율 count²×value 중 count 한 겹을 "타수"로 시각화 — 총 데미지·밸런스는 동일.)
	# 단일 = 앞 1마리(targets 1개) / 잭팟(count≥AOE_MIN_COUNT) = 무리 전체(각 타가 살아있는 모든 적에 동시).
	# AoE 패턴 재사용: 시퀀스 동안 _aoe_active(개별 처치=골드·연출만, 대형/스테이지 정리는 끝에 일괄)
	#   + _skill_resolving(await 동안 자동공격·재진입 억제). 끝나면 _resolve_wave_after_aoe로 정리.
	hits = max(1, hits)
	# 시퀀스 중 모드가 바뀌면(던전 실패/클리어/진입 — await 동안 PC 사망·시간초과 등) 재개 시 정리를 건너뛰고 빠져나간다.
	# _exit_dungeon 이 이미 새 모드 상태(적·카드)를 세팅하므로, 옛 시퀀스가 _resolve_wave_after_aoe 로 그걸 덮으면 손상.
	var entry_mode: Mode = _mode
	if targets.is_empty():
		return
	_aoe_active = true
	_skill_resolving = true
	# 스킬 발동 풀 이펙트(링·파편)는 대상별 1회 — 연타는 작은 임팩트 + 빨강 플로터로(과다 연출 방지).
	for t in targets:
		if is_instance_valid(t) and not t.is_dead:
			Effects.spawn_skill_effect(arena, t.position + ENEMY_SKILL_OFFSET, _skill_hand_count)
	var prev_cum: int = 0
	for i in range(hits):
		var is_last: bool = (i == hits - 1)
		var cum: int = int(round(float(total) * float(i + 1) / float(hits)))
		var hit_dmg: int = max(1, cum - prev_cum)
		prev_cum = cum
		var any_alive: bool = false
		for t in targets:
			if not is_instance_valid(t) or t.is_dead:
				continue
			any_alive = true
			# 각 타 플로터·임팩트를 흩뿌려 연타가 "다다다닥"으로 보이게(같은 자리면 겹쳐서 한 방처럼 보임).
			var jitter := Vector2(randf_range(-18.0, 18.0), randf_range(-10.0, 4.0))
			Effects.spawn_impact_burst(arena, t.position + ENEMY_IMPACT_OFFSET + jitter, 16.0)
			Effects.spawn_damage_floater(arena, t.position + ENEMY_FLOATER_OFFSET + jitter, hit_dmg, false, true)
			# 약한 적도 연타를 끝까지 보여주고 **마지막 타에 처치** — 마지막 전 타는 HP를 최소 1 남기도록 클램프.
			# (총딜 유지: 죽일 적은 어차피 HP만큼만 들어감 = 오버킬은 원래 낭비라 밸런스 동일.)
			var applied: int = hit_dmg
			if not is_last and applied >= t.current_hp:
				applied = max(0, t.current_hp - 1)
			t.take_damage(applied)  # 마지막 타에서만 사망 가능 → _on_enemy_died(_aoe_active 분기: 골드·연출만)
		if not any_alive:
			break  # (안전) 대상 전멸 → 남은 타 생략
		if i < hits - 1:
			await get_tree().create_timer(SKILL_HIT_INTERVAL).timeout
			if _player_dying or not is_inside_tree() or _mode != entry_mode:
				_aoe_active = false
				_skill_resolving = false
				return  # 시퀀스 중 사망/씬 이탈/모드 전환 → 정리는 해당 핸들러(_exit_dungeon 등)에 위임
	_aoe_active = false
	_skill_resolving = false
	_resolve_wave_after_aoe()


func _resolve_wave_after_aoe() -> void:
	# 다타격/AoE 후 정리. 전멸=웨이브 클리어 / 앞 적 생존=계속 교전 / 앞 적 처치=PC가 다음 적으로 전진(일반 처치와 동일 run 모션).
	var front_alive: bool = is_instance_valid(current_enemy) and not current_enemy.is_dead  # 재할당 전에 옛 앞 적 생사 판정
	var survivors: Array = _alive_wave_enemies()
	if survivors.is_empty():
		# 전멸 → 웨이브 클리어 (단일 처치 경로와 동일: 스테이지 진행 + 다음 웨이브)
		current_enemy = null
		_wave_queue.clear()
		await _finish_wave_clear()
		return
	current_enemy = survivors[0]
	_wave_queue = survivors.slice(1)
	if front_alive:
		# 앞 생존(부분 타격) → 대형만 정렬, 계속 교전 + 새 카드(전진 불필요)
		_snap_wave_positions()
		if _tut == Tut.OFF and not current_enemy.is_attacking:
			current_enemy.start_attacking()
		_refresh_hud()
		scratch_card.reset_card()
	else:
		# 앞 처치 → PC가 다음 적으로 짧게 전진(run, 일반 처치와 동일 연출). 도착 시 _enter_idle이 교전 재개 + 잠긴 카드 리셋.
		_refresh_hud()
		_enter_run(false)


func _on_enemy_attacked_player(damage: int) -> void:
	# 보스 + 일반몹 모두 발생 (일반몹은 데미지·빈도가 낮음). 보스만 HP를 크게 깎는다.
	if _player_dying:
		return
	player_hp = max(0.0, player_hp - float(damage))
	player.set_hp(player_hp)
	_update_hp_hud()
	Effects.spawn_damage_floater(arena, player.position + PLAYER_FLOATER_OFFSET, damage, true)
	if player_hp <= 0.0:
		_on_player_died()
		return
	Audio.play_sfx("player_hit")
	# 컷인 시퀀스(공개 대기~컷인) 중엔 피격 플린치(attacked 모션·플래시) 억제 → PC를 idle로 유지(연출 중 흐트러짐 방지).
	# (데미지·HP는 위에서 이미 적용됨. 모션만 안 튐.)
	if not _cutin_active:
		player.flash_hit()
		player.play_attacked()


func _advance_stage_after_kill(was_boss: bool) -> bool:
	# 처치로 스테이지 진행 판정: 보스 처치 → 다음 스테이지 / 잡몹은 N마리 채우면 다음 스테이지.
	# set_stage 저장 + (보스 클리어 시) 즉시 flush + 게이지 100% 유지 플래그 설정. cleared(스테이지 넘김) 반환.
	var cleared := false
	if was_boss:
		stage += 1
		mobs_killed_in_stage = 0
		cleared = true
	else:
		mobs_killed_in_stage += 1
		if mobs_killed_in_stage >= Balance.MOBS_PER_STAGE:
			stage += 1
			mobs_killed_in_stage = 0
			cleared = true
	BackendService.set_stage(stage)
	if was_boss:
		BackendService.flush()  # 보스 클리어 = 의미 있는 이산 이벤트 → 즉시 저장
	_show_full_gauge = cleared  # 클리어 시 게이지 100% 유지(다음 몹 조우 = _enter_idle 에서 0%로)
	return cleared


func _lock_card() -> void:
	# 스크래치 잠금 + 어둡게(이동/처치 등 비교전 구간). 해제는 _enter_idle/reset_card 가 소유.
	scratch_card.is_locked = true
	scratch_card.modulate = LOCKED_TINT


func _alive_wave_enemies() -> Array:
	# 살아있는 웨이브 전체(앞 current_enemy + 대기열) 수집 — AoE 대상/생존자 판정 공용.
	var out: Array = []
	if is_instance_valid(current_enemy) and not current_enemy.is_dead:
		out.append(current_enemy)
	for q in _wave_queue:
		if is_instance_valid(q) and not q.is_dead:
			out.append(q)
	return out


func _spawn_skill_hit_fx(e: Enemy, dmg: int) -> void:
	# 스킬 적중 이펙트 쌍(족보 이펙트 + 금색 큰 플로터). _skill_hand_count 는 호출 시점 멤버값 사용.
	Effects.spawn_skill_effect(arena, e.position + ENEMY_SKILL_OFFSET, _skill_hand_count)
	Effects.spawn_damage_floater(arena, e.position + ENEMY_FLOATER_OFFSET, dmg, false, true)


func _grant_gold(amount: float) -> void:
	# 골드 획득 단일 경로 — 지급 + 누적 통계(gold_earned, 퀘스트 "골드 N 획득" 진행도). 차감/환불엔 쓰지 않음.
	BackendService.add_gold(amount)
	BackendService.add_stat("gold_earned", int(amount))


func _start_attack_swing() -> void:
	# 공격 스윙 시작 = sfx + 모션(불변식 고정 — 컷인 플로우 수정 시 한쪽만 바뀌는 사고 방지).
	Audio.play_sfx("attack")
	player.play_attack()


func _finish_wave_clear() -> void:
	# 웨이브 전멸 공통 마무리(승리 단일 chokepoint — 자동/스킬/AoE 처치 모두 여기로 모임).
	# 던전이면 층 클리어로 분기(스테이지 진행·다음 웨이브 안 함).
	if _mode == Mode.DUNGEON:
		_dungeon_clear()
		return
	# 스테이지 진행 → HUD → 카드 잠금 → 대기 → 다음 웨이브 (await 코루틴).
	var was_boss: bool = in_boss
	var cleared := _advance_stage_after_kill(was_boss)
	_refresh_hud()
	_lock_card()
	await get_tree().create_timer(STAGE_CLEAR_DELAY if cleared else POST_KILL_DELAY).timeout
	if is_inside_tree() and not _player_dying:
		_enter_run()
		_spawn_next()


func _on_enemy_died(enemy: Control) -> void:
	# 적 처치: 마리당 골드 → (튜토리얼 분기) → 웨이브에 다음 적 있으면 전진(진행 X), 전멸이면 스테이지 진행(웨이브=1).
	Audio.play_sfx("kill")
	# 메인 골드·통계·보스 가루는 메인 모드에서만. 던전 처치 = 메인 진행과 무관(보상은 _dungeon_clear 첫 돌파만).
	if _mode == Mode.MAIN:
		_grant_gold(Balance.gold_reward(stage))  # 마리당 골드(스테이지 스케일) + gold_earned 통계

	# 튜토리얼 2단계 처치 → 칭찬 → 3단계. 일반 진행/스폰·업적·통계는 건너뛴다. (튜토리얼은 항상 메인 모드)
	if _tut == Tut.JACKPOT:
		_refresh_hud()
		_on_tut_enemy_killed(enemy)
		return

	if _mode == Mode.MAIN:
		BackendService.add_stat("total_kills", 1)
		if in_boss:
			BackendService.add_stat("boss_kills", 1)  # 보스 처치 통계(퀘스트 "보스 K회" 진행도)
			var dust_gain: float = BackendService.grant_boss_dust(stage)  # 보스 첫 클리어 유물 가루(재파밍 시 0)
			if dust_gain > 0.0:
				Events.currency_changed.emit()  # 열린 패널(상점/유물) 가루 표시 즉시 갱신
				Audio.play_sfx("reward")  # 다른 보상 토스트와 동일하게 reward 효과음(보스 kill 음과 함께)
				NotificationManager.reward("유물 가루\n+%s" % _fmt(dust_gain))
		NotificationManager.achievements(Achievements.check_stat_achievements())

	# 사망 연출 (폭발 + 본체 축소·페이드) — 죽은 적만
	_play_death_fx(enemy, true)

	# AoE(무리 전체 타격) 중이면: 개별 처치는 골드·연출만, 대형/스테이지 정리는 _resolve_wave_after_aoe가 일괄 처리.
	if _aoe_active:
		_refresh_hud()
		return
	current_enemy = null

	# 웨이브에 다음 적이 남았으면 → PC가 짧게 전진(run 재사용)해서 다음 적과 교전. 스테이지 진행 X.
	if not _wave_queue.is_empty():
		current_enemy = _wave_queue.pop_front()
		_refresh_hud()
		# lock_and_reset=false: 덩어리 전멸 전이라 스크래치는 그대로 조작 가능(잠금/초기화 안 함, 연속).
		_enter_run(false)  # PC 전진(카드 유지): 다음 적이 STOP_X까지 ~WAVE_SPACING. run 루프가 도착 시 idle.
		return

	# 웨이브 전멸 → 스테이지 진행(웨이브=진행 1) + 저장 → 잠시 후 다음 웨이브로 이동
	await _finish_wave_clear()


# --------- PC 사망 → 블록 재시작 ---------

func _on_player_died() -> void:
	# 던전이면 사망 = 그 판 실패(결과 모달). 메인 블록 후퇴·사망 연출 안 함(페널티 = 시간뿐).
	if _mode == Mode.DUNGEON:
		_dungeon_fail("체력 소진")
		return
	_player_dying = true
	in_boss = false
	_show_full_gauge = false  # 사망/블록 재시작 시 게이지 100% 연출 해제
	Audio.play_sfx("player_dead")
	# 흔들림(screen_shake) 명시 중단·복구.
	# ⚠️ 예전엔 get_processed_tweens() 전역 kill 이었으나, 그건 전투뿐 아니라 UI 토스트·패널·결과 팝업의
	#    free 콜백까지 끊어 찌꺼기 노드/모달 박제를 유발 → 제거. 대신:
	#    흔들림=reset_shake가 명시 정지 / 적 트윈=_clear_wave의 queue_free로 자동 정리(노드에 바인딩됨)
	#    / 전투 이펙트(플로터·스킬)=자연 종료 후 _clear_arena_effects가 마무리.
	Effects.reset_shake(self)
	Effects.reset_shake(arena)
	_clear_wave()  # 웨이브 전체(앞+대기열) 제거
	pc_state = PcState.IDLE
	_lock_card()
	player.reset_visual()
	player.play_dead()
	await player.animation_finished
	if not is_inside_tree():
		return
	await get_tree().create_timer(DEATH_RESTART_DELAY).timeout
	if not is_inside_tree():
		return
	# 부활/스테이지 이동 시점에 이펙트 잔여물(피격 플로터·버스트 등) 정리 → 플로터가 이때 사라짐.
	_clear_arena_effects()
	# 사망 시 소폭 후퇴 (DEATH_SETBACK 만큼, 블록 첫 스테이지가 바닥선). 골드·강화 유지.
	stage = Balance.retry_stage(stage)
	mobs_killed_in_stage = 0
	BackendService.set_stage(stage)
	BackendService.flush()
	player.set_hp_visible(false)
	player.revive()
	# 부활 시 HP 풀 회복 — 일반몹도 공격하므로 HP 0인 채 재시작하면 즉사 루프가 됨(방지).
	_restore_full_hp()
	_player_dying = false
	_refresh_hud()
	_enter_run()
	_spawn_next()


# --------- 던전 "시련의 탑" (능동 보스 도전 모드) ---------
# 메인 무한 스테이지와 같은 아레나·전투를 쓰되 _mode 로 분기. 룰(hand_gate/time_limit/pc_atk_down)만 다름.
# 보상 = 첫 돌파 1회성(다이아·가루), 재도전 보상 없음(클리어=완료, 재입장 불가). 실패=입구(패널)로.
# 기획서: docs/design/던전 시스템 정리본.md

func _on_dungeon_enter_requested(floor: int) -> void:
	# 던전 패널 "도전" → 던전 모드 진입(튜토리얼·사망 중엔 무시).
	if _tut != Tut.OFF or _player_dying:
		return
	# await 기반 전투 시퀀스(다타격 _skill_multihit·컷인)만 진입 금지 — suspend 된 코루틴은
	# _reset_combat_flags 로 못 멈추고, 재개 시 _resolve_wave_after_aoe/컷인 pause 가 던전 상태를 손상시킨다.
	# ⚠️ _auto_pending/_skill_pending(즉시 적용 대기 플래그)은 _reset_combat_flags 가 안전하게 끄고
	#    모션 종료 핸들러가 무해 return 하므로 막지 않는다 — 막으면 자동공격 모션(잦음)마다 진입이 거부됨.
	#    (_aoe_active 는 _skill_resolving 과 항상 함께 set/clear 되므로 _skill_resolving 으로 충분.)
	if _skill_resolving or _cutin_active:
		Audio.play_sfx("button")
		NotificationManager.info("잠시 후 다시 시도하세요")
		return
	# 입장권 소모(도전·재도전 공통). 부족하면 입장 불가(자정 충전 / 추후 광고·IAP).
	if not BackendService.consume_dungeon_ticket():
		Audio.play_sfx("button")
		NotificationManager.info("입장권이 부족합니다 (자정에 충전)")
		return
	_enter_dungeon(floor)


func _reset_combat_flags() -> void:
	# 모드 전환 시 전투 진행 플래그 일괄 정리(상태 잔재 = 프리징 원인 — 진입/퇴장에서 명시 리셋).
	_reset_pending_attack_flags()
	_cutin_active = false
	_auto_atk_accum = 0.0
	_show_full_gauge = false


func _enter_dungeon(floor: int) -> void:
	# 스테이지 → 던전 = "이동" 연출(검은 화면 페이드 + 짧은 로딩). 가려진 동안 모드/적을 교체해 전환을 매끄럽게.
	if floor < 1 or floor > DungeonDataScript.floor_count():
		return
	UIManager.hide_all()  # 던전 패널 닫기(밴드 패널)
	if get_tree() != null:
		get_tree().paused = false  # 혹시 모를 컷인 pause 잔재 해제(안전)
	_lock_card()  # 이동 연출 동안 자동 긁기 정지(전환 중 새 스킬 발동 방지)
	# 1) 화면을 어둡게 덮으며 "시련의 탑 N층 / 이동 중…"(의미상 짧은 로딩).
	await _dungeon_travel_cover(floor)
	if not is_inside_tree():
		return
	if _player_dying:
		# 연출 중 PC 사망(메인 보스 피격 등) → 던전 진입 취소, 화면만 복구.
		await _dungeon_travel_reveal()
		return
	# 2) 가려진 동안 모드/적 교체
	_mode = Mode.DUNGEON
	_dungeon_floor = floor
	_dungeon_hand_gate = DungeonDataScript.hand_gate(floor)
	_dungeon_time_left = DungeonDataScript.time_limit(floor)
	_dungeon_pc_atk_mult = max(0.0, 1.0 - DungeonDataScript.pc_atk_down(floor))
	_player_dying = false
	_reset_combat_flags()
	_clear_wave()
	_restore_full_hp()
	_dungeon_enter_msec = Time.get_ticks_msec()  # 소요시간 측정 시작
	_refresh_hud()
	_enter_run()    # PC run → 보스가 우측에서 진입
	_spawn_next()   # _mode==DUNGEON → _spawn_dungeon_boss
	# 3) 화면 밝히며 던전 노출(보스가 우측에서 걸어 들어옴 = 도착 느낌)
	await _dungeon_travel_reveal()


func _build_travel_overlay() -> void:
	# 던전 이동 연출용 전체화면 페이드 오버레이(CanvasLayer 70 — HUD 위, 알림(80) 아래). 평소 숨김.
	_travel_overlay = CanvasLayer.new()
	_travel_overlay.layer = 70
	_travel_overlay.visible = false
	add_child(_travel_overlay)
	_travel_rect = ColorRect.new()
	_travel_rect.color = Color(0.04, 0.04, 0.06, 0.0)  # 거의 검정, 알파로 페이드
	_travel_rect.anchor_right = 1.0
	_travel_rect.anchor_bottom = 1.0
	_travel_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # 전환 중 입력 차단
	_travel_overlay.add_child(_travel_rect)
	_travel_label = Label.new()
	_travel_label.anchor_right = 1.0
	_travel_label.anchor_top = 0.5
	_travel_label.anchor_bottom = 0.5
	_travel_label.offset_top = -36.0
	_travel_label.offset_bottom = 36.0
	_travel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_travel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_travel_label.add_theme_font_size_override("font_size", 22)
	_travel_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.62))
	_travel_label.modulate.a = 0.0
	_travel_rect.add_child(_travel_label)


func _dungeon_travel_cover(floor: int) -> void:
	# 페이드 인(검정 덮임 + 문구) → 짧은 "이동 중" 홀드(점 애니메이션).
	if _travel_overlay == null:
		return
	var base: String = "시련의 탑 %d층" % floor
	_travel_label.text = base
	_travel_label.modulate.a = 0.0
	_travel_rect.color.a = 0.0
	_travel_overlay.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_travel_rect, "color:a", 1.0, TRAVEL_COVER_TIME)
	tw.tween_property(_travel_label, "modulate:a", 1.0, TRAVEL_COVER_TIME)
	await tw.finished
	# "이동 중" 로딩 홀드 — 점이 늘었다 줄며 로딩감(의미상). ⚠️ ASCII 점(.)만(번들폰트 안전).
	var elapsed: float = 0.0
	var step: float = 0.18
	var dots: int = 0
	while elapsed < TRAVEL_HOLD_TIME and is_inside_tree():
		_travel_label.text = "%s\n이동 중%s" % [base, ".".repeat(dots % 4)]
		dots += 1
		await get_tree().create_timer(step).timeout
		elapsed += step


func _dungeon_travel_reveal() -> void:
	# 페이드 아웃(던전/화면 노출).
	if _travel_overlay == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_travel_rect, "color:a", 0.0, TRAVEL_REVEAL_TIME)
	tw.tween_property(_travel_label, "modulate:a", 0.0, TRAVEL_REVEAL_TIME)
	await tw.finished
	_travel_overlay.visible = false


func _exit_dungeon() -> void:
	# 던전 종료 → 메인 모드 복귀(저장된 스테이지에서 재개). 던전 진행도(dungeon_max_cleared)는 별개로 유지.
	_mode = Mode.MAIN
	_dungeon_floor = 0
	_dungeon_time_left = 0.0
	_dungeon_hand_gate = 0
	_dungeon_pc_atk_mult = 1.0
	_player_dying = false
	_reset_combat_flags()
	_clear_wave()
	stage = BackendService.get_stage()
	mobs_killed_in_stage = 0
	in_boss = false
	_restore_full_hp()
	_refresh_hud()
	_enter_run()
	_spawn_next()


func _spawn_dungeon_boss() -> void:
	# 던전 보스 1체 스폰 — 메인 환산(stage_equiv) HP/공격 + 룰 + 빨강 틴트(보스처럼). 웨이브 없음.
	in_boss = true
	_restore_full_hp(false)
	Audio.play_sfx("boss")
	var e: Enemy = EnemyScene.instantiate()
	e.max_hp = DungeonDataScript.boss_hp(_dungeon_floor)
	e.is_boss = true
	e.tint_override = DUNGEON_ENEMY_TINT  # 임시: 기존 몬스터 재활용 + 색만 빨강으로 덮어씌움
	e.variant = Enemy.pick_variant()      # 외형은 기존 몬스터 무작위
	e.attack_interval = Balance.BOSS_ATTACK_INTERVAL
	e.attack_windup = Balance.BOSS_ATTACK_WINDUP
	e.attack_damage = 999999 if BOSS_ONESHOT_TEST else DungeonDataScript.boss_attack(_dungeon_floor)
	e.z_index = 0
	var spawn_x: float = arena.size.x + EnemyData.SPAWN_OFFSET_FROM_RIGHT
	e.position = Vector2(spawn_x, arena.size.y - EnemyData.SPAWN_Y_FROM_BOTTOM)
	arena.add_child(e)
	e.died.connect(_on_enemy_died.bind(e))
	e.attacked_player.connect(_on_enemy_attacked_player)
	current_enemy = e
	player.set_max_hp(player_max_hp)
	player.set_hp(player_hp)
	player.set_hp_visible(true)
	_update_hp_hud()
	_refresh_hud()


func _dungeon_clear() -> void:
	# 던전 층 클리어 — 첫 돌파=다이아·가루 마일스톤(grant_dungeon_clear), 재도전=골드·소량가루(grant_dungeon_repeat).
	# 결과 모달 표시(다음 층/나가기, 자동 등반이면 자동 진행).
	var floor_n: int = _dungeon_floor
	Audio.play_sfx("reward")
	var rewards: Array = []  # [{text, color}]
	var res: Dictionary = BackendService.grant_dungeon_clear(floor_n)  # 첫 돌파면 dia/dust, 아니면 {}
	var first_clear: bool = not res.is_empty()
	if first_clear:
		if float(res.get("dia", 0.0)) > 0.0:
			rewards.append({"text": "다이아 +%s" % _fmt(float(res["dia"])), "color": DIA_COLOR})
		if float(res.get("dust", 0.0)) > 0.0:
			rewards.append({"text": "유물 가루 +%s" % _fmt(float(res["dust"])), "color": DUST_COLOR})
	else:
		var rep: Dictionary = BackendService.grant_dungeon_repeat(floor_n)  # 재도전 보상
		if float(rep.get("gold", 0.0)) > 0.0:
			rewards.append({"text": "골드 +%s" % _fmt(float(rep["gold"])), "color": GOLD_COLOR})
		if float(rep.get("dust", 0.0)) > 0.0:
			rewards.append({"text": "유물 가루 +%s" % _fmt(float(rep["dust"])), "color": DUST_COLOR})
	Events.currency_changed.emit()  # HUD/패널 재화 갱신
	var elapsed: float = float(Time.get_ticks_msec() - _dungeon_enter_msec) / 1000.0
	# 자동 등반(기본 켜짐): 다음 층 있고 입장권 있으면 결과 모달 없이 바로 다음 층(연출=이동 전환).
	# 끄기는 설정에만(2026-06-18). 멈춤(=결과 모달)은 실패/최고층/입장권 소진 시.
	if BackendService.get_dungeon_auto() and floor_n < DungeonDataScript.floor_count() and BackendService.get_dungeon_tickets() > 0:
		_halt_dungeon_combat()
		NotificationManager.reward(_dungeon_reward_summary(floor_n, rewards))
		if BackendService.consume_dungeon_ticket():
			_enter_dungeon(floor_n + 1)
		else:
			_return_to_dungeon_panel()  # 엣지(소진) → 입구로
		return
	# 자동 꺼짐 / 자동 정지(최고층·입장권 소진) → 결과 모달(수동 버튼)
	_show_dungeon_result(true, floor_n, elapsed, rewards, first_clear, "")


func _dungeon_reward_summary(floor_n: int, rewards: Array) -> String:
	# 자동 등반 시 층 클리어 토스트 요약(보상 인라인).
	if rewards.is_empty():
		return "%d층 클리어" % floor_n
	var parts: Array = []
	for r in rewards:
		parts.append(str((r as Dictionary).get("text", "")))
	return "%d층 클리어\n%s" % [floor_n, "  ".join(parts)]


func _dungeon_fail(cause: String = "") -> void:
	# 던전 실패(시간 초과 / 체력 소진) — 진행도 변화 0. 결과 모달(재도전/나가기).
	Audio.play_sfx("player_dead")
	var floor_n: int = _dungeon_floor
	var elapsed: float = float(Time.get_ticks_msec() - _dungeon_enter_msec) / 1000.0
	_show_dungeon_result(false, floor_n, elapsed, [], false, cause)


func _return_to_dungeon_panel() -> void:
	# 던전 한 판 종료 → 메인 복귀 + 던전 패널 다시 열기(다음 층/재도전 유도). "입구로".
	_exit_dungeon()
	if is_inside_tree():
		UIManager.open("dungeon")


# --------- 던전 결과 모달 ---------

func _close_dungeon_result() -> void:
	if _dungeon_result_overlay != null:
		_dungeon_result_overlay.queue_free()
		_dungeon_result_overlay = null


func _on_dungeon_result_next(floor_n: int) -> void:
	# 결과 모달 "다음 층 도전"/"재도전" — 입장권 1 소모 후 진입.
	Audio.play_sfx("button")
	if not BackendService.consume_dungeon_ticket():
		NotificationManager.info("입장권이 부족합니다 (자정에 충전)")
		return
	_close_dungeon_result()
	_enter_dungeon(floor_n)


func _on_dungeon_result_exit() -> void:
	# 결과 모달 "나가기"/"멈춤" — 던전 종료 후 입구(패널)로.
	Audio.play_sfx("button")
	_close_dungeon_result()
	_return_to_dungeon_panel()


func _halt_dungeon_combat() -> void:
	# 던전 결과 직전 전투 정지: 보스 제거(살아있는 보스가 계속 공격→재실패 방지) + PC idle 상태 + 카드 잠금.
	_clear_wave()
	pc_state = PcState.IDLE
	_lock_card()


func _result_center_label(parent: Control, text: String, size: int, col: Color) -> void:
	# 던전 결과 모달의 중앙정렬 라벨(제목/부제/보상/입장권 공용).
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)


func _dungeon_result_button() -> Button:
	# 던전 결과 모달 버튼(다음층/재도전/나가기 공용 생성 — 인자 동일). text/disabled/시그널은 호출부.
	return UISkin.make_buy_button(Vector2(0, 42), 14, 4, true, true, Color(0, 0, 0, 0), true)


func _show_dungeon_result(success: bool, floor_n: int, elapsed: float, rewards: Array, first_clear: bool, cause: String) -> void:
	_close_dungeon_result()
	# 결과 동안 전투 정지: 보스 제거(실패 시 살아있는 보스가 계속 공격→재실패 방지) + 카드 잠금 + PC idle.
	_halt_dungeon_combat()
	if player != null:
		player.play_idle()

	var has_next: bool = floor_n < DungeonDataScript.floor_count()
	var has_ticket: bool = BackendService.get_dungeon_tickets() > 0
	# (자동 등반 연속 진행은 _dungeon_clear 가 모달 없이 처리 — 여기 모달은 자동 꺼짐 / 정지[실패·최고층·입장권소진]일 때만.)

	# 전체화면 모달(딤 + 중앙 카드) — 게임 루트(self)에 올려 전체를 덮는다.
	var overlay := Control.new()
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_dungeon_result_overlay = overlay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UISkin.panel())
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -150.0
	card.offset_right = 150.0
	card.offset_top = -130.0
	card.offset_bottom = 130.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(card)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	m.add_child(vb)

	_result_center_label(vb, ("%d층 클리어!" % floor_n) if success else ("%d층 실패" % floor_n), 20, Color(0.55, 0.9, 0.5) if success else Color(1.0, 0.45, 0.4))

	var sub_text: String
	if success:
		sub_text = "소요 %.1f초%s" % [elapsed, "   (첫 돌파!)" if first_clear else ""]
	else:
		sub_text = ("원인: %s" % cause) if cause != "" else "도전 실패"
	_result_center_label(vb, sub_text, 12, Color(0.82, 0.82, 0.78))

	if success:
		if rewards.is_empty():
			_result_center_label(vb, "보상 없음", 12, Color(0.7, 0.7, 0.7))
		for r in rewards:
			_result_center_label(vb, str((r as Dictionary).get("text", "")), 14, (r as Dictionary).get("color", Color(1, 1, 1)))

	_result_center_label(vb, "입장권 %d" % BackendService.get_dungeon_tickets(), 11, Color(0.82, 0.85, 0.7))

	# [다음 층 도전](클리어+다음층) / [재도전](실패) + [나가기]
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	if success and has_next:
		var next_btn := _dungeon_result_button()
		next_btn.text = "다음 층 도전" if has_ticket else "입장권 부족"
		next_btn.disabled = not has_ticket
		next_btn.pressed.connect(_on_dungeon_result_next.bind(floor_n + 1))
		btn_row.add_child(next_btn)
	elif not success:
		var retry_btn := _dungeon_result_button()
		retry_btn.text = "재도전" if has_ticket else "입장권 부족"
		retry_btn.disabled = not has_ticket
		retry_btn.pressed.connect(_on_dungeon_result_next.bind(floor_n))
		btn_row.add_child(retry_btn)
	var exit_btn := _dungeon_result_button()
	exit_btn.text = "나가기"
	exit_btn.pressed.connect(_on_dungeon_result_exit)
	btn_row.add_child(exit_btn)
	vb.add_child(btn_row)


func _update_dungeon_hud() -> void:
	# 던전 배너: "N층" (+ time_limit 있으면 남은 초). 진행 게이지 = 남은 시간 비율(없으면 가득).
	if stage_label == null:
		return
	var tl: float = DungeonDataScript.time_limit(_dungeon_floor)
	if tl > 0.0:
		stage_label.text = "%d층   %d초" % [_dungeon_floor, int(ceil(_dungeon_time_left))]
		_set_bar_fill(_bar_mask, clampf(_dungeon_time_left / tl, 0.0, 1.0))
	else:
		stage_label.text = "%d층" % _dungeon_floor
		_set_bar_fill(_bar_mask, 1.0)
	if _boss_badge != null:
		_boss_badge.visible = false


# --------- 하단 내비 도크 ---------

# 내비 도크 상단 Y(전투와 스크래치 사이). 배치 순서: 전투 → 내비 → 스크래치.
const NAV_TOP_Y: float = 490.0

func _build_scratch_bg() -> void:
	# 스크래치 영역(내비 아래 ~ 화면 바닥) 뒤 배경 = #16 9-slice 프레임. 티켓/카드보다 뒤에 그려지게 이동.
	var p := Panel.new()
	p.anchor_left = 0.0
	p.anchor_right = 1.0
	p.anchor_top = 0.0
	p.anchor_bottom = 1.0
	p.offset_left = 0.0
	p.offset_right = 0.0
	p.offset_top = NAV_TOP_Y + NavDock.HEIGHT - 26.0  # 내비 아래로 올려(겹쳐) 사이 빈 공간 제거
	p.offset_bottom = 0.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UISkin.scratch_bg())
	add_child(p)
	move_child(p, ticket_bg.get_index())  # 티켓 배경 앞 인덱스로 → 티켓·카드가 위에 그려짐


func _make_chip(parent: Control, x: float, y: float, w: float, h: float) -> void:
	# 검은 반투명 둥근 칩 배경 (재화 숫자 뒤).
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_left = 0.0
	p.anchor_right = 0.0
	p.offset_left = x
	p.offset_top = y
	p.offset_right = x + w
	p.offset_bottom = y + h
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)


func _make_icon_texrect(path: String) -> TextureRect:
	# HUD 아이콘 TextureRect 공용 셋업(텍스처 로드 + expand/stretch/LINEAR 필터/입력무시). 배치(anchor/offset)는 호출부.
	var ic := TextureRect.new()
	ic.texture = load(path)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func _make_currency_icon(parent: Control, path: String, x: float, y: float, sz: float) -> void:
	# 재화 아이콘(칩 왼쪽). 작게 스케일되므로 Linear 필터로 부드럽게.
	var ic := _make_icon_texrect(path)
	ic.anchor_left = 0.0
	ic.anchor_right = 0.0
	ic.offset_left = x
	ic.offset_top = y
	ic.offset_right = x + sz
	ic.offset_bottom = y + sz
	parent.add_child(ic)


func _set_button_icon(btn: Button, icon_path: String, margin: float = 6.0) -> void:
	# HUD 아이콘 버튼 공용 — 텍스트 대신 버튼 중앙에 아이콘(여백 margin, 비율 유지·LINEAR 필터).
	# 버튼 크기에 맞춰 자동 스케일. (우편·설정 등 #19 배경 스킨 위에 얹는 아이콘)
	btn.text = ""
	var ic := _make_icon_texrect(icon_path)
	ic.anchor_right = 1.0
	ic.anchor_bottom = 1.0
	ic.offset_left = margin
	ic.offset_top = margin
	ic.offset_right = -margin
	ic.offset_bottom = -margin
	btn.add_child(ic)


func _build_top_bar() -> void:
	# 레퍼런스식 상단 바. #23 9-slice 배경(가로 가득) 위에:
	#   [가장 왼쪽 ~48px 비움(프로필 예약)] 닉네임(=계정) · 골드/다이아 칩(검은 반투명, 세로 스택) · 설정(오른끝)
	var hud: Control = $TopHUD
	var bar_top := 6.0
	var bar_bottom := 52.0

	# 1) 배경(#23) — 가로 가득, 맨 뒤로. ⚠️ 임시 placeholder(코너 장식 있음) — 내일 UI 에셋 교체 예정.
	var bar := Panel.new()
	bar.anchor_right = 1.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = bar_top
	bar.offset_bottom = bar_bottom
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", UISkin.top_bar())
	hud.add_child(bar)
	hud.move_child(bar, 0)

	# 2) 닉네임 = 로그인 계정 (왼쪽, 가장 왼쪽 ~44px 비움)
	account_label.anchor_left = 0.0
	account_label.anchor_right = 0.0
	account_label.offset_left = 46.0
	account_label.offset_right = 98.0  # 골드 칩(102~) 앞까지 — 우편/설정 버튼(둘 다 38px 정사각형) 자리 확보 위해 좌측 압축
	account_label.offset_top = bar_top + 2.0
	account_label.offset_bottom = bar_bottom - 2.0
	account_label.add_theme_font_size_override("font_size", 12)
	account_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.82))
	Effects.apply_label_shadow(account_label, 0.7, 1)
	account_label.clip_text = true
	account_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	account_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 3) 골드/다이아 = 가로 나란히(레퍼런스식). 각 칩 = 검은 반투명 + "골드/다이아 [숫자]"(컬러).
	#    아이콘 없어 텍스트로 재화 표기(추후 아이콘으로 교체).
	# 360 디자인 폭에 [프로필46][닉네임~98][골드칩102~180][다이아칩184~264][우편272~310][설정316~354] 배치.
	# 우편/설정 버튼(둘 다 38px 정사각형·우측 anchor)과 안 겹치도록 골드/다이아 칩을 좌측으로 이동(2026-06-11 우편 아이콘 버튼).
	var cur_y := 14.0
	var cur_h := 26.0
	var gold_x := 102.0
	var gold_w := 78.0
	var dia_x := 184.0
	var dia_w := 80.0
	_make_chip(hud, gold_x, cur_y, gold_w, cur_h)
	_make_chip(hud, dia_x, cur_y, dia_w, cur_h)
	# 재화 아이콘 (텍스트 "골드/다이아" 대신 칩 왼쪽에 아이콘, 숫자 라벨은 오른쪽으로 시프트)
	var ic_sz := 20.0
	var ic_y := cur_y + (cur_h - ic_sz) * 0.5
	_make_currency_icon(hud, "res://assets/ui/icon/icon_gold.png", gold_x + 4.0, ic_y, ic_sz)
	_make_currency_icon(hud, "res://assets/ui/icon/icon_dia.png", dia_x + 4.0, ic_y, ic_sz)
	# 골드
	gold_label.anchor_left = 0.0
	gold_label.anchor_right = 0.0
	gold_label.offset_left = gold_x + 27.0
	gold_label.offset_right = gold_x + gold_w - 3.0
	gold_label.offset_top = cur_y
	gold_label.offset_bottom = cur_y + cur_h
	gold_label.add_theme_font_size_override("font_size", 11)
	gold_label.clip_text = true
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 다이아
	_dia_label = Label.new()
	_dia_label.anchor_left = 0.0
	_dia_label.anchor_right = 0.0
	_dia_label.offset_left = dia_x + 27.0
	_dia_label.offset_right = dia_x + dia_w - 3.0
	_dia_label.offset_top = cur_y
	_dia_label.offset_bottom = cur_y + cur_h
	_dia_label.add_theme_font_size_override("font_size", 11)
	_dia_label.add_theme_color_override("font_color", DIA_COLOR)
	_dia_label.clip_text = true
	_dia_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dia_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dia_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_dia_label)

	# 6) 설정 버튼 = 바 오른쪽 끝. 폭 38px(높이 38과 정사각형). 텍스트 대신 icon_settings 아이콘.
	settings_button.anchor_left = 1.0
	settings_button.anchor_right = 1.0
	settings_button.offset_left = -44.0
	settings_button.offset_right = -6.0
	settings_button.offset_top = bar_top + 4.0
	settings_button.offset_bottom = bar_bottom - 4.0
	_set_button_icon(settings_button, "res://assets/ui/icon/icon_settings.png", 2.0)  # 설정 아이콘은 여백 작게(크게)

	# 6-2) 우편함 버튼 = 설정 바로 왼쪽에 붙임(38px 정사각형, 간격 2 — 우편 끝 314 ↔ 설정 시작 316). 받을 보상 있으면 빨간 점(RedDot).
	#      텍스트 대신 icon_mail 아이콘(설정과 동일 #19 배경 스킨).
	var mail_btn := Button.new()
	mail_btn.focus_mode = Control.FOCUS_NONE
	mail_btn.anchor_left = 1.0
	mail_btn.anchor_right = 1.0
	mail_btn.offset_left = -84.0
	mail_btn.offset_right = -46.0
	mail_btn.offset_top = bar_top + 4.0
	mail_btn.offset_bottom = bar_bottom - 4.0
	UISkin.skin_button(mail_btn, "settings", 3)  # 설정과 같은 #19 배경 스킨(통일감)
	mail_btn.pressed.connect(_on_mailbox_pressed)
	hud.add_child(mail_btn)
	_set_button_icon(mail_btn, "res://assets/ui/icon/icon_mail.png")
	_mail_button = mail_btn  # 튜토리얼 중 비활성화용
	_mail_dot = RedDotScript.new()
	mail_btn.add_child(_mail_dot)  # 아이콘 뒤에 add → 빨간 점이 아이콘 위에 그려짐

	# 6-3) 퀘스트 버튼 = 설정 버튼 바로 아래(우측 정렬, 상단 바 아래). 받을 일일 퀘스트 있으면 빨간 점.
	#      **배경 없이 icon_quest 아이콘만**(메일·설정과 달리 #19 배경 스킨 안 씀 — 사용자 요청). 38×38 클릭영역. ⚠️ 위치 잠정.
	var quest_btn := Button.new()
	quest_btn.focus_mode = Control.FOCUS_NONE
	quest_btn.flat = true  # 배경 없음(투명)
	var quest_empty := StyleBoxEmpty.new()
	for quest_state in ["normal", "hover", "pressed", "focus", "disabled"]:
		quest_btn.add_theme_stylebox_override(quest_state, quest_empty)  # 모든 상태 배경 제거(완전 투명)
	quest_btn.anchor_left = 1.0
	quest_btn.anchor_right = 1.0
	quest_btn.offset_left = -46.0
	quest_btn.offset_right = -6.0
	quest_btn.offset_top = bar_bottom + 4.0
	quest_btn.offset_bottom = bar_bottom + 44.0
	quest_btn.pressed.connect(_on_quest_pressed)
	hud.add_child(quest_btn)
	_set_button_icon(quest_btn, "res://assets/ui/icon/icon_quest.png", 2.0)  # 여백 2 → 아이콘 36px(40×40 버튼)
	_quest_button = quest_btn
	_quest_dot = RedDotScript.new()
	quest_btn.add_child(_quest_dot)  # 아이콘 뒤에 add → 빨간 점이 아이콘 위에 그려짐

	# 7) 라벨·버튼을 칩 위로(z-order)
	hud.move_child(gold_label, hud.get_child_count() - 1)
	hud.move_child(account_label, hud.get_child_count() - 1)
	hud.move_child(settings_button, hud.get_child_count() - 1)
	hud.move_child(mail_btn, hud.get_child_count() - 1)
	hud.move_child(quest_btn, hud.get_child_count() - 1)


func _build_hp_bar() -> void:
	# 좌상단 HUD PC 체력바: 게이지 바 공용 구조(_build_masked_bar) + 녹색. HP 비율만큼 노출.
	var holder := Control.new()
	holder.offset_left = 8.0
	holder.offset_top = 5.0
	holder.offset_right = 204.0
	holder.offset_bottom = 27.0
	$TopHUD.add_child(holder)
	_hp_mask = _build_masked_bar(holder)
	_update_hp_hud()


func _build_masked_bar(holder: Control) -> ColorRect:
	# 게이지 바 공용(스테이지 진행·HUD HP): holder 안에 #24 초록 바(균일 스트레치) + 초록 채움 영역(분수 anchor) inner
	# + 어두운 마스크. 마스크 노드를 반환 → 호출부가 mask.anchor_left = 진행도/HP비율 로 갱신.
	# 분수 anchor = #24 아트 초록 bbox(tools/scan_bar): x[5..459]/465, y[5..21]/27 (캡 5px 대칭).
	# ⚠️ 세로 nudge: 초록은 비트맵(27px→holder nearest 스케일), 마스크는 벡터라 래스터화에서 마스크가 ~1px
	#    위로 떠 보였음(하단 초록 노출/상단 마스크 튐). inner를 MASK_Y_NUDGE만큼 아래로 내려 초록 밴드에 맞춘다.
	const G_L := 5.0 / 465.0
	const G_R := 460.0 / 465.0
	const G_T := 5.0 / 27.0
	const G_B := 22.0 / 27.0
	const MASK_Y_NUDGE := 1.0  # px. 마스크를 초록 밴드에 정렬(아래로). 정렬이 안 맞으면 이 값만 조정.
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var atex := AtlasTexture.new()
	atex.atlas = load(UISkin.SHEET)
	atex.region = UISkin.R_BAR_FILL
	var green := TextureRect.new()
	green.texture = atex
	green.modulate = Color(1.3, 1.65, 1.25)  # 초록을 더 밝고 선명하게(#24 아트 자체보다 밝게). 밝기 조정은 이 값.
	green.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	green.stretch_mode = TextureRect.STRETCH_SCALE
	green.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	green.anchor_right = 1.0
	green.anchor_bottom = 1.0
	green.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(green)
	var inner := Control.new()
	inner.anchor_left = G_L
	inner.anchor_right = G_R
	inner.anchor_top = G_T
	inner.anchor_bottom = G_B
	inner.offset_left = -1.0                # 좌 1px 확장 (살짝 비어 보이던 것 보정)
	inner.offset_right = 1.0                # 우 1px 확장
	inner.offset_top = MASK_Y_NUDGE - 1.0   # 상단 1px 확장(위로)
	inner.offset_bottom = MASK_Y_NUDGE      # 하단은 기존 nudge 유지
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.clip_contents = true
	holder.add_child(inner)
	var mask := ColorRect.new()
	mask.color = Color(0.05, 0.05, 0.06, 0.92)
	mask.anchor_right = 1.0
	mask.anchor_bottom = 1.0
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(mask)
	return mask


func _set_bar_fill(mask: ColorRect, ratio: float) -> void:
	# 마스크 바 채움: 진행도/HP 비율만큼 마스크를 왼쪽부터 걷음(anchor_left=비율). null-safe.
	if mask == null:
		return
	mask.anchor_left = clampf(ratio, 0.0, 1.0)
	mask.offset_left = 0.0


func _update_hp_hud() -> void:
	_set_bar_fill(_hp_mask, player_hp / max(1.0, player_max_hp))


func _build_nav_dock() -> void:
	# 강화/장비/유물/던전/상점 탭 바. 던전은 준비중 토스트(주요 컨텐츠 예정), 나머지는 동작.
	# 전투 영역과 스크래치 사이(상단 고정 밴드)에 배치한다.
	_nav = NavDockScript.new()
	add_child(_nav)  # _ready가 기본은 하단 앵커 → 아래서 상단 밴드로 덮어씀
	_nav.anchor_top = 0.0
	_nav.anchor_bottom = 0.0
	_nav.offset_top = NAV_TOP_Y
	_nav.offset_bottom = NAV_TOP_Y + NavDock.HEIGHT
	_nav.tab_selected.connect(_on_nav_tab)


func _on_nav_tab(id: String) -> void:
	# 던전 전투 중엔 메뉴 탭 전부 비활성(강화/장비 등) — 보스전 회복 규칙(in_boss)으로 인한 혼란 방지(2026-06-18 사용자 결정 C).
	# 던전 종료(입구 복귀) 후 정상. 음영은 _update_nav_tab_locks 가 표시.
	if _mode == Mode.DUNGEON:
		Audio.play_sfx("button")
		NotificationManager.info("던전 전투 중에는 사용할 수 없습니다")
		return
	# 튜토리얼 중엔 강화 유도(UPGRADE) 단계의 강화 탭만 허용. 그 전(SCRATCH/JACKPOT)엔 전부 차단(음영).
	if _tut != Tut.OFF and not (id == "upgrade" and _tut == Tut.UPGRADE):
		return
	match id:
		"upgrade":
			_on_upgrade_pressed()              # 강화만 튜토리얼 종료 훅 때문에 별도 경유
		"relic":
			# 유물 탭은 스테이지 10 클리어 전 잠금(음영). 진입 시도 시 안내 토스트.
			if not BackendService.relic_unlocked():
				Audio.play_sfx("button")
				NotificationManager.info("스테이지 10을 클리어하면 열립니다")
				return
			UIManager.open(id)
		"dungeon":
			# 던전도 스테이지 10 클리어 전 잠금(유물과 동일 기준).
			if not BackendService.dungeon_unlocked():
				Audio.play_sfx("button")
				NotificationManager.info("스테이지 10을 클리어하면 열립니다")
				return
			UIManager.open(id)
		"equip", "shop":
			UIManager.open(id)                 # 장비/상점 — UIManager가 상호배타 오픈 소유
		_:
			# 모험 등 = 준비 중.
			Audio.play_sfx("button")
			NotificationManager.info("준비 중입니다")


# --------- 내비 밴드 패널 (UIManager 등록) ---------
# 부착·상호배타 오픈·닫기 배선은 UIManager(autoload)가 소유하고, 패널 변동 통지는 Events(전역 버스)로 받는다.
# (구 _add_band_panel/_open_nav_panel/_hide_nav_panels → UIManager.register_band_panel/open/hide_all 로 이동.)

func _build_nav_panels() -> void:
	var band_top: float = NAV_TOP_Y + NavDock.HEIGHT  # 내비 바 바로 아래 ~ 화면 바닥(스크래치 영역만 덮음)
	_upgrade_panel = UIManager.register_band_panel("upgrade", UpgradePanelScript.new(), self, band_top)
	_shop_panel = UIManager.register_band_panel("shop", ShopPanelScript.new(), self, band_top)
	_equipment_panel = UIManager.register_band_panel("equip", EquipmentPanelScript.new(), self, band_top)
	_relic_panel = UIManager.register_band_panel("relic", RelicPanelScript.new(), self, band_top)
	_dungeon_panel = UIManager.register_band_panel("dungeon", DungeonPanelScript.new(), self, band_top)
	# 패널 → 게임 반응은 Events 구독으로 (패널은 game.gd 를 모름)
	Events.upgrade_purchased.connect(_on_upgrade_purchased)
	Events.currency_changed.connect(_refresh_hud)
	Events.equipment_changed.connect(_on_equipment_changed)
	Events.relics_changed.connect(_on_relic_changed)
	Events.dungeon_enter_requested.connect(_on_dungeon_enter_requested)


func _on_equipment_changed() -> void:
	# 장비 장착/강화/합성 → 최대 체력(방어구) 재계산 + HUD 갱신.
	# (공격력 무기 보너스는 _attack_power로 매 공격마다 라이브 반영되므로 별도 처리 불필요)
	player_max_hp = _max_hp()
	# 최대 HP가 늘면 현재 HP도 채운다 — 강화 hp 구매(_apply_upgrade_stats reset_hp)와 동일하게
	# 보스전이 아니면 상한까지 풀충전. 보스전 중엔 상한만 갱신(+ 상한 하향 시 clamp)으로
	# 보스전 회복 금지와 일관(2026-06-15 결정: 장비도 강화처럼 풀충전, 보스전 제외).
	if not in_boss:
		player_hp = player_max_hp
	else:
		player_hp = min(player_hp, player_max_hp)
	player.set_max_hp(player_max_hp)
	player.set_hp(player_hp)  # 현재 HP가 바뀌었으니 머리 위 바도 즉시 동기화
	_refresh_hud()


func _on_relic_changed() -> void:
	# 유물 장착/해제/뽑기 → ①분포·④와일드 즉시 반영 + HUD 갱신.
	# (⑤보정·②확장은 스킬 적중 시 라이브 계산되므로 별도 처리 불필요)
	_apply_scratch_numbers()
	if scratch_card != null and not scratch_card.is_locked:
		scratch_card.reset_card()
	_refresh_hud()


func _on_upgrade_pressed() -> void:
	# "강화" 버튼 — 튜토리얼 3단계 종료 훅 후 패널 표시(refresh는 upgrade_panel.open() 안에서).
	if _tut == Tut.UPGRADE:
		_end_tutorial()  # 튜토리얼 3단계 종료 → 정상 게임 재개
	UIManager.open("upgrade")


func _attack_power() -> float:
	# 캐릭터 공격력 = 강화(골드 트랙) × (1 + 장착 무기 보너스). 자동·스킬 공용.
	return Upgrades.value("attack") * (1.0 + BackendService.equipped_bonus("weapon"))


func _max_hp() -> float:
	# 최대 체력 = 강화 hp 트랙 × (1 + 장착 방어구 보너스).
	return Upgrades.value("hp") * (1.0 + BackendService.equipped_bonus("armor"))


func _restore_full_hp(sync_player_bar: bool = true) -> void:
	# PC HP 풀충전(상한 재계산 포함). sync_player_bar=false 면 멤버만 갱신(시각 동기화는 호출부 후속 코드가 수행).
	player_max_hp = _max_hp()
	player_hp = player_max_hp
	if sync_player_bar:
		player.set_max_hp(player_max_hp)
		player.set_hp(player_hp)


func _effective_auto_rate() -> float:
	# 자동긁기 유효 속도 — 치트(_cheat_auto_rate>0) 우선, 아니면 강화값.
	# ⚠️ _setup_scratch_card_layout/_apply_upgrade_stats/_end_tutorial 은 의도적으로 이 헬퍼를 안 씀
	#    (현행 동작 = 강화 구매·튜토 종료 시 치트 속도를 강화값으로 복귀). 통일하려면 별도 결정 필요.
	return _cheat_auto_rate if _cheat_auto_rate > 0.0 else Upgrades.value("auto_speed")


func refresh_auto_rate_live() -> void:
	# 자동긁기 유효 속도 변경(치트 토글 등) 직후 즉시 반영 — 교전 idle 중일 때만(run/튜토리얼은 다음 _enter_idle 에서).
	if _tut == Tut.OFF and pc_state == PcState.IDLE:
		scratch_card.auto_rate = _effective_auto_rate()


func _apply_upgrade_stats(reset_hp: bool) -> void:
	# 강화 값(HP 상한·자동긁기속도·브러시 범위)을 라이브 상태에 즉시 반영.
	# reset_hp=true면 보스전이 아닐 때 현재 HP를 상한까지 회복(구매·치트 부스트).
	# cheat_controller._wipe 는 reset_hp=false(현재 HP 미변경 — 직후 _goto_stage가 스폰 처리).
	player_max_hp = _max_hp()
	if reset_hp and not in_boss:
		player_hp = player_max_hp
	scratch_card.auto_rate = Upgrades.value("auto_speed")
	scratch_card.brush_radius = Upgrades.value("brush")


func _on_upgrade_purchased() -> void:
	# HP 상한 등 즉시 반영. (전투력은 다음 공격 계산 시 Upgrades.value로 자동 반영)
	_apply_upgrade_stats(true)
	_refresh_hud()


# --------- 튜토리얼 (첫 시작, 스크립트형) ---------

func _start_tutorial() -> void:
	# 1단계 시작: 상단 배너 + 자동긁기 OFF. 적은 _spawn_next가 고HP로 스폰(한 방에 안 죽음).
	_tut = Tut.SCRATCH
	_set_tutorial_ui_lock(true)  # 강화 외 UI 잠금(우편·설정 비활성, 내비 비강화 탭 차단)
	_tut_banner = TutorialOverlayScript.new()
	add_child(_tut_banner)  # 다른 패널보다 나중에 add → 위에 표시
	_tut_set_banner(TUT_MSG_1)


func _set_tutorial_ui_lock(locked: bool) -> void:
	# 튜토리얼 중 강화 외 UI 잠금. 우편·설정 버튼을 비활성(disabled)하고, 내비 도크의 비강화 탭은
	# _on_nav_tab 가 무시한다(강화 탭만 통과 — 튜토리얼 3단계가 강화 유도라서).
	# (치트 버튼은 dev 전용이라 잠그지 않음.)
	var tint: Color = Color(0.5, 0.5, 0.5) if locked else Color(1, 1, 1)  # 비활성 시각 피드백(자식 아이콘·dot도 상속)
	if _mail_button != null:
		_mail_button.disabled = locked
		_mail_button.modulate = tint
	if settings_button != null:
		settings_button.disabled = locked
		settings_button.modulate = tint
	if _quest_button != null:
		_quest_button.disabled = locked
		_quest_button.modulate = tint
	if _quest_tracker != null:
		_quest_tracker.visible = not locked  # 튜토리얼 중 메인 트래커 숨김(해제 후 _refresh_hud가 상태 반영)
	_update_nav_guide_dots()  # _tut 상태를 내비 가이드 dot에 즉시 반영(튜토리얼 시작 시 끄고, 종료 시 다시 평가)


func _tut_set_banner(msg: String) -> void:
	if _tut_banner != null:
		_tut_banner.set_text(msg)


func _tutorial_mob_hp() -> int:
	# 강화 Lv0에서 나올 수 있는 최고 한 방(잭팟) 데미지보다 높게 → 1단계 적이 한 방에 안 죽는다.
	var max_dmg: float = Upgrades.value("attack") * Upgrades.value("card_mult") * float(TUT_JACKPOT_MULT)
	return int(ceil(max_dmg * 1.5)) + 1


func _enter_tut_jackpot() -> void:
	# 1단계 완료(긁어서 공격함) → 2단계: 다음 카드를 강제 잭팟(모두 9)으로.
	_tut = Tut.JACKPOT
	_tut_set_banner(TUT_MSG_2)
	scratch_card.set_number_pool([9])  # 모든 칸 9 → 완성 시 잭팟
	scratch_card.reset_card()


func _play_death_fx(enemy: Control, shrink: bool) -> void:
	# 적 사망 폭발 연출: 폭발 + 본체 페이드아웃(+선택적 축소) → queue_free. (일반 처치=축소O, 튜토리얼=축소X)
	Effects.spawn_explosion(arena, enemy.position + ENEMY_EXPLOSION_OFFSET)
	var tw := create_tween().set_parallel(true)
	if shrink:
		enemy.pivot_offset = enemy.size * 0.5
		tw.tween_property(enemy, "scale", enemy.scale * 0.4, 0.2)
	tw.tween_property(enemy, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(enemy.queue_free)


func _on_tut_enemy_killed(enemy: Control) -> void:
	# 2단계 잭팟으로 적 강제 처치됨 → 칭찬 문구 → 잠시 후 3단계(강화 유도).
	_lock_card()
	_play_death_fx(enemy, false)  # 튜토리얼: 축소 없이 페이드만
	current_enemy = null
	_tut_set_banner(TUT_PRAISE)
	await get_tree().create_timer(TUT_PRAISE_DURATION).timeout
	if is_inside_tree() and _tut == Tut.JACKPOT:
		_enter_tut_upgrade()


func _enter_tut_upgrade() -> void:
	# 3단계: 강화 유도. 숫자 분포 정상 복귀 + 강화 버튼 강조. 적은 스폰하지 않는다(전투 종료).
	_tut = Tut.UPGRADE
	_tut_set_banner(TUT_MSG_3)
	_apply_scratch_numbers()  # 강제 잭팟 풀 해제 → 정상 분포
	_start_upgrade_blink()


func _start_upgrade_blink() -> void:
	_stop_upgrade_blink()
	var btn: Button = _nav.get_button("upgrade") if _nav != null else null
	if btn == null:
		return
	_tut_blink = create_tween().set_loops()
	_tut_blink.tween_property(btn, "modulate", Color(1.6, 1.6, 0.6), 0.5)
	_tut_blink.tween_property(btn, "modulate", Color(1, 1, 1), 0.5)


func _stop_upgrade_blink() -> void:
	if _tut_blink != null:
		_tut_blink.kill()
		_tut_blink = null
	if _nav != null:
		var btn: Button = _nav.get_button("upgrade")
		if btn != null:
			btn.modulate = Color(1, 1, 1)


func _end_tutorial() -> void:
	# 3단계 종료(강화 버튼 클릭): 배너·강조 제거, 자동긁기 복원, 정상 게임 재개.
	_tut = Tut.OFF
	_set_tutorial_ui_lock(false)  # 잠갔던 UI(우편·설정·내비 비강화 탭) 복원
	_stop_upgrade_blink()
	if _tut_banner != null:
		_tut_banner.queue_free()
		_tut_banner = null
	scratch_card.auto_rate = Upgrades.value("auto_speed")
	_apply_scratch_numbers()
	_enter_run()
	_spawn_next()


# --------- 설정 (계정 메뉴) ---------
# 방치형이라 일시정지는 없다. 설정 패널은 게임 진행 위에 겹쳐 뜨는 계정 메뉴.

func _build_settings_panel() -> void:
	# 설정(계정 메뉴) 오버레이 — UIManager 오버레이로 등록(부착·닫기 배선 위임), 계정 시그널만 여기서 연결.
	_settings_panel = UIManager.register_overlay("settings", SettingsPanelScript.new(), self)
	_settings_panel.main_menu_pressed.connect(_on_main_menu_pressed)
	_settings_panel.logout_pressed.connect(_on_logout_pressed)
	_settings_panel.delete_account_pressed.connect(_on_delete_account_pressed)


func _on_settings_pressed() -> void:
	# "설정" 버튼 → UIManager 오버레이 오픈(sfx+refresh+표시는 open_overlay/open()이 수행).
	UIManager.open_overlay("settings")


# --------- 우편함 (보상 수령식 통로) ---------

func _build_mailbox_panel() -> void:
	# 우편함 오버레이 — UIManager 오버레이로 등록(설정/치트와 같은 독립 전체화면).
	_mailbox_panel = UIManager.register_overlay("mailbox", MailboxPanelScript.new(), self)


func _on_mailbox_pressed() -> void:
	UIManager.open_overlay("mailbox")


# --------- 퀘스트 (단기 목표 + 수령식 보상) ---------

func _build_quest_panel() -> void:
	# 일일 퀘스트 오버레이 — UIManager 오버레이로 등록(우편함/설정과 같은 독립 전체화면).
	_quest_panel = UIManager.register_overlay("quest", QuestPanelScript.new(), self)


func _build_quest_tracker() -> void:
	# 메인 퀘스트 HUD 트래커 — 우측 하단(내비 도크 바로 위). 다음 미수령 메인 퀘 1개만 상시 표시.
	# (완료 시 클릭→수령→즉시 다음 노출, 전부 수령 시 숨김.)
	# ⚠️ 오버레이(설정/우편/일일)보다 **먼저** add 해야 그 dim 이 트래커를 덮는다(_ready에서 _build_nav_panels 다음 호출).
	_quest_tracker = QuestTrackerScript.new()
	add_child(_quest_tracker)
	_quest_tracker.anchor_left = 1.0
	_quest_tracker.anchor_right = 1.0
	_quest_tracker.anchor_top = 0.0
	_quest_tracker.anchor_bottom = 0.0
	_quest_tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_quest_tracker.offset_left = -158.0
	_quest_tracker.offset_right = -8.0
	_quest_tracker.offset_top = NAV_TOP_Y - 66.0
	_quest_tracker.offset_bottom = NAV_TOP_Y - 8.0
	# 트래커 우상단 모서리 빨간 점 — 메인 퀘 완료(받기 가능) 시 표시(우편/일일 퀘 버튼과 동일 컨벤션).
	# 트래커는 PanelContainer(자식 anchor 무시)라 닷을 자식으로 못 넣음 → 같은 부모에 sibling 으로 모서리에 얹는다.
	# (트래커보다 뒤에 add → 위에 그려짐. 트래커와 함께 오버레이 dim 에 덮임.)
	_quest_main_dot = RedDotScript.new()
	add_child(_quest_main_dot)
	var dot_sz: float = 12.0
	_quest_main_dot.anchor_left = 1.0
	_quest_main_dot.anchor_right = 1.0
	_quest_main_dot.anchor_top = 0.0
	_quest_main_dot.anchor_bottom = 0.0
	_quest_main_dot.offset_left = -8.0 - dot_sz + 4.0   # 트래커 우측 끝(-8) 안쪽, 모서리에 살짝 걸침
	_quest_main_dot.offset_right = -8.0 + 4.0
	_quest_main_dot.offset_top = (NAV_TOP_Y - 66.0) - 4.0
	_quest_main_dot.offset_bottom = (NAV_TOP_Y - 66.0) - 4.0 + dot_sz


func _on_quest_pressed() -> void:
	UIManager.open_overlay("quest")


func _on_main_menu_pressed() -> void:
	# 메인 메뉴(login.tscn = 계정 선택/변경). 진행은 영구 저장이라 폐기 없음.
	BackendService.flush()
	_goto_scene("res://scenes/login.tscn")


func _on_logout_pressed() -> void:
	BackendService.flush()
	BackendService.logout()  # → logged_out → _return_to_login


func _on_delete_account_pressed() -> void:
	BackendService.delete_account()  # → account_deleted → _return_to_login


# --------- 치트 (개발용) ---------
# 치트 버튼/패널/동작 일체는 cheat_controller.gd 로 분리(2026-06-11 god object 티어2 — CHEAT_ENABLED +
# 디버그 빌드일 때 _ready 가 생성). game 에는 _cheat_auto_rate 상태와 refresh_auto_rate_live() 훅만 남는다.


# --------- 씬 전환 / 공통 ---------

func _clear_arena_effects() -> void:
	# arena의 일시적 이펙트 노드(피격 플로터·버스트 등 Label/ColorRect) 정리.
	# 지속 노드(Player=AnimatedSprite2D, HP바=ProgressBar)는 Label/ColorRect가 아니라 안전.
	for child in arena.get_children():
		if child is Label or child is ColorRect:
			child.queue_free()


func _goto_scene(path: String) -> void:
	# 씬 전환 — 공용 SceneNav 위임(login.gd와 중복 제거).
	SceneNav.goto_scene(get_tree(), path)


func _return_to_login() -> void:
	# 로그아웃/계정 탈퇴 완료 시그널 → 로그인 화면 복귀.
	_goto_scene("res://scenes/login.tscn")


func _build_stage_banner() -> void:
	# 상단 스테이지 배너: 대비용 배경 칩 + 스테이지 이름(그림자) + 진행 바 + BOSS 배지.
	# (레퍼런스 상단의 스테이지명+진행바 구조. 라벨이 하늘 배경에 묻히는 문제도 칩/그림자로 해결.)
	var hud: Control = $TopHUD

	# 스테이지 이름 프레임 = #2 버튼형 9-slice 패널. 스테이지 글자를 이 안에 중앙 배치.
	var chip := Panel.new()
	chip.anchor_left = 0.5
	chip.anchor_right = 0.5
	chip.offset_left = -108.0
	chip.offset_right = 108.0
	chip.offset_top = 58.0   # 상단 바(#23, y6~52) 아래로
	chip.offset_bottom = 102.0
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UISkin.header())
	hud.add_child(chip)
	hud.move_child(chip, 0)  # 라벨/바보다 뒤로

	# 스테이지 라벨 = #2 프레임 안에 가로·세로 중앙 정렬(그림자로 대비).
	stage_label.anchor_left = 0.5
	stage_label.anchor_right = 0.5
	stage_label.offset_left = -100.0
	stage_label.offset_right = 100.0
	stage_label.offset_top = 58.0
	stage_label.offset_bottom = 102.0
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Effects.apply_label_shadow(stage_label, 0.85, 1)

	_boss_badge = Label.new()
	_boss_badge.text = "BOSS"
	_boss_badge.anchor_left = 0.5
	_boss_badge.anchor_right = 0.5
	_boss_badge.offset_left = 112.0
	_boss_badge.offset_right = 178.0
	_boss_badge.offset_top = 62.0
	_boss_badge.offset_bottom = 88.0
	_boss_badge.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	Effects.apply_label_shadow(_boss_badge, 0.85, 1)
	_boss_badge.add_theme_font_size_override("font_size", 14)
	_boss_badge.visible = false
	_boss_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_boss_badge)

	# 스테이지 진행 바: 게이지 바 공용 구조(_build_masked_bar) — #24 초록 + 마스크, 진행도만큼 왼쪽부터 노출.
	var bar_holder := Control.new()
	bar_holder.anchor_left = 0.5
	bar_holder.anchor_right = 0.5
	bar_holder.offset_left = -98.0
	bar_holder.offset_right = 98.0
	bar_holder.offset_top = 112.0
	bar_holder.offset_bottom = 127.0  # 절반 두께(높이 15), 기존 위치 중앙 유지
	hud.add_child(bar_holder)
	_bar_mask = _build_masked_bar(bar_holder)


func _refresh_hud() -> void:
	# 상단 HUD 갱신: 골드 + 스테이지명 + 진행 바(잡몹 진행도/보스 빨강) + BOSS 배지.
	gold_label.text = _fmt(BackendService.get_gold())  # 좌측 아이콘 + 숫자(노란색)
	if _dia_label != null:
		_dia_label.text = _fmt(BackendService.get_dia())  # 좌측 아이콘 + 숫자(하늘색)
	if _mail_dot != null:
		_mail_dot.set_active(MailboxScript.has_claimable(BackendService.get_mail_claimed()))  # 받을 우편 있으면 빨간 점
	if _quest_dot != null:
		# 상단 "퀘스트"(일일 패널) 버튼 red dot = 받을 일일 퀘스트 있을 때만. 메인은 트래커가 자체 "받기!" 표시.
		_quest_dot.set_active(QuestsScript.has_claimable_daily(
			BackendService.get_stats(), BackendService.get_quests_daily_base(),
			BackendService.get_quests_daily_claimed()))
	if _quest_tracker != null:
		# 메인 퀘스트 트래커 갱신(진행도/완료). _refresh_hud는 처치/골드마다 호출돼 완료 즉시 반영.
		# 튜토리얼 중엔 숨김(스크래치/강화 집중).
		if _tut == Tut.OFF:
			_quest_tracker.refresh()
		else:
			_quest_tracker.visible = false
	if _quest_main_dot != null:
		# 트래커가 보이고 + 현재 메인 퀘가 받기 가능(완료)일 때만 빨간 점(우편/일일 퀘 닷과 동일).
		_quest_main_dot.set_active(_quest_tracker != null and _quest_tracker.visible and _quest_tracker.is_claimable())
	_update_hp_hud()
	if _mode == Mode.DUNGEON:
		_update_dungeon_hud()  # 던전 배너(N층 + 타이머) + 게이지(남은 시간/가득)
	else:
		var is_boss: bool = Balance.is_boss_stage(stage)
		stage_label.text = "스테이지 %d" % stage
		if _boss_badge != null:
			_boss_badge.visible = is_boss
		# 진행도만큼 마스크를 왼쪽부터 걷음. 클리어 직후/보스전은 가득(진행도 1.0).
		var prog: float = 1.0 if (_show_full_gauge or is_boss) else float(mobs_killed_in_stage) / float(max(1, Balance.MOBS_PER_STAGE))
		_set_bar_fill(_bar_mask, prog)
	# 강화 패널이 열려 있으면 같이 갱신 — _refresh_hud 는 처치(골드 변동)마다 호출되므로,
	# 실시간 골드 수입에 맞춰 구매 버튼 활성(can_afford)이 즉시 켜진다(패널 닫혀 있으면 skip).
	if _upgrade_panel != null and _upgrade_panel.visible:
		_upgrade_panel.refresh()
	# 장비 패널도 동일 — 단 refresh()는 리스트 전체 재구성(스크롤 리셋)이라, 강화 버튼 활성만
	# 제자리 갱신하는 가벼운 refresh_affordability() 사용(매 처치 호출 안전).
	if _equipment_panel != null and _equipment_panel.visible:
		_equipment_panel.refresh_affordability()
	_update_nav_guide_dots()


func _update_nav_guide_dots() -> void:
	# 유물 가벼운 가이드(red dot): 무료 확정 소환 대기 → 상점 탭 / 미장착 유물(빈 슬롯) → 유물 탭.
	# 튜토리얼 중엔 내비가 잠겨 있으므로 표시 안 함.
	if _nav == null:
		return
	var show: bool = _tut == Tut.OFF
	_update_nav_tab_locks()  # 탭 음영(튜토리얼 단계 + 유물 스테이지 10 게이트)
	_nav.set_red_dot("shop", show and BackendService.relic_free_pulls_left() > 0)
	_nav.set_red_dot("relic", show and _has_unequipped_relic())


func _update_nav_tab_locks() -> void:
	# 내비 탭 음영(잠금) 갱신 — 던전 전투 중 / 튜토리얼 단계 + 유물(스테이지 10) 게이트.
	#  · 던전 전투 중(_mode==DUNGEON): 모든 탭 음영(전투 중 메뉴 금지 — _on_nav_tab 가 차단).
	#  · 튜토리얼 SCRATCH/JACKPOT: 모든 탭 음영(아직 아무 메뉴도 못 엶).
	#  · 튜토리얼 UPGRADE: 강화만 강조(blink 가 modulate 소유 → 여기선 안 건드림), 나머지 음영.
	#  · 튜토리얼 종료(OFF): 강화/장비/상점 정상, 유물·던전은 스테이지 10 클리어 전까지 음영 유지.
	if _nav == null:
		return
	if _mode == Mode.DUNGEON:
		for t in ["upgrade", "equip", "relic", "dungeon", "shop"]:
			_nav.set_locked(t, true)
		return
	var in_tut: bool = _tut != Tut.OFF
	_nav.set_locked("equip", in_tut)
	_nav.set_locked("shop", in_tut)
	_nav.set_locked("relic", in_tut or not BackendService.relic_unlocked())
	_nav.set_locked("dungeon", in_tut or not BackendService.dungeon_unlocked())  # 던전도 스테이지 10 게이트
	# 강화 탭: UPGRADE 단계는 blink 가 modulate 를 소유하므로 제외, 그 외엔 튜토리얼 중이면 음영.
	if _tut != Tut.UPGRADE:
		_nav.set_locked("upgrade", in_tut)


func _has_unequipped_relic() -> bool:
	# 보유 유물 중 슬롯에 안 낀 게 있고, 빈 슬롯이 남았으면 true(장착 유도).
	var equipped: int = BackendService.get_relic_slots().size()
	if equipped >= BackendService.relic_slot_count():
		return false
	return BackendService.get_relics().size() > equipped


func _refresh_account_label() -> void:
	# 상단 계정 표시: 게스트면 "게스트", 인증이면 "이름 (google/kplay)".
	var who: String
	if BackendService.is_guest():
		who = "게스트"
	else:
		var nm: String = BackendService.user_name
		who = "%s (%s)" % [nm if nm != "" else "?", BackendService.account_type]
	account_label.text = who


func _fmt(n: float) -> String:
	# 재화 포맷 단일 출처(UISkin.fmt_currency)에 위임 — HUD·패널 전부 같은 정책("10억부터 K").
	return UISkin.fmt_currency(n)
