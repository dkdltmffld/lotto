class_name PlayerData
extends RefCounted

# PC 이동 속도 (run 상태, px/sec). 기획서 3.
# ⚠️ [2026-06-19 빠른 이동감] run 속도·웨이브 간격·스폰 진입거리를 같은 배율 K(=1.5)로 함께 키웠다.
#   목적 = "화면 이동은 더 빠르게, 이동 시간(=플레이 호흡)은 불변"(run 시간 = 거리/속도, 고정 타이머 없음).
#   한 묶음(K 바꾸면 셋 다): RUN_SPEED(여기) · game.gd WAVE_SPACING · EnemyData.SPAWN_OFFSET_FROM_RIGHT.
const RUN_SPEED: float = 225.0  # = 150 × 1.5

# PC 화면상 위치/크기.
# HOME_X: PC가 보이는 가로 좌표 (Arena 좌상단 기준). attack 모션의 잽도 이 값 기준으로 계산.
# Y_FROM_BOTTOM: PC 중심 y (Arena 하단 기준 위로 N px). 비율 변경 시 자동 적응.
# VISUAL_SCALE: 스프라이트 텍스처 다운스케일 (256×256 텍스처 × 0.4 = 화면상 ≈102×102).
const HOME_X: float = 80.0
const Y_FROM_BOTTOM: float = 82.0
const VISUAL_SCALE: float = 0.4

# 스프라이트 시트의 프레임 한 칸 크기 (정사각형).
# 프레임 개수는 시트마다 다를 수 있으므로 자동으로 (텍스처 width / FRAME_SIZE)로 계산한다.
const FRAME_SIZE: int = 256

# PC 상태 → 스프라이트 매핑. 기획서 2-1.
# 두 포맷 지원:
#   ① 가로 시트  "path": 단일 PNG, width = FRAME_SIZE × 프레임수, height = FRAME_SIZE (idle/run/attacked/dead)
#   ② 포즈 파일  "pose_base": 키포즈 개별 PNG. {base}_0.png, _1.png, … 순서대로 로드(0=시작, 증가=뒤 포즈).
#                각 파일 = 한 프레임 전체(고해상도 가능, FRAME_SIZE 무관). 무기 분리용 빈손 attack 포즈가 이 방식. [[reference_sprite_naming]]
const ANIMATIONS: Dictionary = {
	"idle": {
		"path": "res://assets/sprites/player/PC_idle.png",
		"speed": 10.0,
		"loop": true,
	},
	"run": {
		"path": "res://assets/sprites/player/PC_run_v2.png",
		"speed": 18.0,  # = 12 × 1.5 — RUN_SPEED를 ×1.5 했으므로 다리 사이클도 맞춰 빠르게(발 미끄러짐 완화). 시각 케이던스라 호흡과 무관.
		"loop": true,
	},
	"attack": {
		# idle 기준으로 재제작한 빈손 포즈 — _0(와인드업) · _1(타격). 무기는 PlayerController가 별도 렌더.
		"pose_base": "res://assets/sprites/player/PC_attack_02",
		"speed": 24.0,  # 빠른 스윙(전진에 모션 안 끊기게). 너무 빠르면 이 값만 낮추면 됨.
		"loop": false,
	},
	"attacked": {
		"path": "res://assets/sprites/player/PC_attacked.png",
		"speed": 14.0,
		"loop": false,
	},
	"dead": {
		"path": "res://assets/sprites/player/PC_dead.png",
		"speed": 12.0,
		"loop": false,
	},
}
