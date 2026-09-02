class_name LocalBackendProvider
extends BackendProvider

# 웹·에디터·데스크탑 공용 로컬 저장 Provider. user:// 에 JSON 파일로 저장한다.
# Google은 현재 외부 인증 없는 로컬 프로필이며 Guest와 파일만 분리된다.
# 기존 Google 진행도 호환을 위해 save.json 파일명은 유지한다.

const GOOGLE_PATH := "user://save.json"
const GUEST_PATH := "user://save_guest.json"
var _slot_path: String = GOOGLE_PATH


func set_slot(slot: String) -> void:
	_slot_path = GOOGLE_PATH if slot == BackendProvider.SLOT_GOOGLE else GUEST_PATH


func load_all() -> Dictionary:
	await _await_one_frame()
	if not FileAccess.file_exists(_slot_path):
		return {}
	var f := FileAccess.open(_slot_path, FileAccess.READ)
	if f == null:
		push_warning("[Backend/Local] 저장 파일 열기 실패: %s" % _slot_path)
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Backend/Local] 저장 파일 파싱 실패 — 새로 시작")
		return {}
	return parsed


func save_all(data: Dictionary) -> bool:
	var f := FileAccess.open(_slot_path, FileAccess.WRITE)
	if f == null:
		push_warning("[Backend/Local] 저장 파일 쓰기 실패: %s" % _slot_path)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


func clear_current() -> void:
	_delete_file()


func _delete_file() -> void:
	# 현재 슬롯 파일만 삭제 (게스트/인증 분리).
	if FileAccess.file_exists(_slot_path):
		DirAccess.remove_absolute(_slot_path)
