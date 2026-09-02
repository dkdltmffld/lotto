class_name BackendProvider
extends RefCounted

# 로컬 영속화 인터페이스. 웹/데스크탑 모두 user:// 파일을 사용한다.
# Google은 현재 외부 인증이 없는 로컬 프로필이며 Guest와 슬롯만 분리된다.
const SLOT_GOOGLE := "google"
const SLOT_GUEST := "guest"


# load_all은 await 대상이므로 항상 코루틴이어야 한다. 한 프레임 대기로 코루틴화 보장.
func _await_one_frame() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).process_frame


# 저장 슬롯 선택. Google/Guest 진행도가 섞이지 않게 파일을 분리한다.
func set_slot(_slot: String) -> void:
	pass


# 저장된 전체 데이터(JSON dict) 로드. 없거나 실패 시 {} 반환. (코루틴 — 호출 측은 await)
func load_all() -> Dictionary:
	await _await_one_frame()
	return {}


# 전체 데이터 저장. fire-and-forget(await 불필요). 성공 여부 반환.
func save_all(_data: Dictionary) -> bool:
	return false


# 현재 선택된 로컬 슬롯의 저장을 삭제한다. 계정 탈퇴에서만 호출한다.
func clear_current() -> void:
	pass
