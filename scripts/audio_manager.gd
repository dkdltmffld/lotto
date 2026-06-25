extends Node

# 오디오 매니저 (autoload "Audio"). 효과음(SFX)/배경음(BGM) 재생 + 볼륨/음소거 설정.
#
# ⚠️ 더미 단계: 실제 사운드 파일은 아직 없다. 카탈로그 경로에 파일이 있으면 재생하고,
#    없으면 조용히 skip(에러 없음). 나중에 assets/audio/{sfx,bgm}/*.ogg 를 넣기만 하면
#    코드 수정 없이 자동으로 울린다. 코어 로직에는 이미 play_sfx/play_bgm 훅이 박혀 있다.
#
# HTML5(웹) 제약(CLAUDE.md):
#   - 포맷은 Ogg Vorbis 권장(MP3 라이선스/디코딩 이슈).
#   - 오디오는 "첫 사용자 제스처" 이후에만 재생 가능(브라우저 autoplay 정책). 본 게임은
#     로그인 화면의 계정 버튼을 누른 뒤 게임 씬에 진입하므로 BGM 시작 시점은 이미 제스처 이후 — 안전.
#   - 스레드 미사용(AudioStreamPlayer는 메인 스레드). 웹 호환.
#
# ⚠️ class_name 없음 — autoload 이름(Audio)과 충돌 방지. 전역 식별자 Audio 로 접근.

const BUS_MASTER := "Master"
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"

const SFX_POOL_SIZE := 8  # 동시 재생용 AudioStreamPlayer 풀 크기(긁기 연타 등 겹침 대비)

# 효과음 카탈로그: key -> 리소스 경로. (파일은 더미 단계라 아직 없을 수 있음 → skip)
const SFX := {
	"scratch": "res://assets/audio/sfx/scratch.ogg",        # 칸 한 개 긁힘(완료)
	"hand": "res://assets/audio/sfx/hand.ogg",              # 카드 완성(족보 성립)
	"jackpot": "res://assets/audio/sfx/jackpot.ogg",        # 잭팟(9칸 동일)
	"attack": "res://assets/audio/sfx/attack.ogg",          # 플레이어 공격 모션
	"hit": "res://assets/audio/sfx/hit.ogg",                # 적 타격
	"kill": "res://assets/audio/sfx/kill.ogg",              # 적 처치
	"boss": "res://assets/audio/sfx/boss.ogg",              # 보스 등장
	"player_hit": "res://assets/audio/sfx/player_hit.ogg",  # 플레이어 피격(보스전)
	"player_dead": "res://assets/audio/sfx/player_dead.ogg",# 플레이어 사망
	"upgrade": "res://assets/audio/sfx/upgrade.ogg",        # 강화 구매
	"reward": "res://assets/audio/sfx/reward.ogg",          # 보상 수령(오프라인/리텐션)
	"button": "res://assets/audio/sfx/button.ogg",          # 버튼 클릭
}

# 배경음 카탈로그: key -> 리소스 경로.
const BGM := {
	"main": "res://assets/audio/bgm/main.ogg",  # 평상시
	"boss": "res://assets/audio/bgm/boss.ogg",  # 보스전(선택)
}

# 설정값(0~1 선형). 영속화는 BackendService settings 에 묶어 저장.
var master_volume: float = 1.0
var bgm_volume: float = 0.8
var sfx_volume: float = 1.0
var muted: bool = false

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_idx: int = 0
var _bgm_player: AudioStreamPlayer = null
var _current_bgm_key: String = ""
var _stream_cache: Dictionary = {}    # path -> AudioStream | null (없는 파일도 null로 캐시해 재시도 방지)
var _missing_warned: Dictionary = {}  # path -> true (없는 파일은 1회만 로그)


func _ready() -> void:
	_ensure_buses()
	# SFX 플레이어 풀
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_sfx_players.append(p)
	# BGM 플레이어
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = BUS_BGM
	add_child(_bgm_player)
	# 저장된 설정 반영: BackendService 로드가 끝났으면 즉시, 아니면 save_ready 후.
	if BackendService.is_ready:
		_load_settings()
	else:
		BackendService.save_ready.connect(_load_settings)
	_apply_volumes()


func _ensure_buses() -> void:
	# Master(index 0)는 항상 존재. BGM/SFX 버스가 없으면 코드로 만들어 Master로 보낸다.
	# (.tres 버스 레이아웃 의존 없이 자기완결 — 웹/이식 안전)
	for bus_name in [BUS_BGM, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)


# ---------- 재생 ----------

func play_sfx(key: String) -> void:
	# 효과음 1회 재생. 풀에서 다음 플레이어를 라운드로빈으로 사용(겹침 허용).
	var path: String = SFX.get(key, "")
	if path == "":
		return
	var stream := _get_stream(path)
	if stream == null:
		return
	var p := _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_players.size()
	p.stream = stream
	p.play()


func play_bgm(key: String) -> void:
	# 배경음 전환(루프). 같은 곡이 이미 재생 중이면 무시.
	if key == _current_bgm_key and _bgm_player != null and _bgm_player.playing:
		return
	_current_bgm_key = key
	var path: String = BGM.get(key, "")
	var stream := _get_stream(path) if path != "" else null
	if stream == null:
		_bgm_player.stop()
		return
	if stream is AudioStreamOggVorbis and not stream.loop:
		stream.loop = true  # 배경음 루프 보장
	_bgm_player.stream = stream
	_bgm_player.play()


func stop_bgm() -> void:
	_current_bgm_key = ""
	if _bgm_player != null:
		_bgm_player.stop()


func _get_stream(path: String) -> AudioStream:
	# 경로의 오디오 스트림을 캐시와 함께 반환. 없으면 null(1회만 로그) — 더미 단계 안전 skip.
	if _stream_cache.has(path):
		return _stream_cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = ResourceLoader.load(path) as AudioStream
	elif not _missing_warned.has(path):
		_missing_warned[path] = true
		print("[Audio] 사운드 파일 없음(더미 단계, skip): %s" % path)
	_stream_cache[path] = stream
	return stream


# ---------- 설정 (볼륨 0~1 / 음소거) ----------

func set_master_volume(v: float) -> void:
	_set_volume_field(&"master_volume", v)


func set_bgm_volume(v: float) -> void:
	_set_volume_field(&"bgm_volume", v)


func set_sfx_volume(v: float) -> void:
	_set_volume_field(&"sfx_volume", v)


func _set_volume_field(field: StringName, v: float) -> void:
	# 볼륨 setter 공용 본문: clamp 후 필드 대입(단순 var라 set() 경유=대입과 동일) → 적용 → 저장.
	set(field, clampf(v, 0.0, 1.0))
	_apply_volumes()
	_save_settings()


func set_muted(m: bool) -> void:
	muted = m
	_apply_volumes()
	_save_settings()


func toggle_muted() -> bool:
	set_muted(not muted)
	return muted


func _apply_volumes() -> void:
	_set_bus_db(BUS_MASTER, master_volume)
	_set_bus_db(BUS_BGM, bgm_volume)
	_set_bus_db(BUS_SFX, sfx_volume)
	var master_idx := AudioServer.get_bus_index(BUS_MASTER)
	if master_idx != -1:
		AudioServer.set_bus_mute(master_idx, muted)


func _set_bus_db(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	# 0이면 사실상 무음(-80db), 그 외엔 선형→데시벨 변환.
	AudioServer.set_bus_volume_db(idx, -80.0 if linear <= 0.0 else linear_to_db(linear))


func _load_settings() -> void:
	# BackendService settings 에서 오디오 값 로드(없으면 기본값 유지).
	var s: Dictionary = BackendService.get_value("settings", {})
	master_volume = float(s.get("audio_master", master_volume))
	bgm_volume = float(s.get("audio_bgm", bgm_volume))
	sfx_volume = float(s.get("audio_sfx", sfx_volume))
	muted = bool(s.get("audio_muted", muted))
	_apply_volumes()


func _save_settings() -> void:
	# 오디오 설정을 settings dict 에 병합 저장(다른 설정 키 보존). 이산 이벤트 → flush.
	if not BackendService.is_ready:
		return
	var s: Dictionary = (BackendService.get_value("settings", {}) as Dictionary).duplicate()
	s["audio_master"] = master_volume
	s["audio_bgm"] = bgm_volume
	s["audio_sfx"] = sfx_volume
	s["audio_muted"] = muted
	BackendService.set_value("settings", s)
	BackendService.flush()
