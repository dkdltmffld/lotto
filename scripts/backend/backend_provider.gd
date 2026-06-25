class_name BackendProvider
extends RefCounted

# 백엔드 영속화/플랫폼 기능의 추상 인터페이스.
# 구현체: LocalBackendProvider(비웹, user:// 파일) / KplayBackendProvider(웹, kplay postMessage).
# BackendService가 플랫폼에 따라 하나를 골라 사용한다.

# 플랫폼→게임 비동기 알림. Local은 emit하지 않음(싱글플레이), Kplay는 message 수신 시 emit.
signal login_changed(logged_in: bool, user_name: String)
signal score_submitted(success: bool, rank: int)
signal resync_needed()  # (웹) 로그인 타임아웃 뒤 늦게 클라우드가 도착 → BackendService 재로드 필요(stale 덮어쓰기 방지)

# 저장 슬롯 이름 (set_slot의 slot 인자). "auth"=인증 계정, "guest"=게스트.
const SLOT_AUTH := "auth"
const SLOT_GUEST := "guest"


# load_all은 await 대상이므로 항상 코루틴이어야 한다. 한 프레임 대기로 코루틴화 보장.
func _await_one_frame() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).process_frame


# 저장 슬롯 선택. 계정 종류별로 저장 위치를 분리해 데이터가 섞이지 않게 한다.
#   slot = "auth"(인증 계정, 클라우드 동기) / "guest"(게스트, 로컬 전용)
#   cloud_sync = true면 저장 시 클라우드에도 반영(인증), false면 로컬만(게스트).
# BackendService가 계정 선택/로그인 시 호출한다. (기본 구현 no-op)
func set_slot(_slot: String, _cloud_sync: bool) -> void:
	pass


# 저장된 전체 데이터(JSON dict) 로드. 없거나 실패 시 {} 반환. (코루틴 — 호출 측은 await)
func load_all() -> Dictionary:
	await _await_one_frame()
	return {}


# 전체 데이터 저장. fire-and-forget(await 불필요). 성공 여부 반환.
func save_all(_data: Dictionary) -> bool:
	return false


# --- 플랫폼 기능 (웹 전용; 비웹은 no-op) ---

# provider_hint = "google" | "kplay" (인증 방식 힌트). 완료는 login_changed 시그널로.
func login(_provider_hint: String = "") -> void:
	pass


func submit_score(_score: int) -> void:
	pass


func show_leaderboard() -> void:
	pass


# 로그아웃: 로컬(이 기기) 데이터만 삭제. 인증 계정의 클라우드 사본은 유지(재로그인 시 복원).
func clear_local() -> void:
	pass


# 계정 탈퇴: 로컬 + 서버(클라우드) 데이터 모두 삭제. 재로그인 시 신규 계정으로 시작.
func clear_account() -> void:
	pass
