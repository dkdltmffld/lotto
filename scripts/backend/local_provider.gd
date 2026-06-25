class_name LocalBackendProvider
extends BackendProvider

# 비웹(에디터·데스크탑) 폴백. user:// 에 JSON 파일로 저장.
# 웹에서는 KplayBackendProvider가 대신 쓰인다. 단일 플레이어라 로그인/리더보드는 no-op.
# 게스트/인증 슬롯은 파일을 분리한다(save.json=인증, save_guest.json=게스트).

const AUTH_PATH := "user://save.json"          # 인증 슬롯(기존 파일명 유지)
var _slot_path: String = AUTH_PATH


func set_slot(slot: String, _cloud_sync: bool) -> void:
	# 비웹은 클라우드가 없으니 cloud_sync는 무시하고 파일만 분리한다.
	_slot_path = AUTH_PATH if slot == BackendProvider.SLOT_AUTH else "user://save_%s.json" % slot


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


func login(_provider_hint: String = "") -> void:
	# 비웹은 실제 인증이 없으므로 개발 편의용 더미 로그인 즉시 성공 처리.
	# (call_deferred로 emit해 호출 측이 login_changed를 await로 잡을 시간을 준다)
	login_changed.emit.call_deferred(true, "DevUser")


func clear_local() -> void:
	_delete_file()


func clear_account() -> void:
	# 비웹은 별도 서버가 없으므로 로컬 파일 삭제가 곧 전체 삭제.
	_delete_file()


func _delete_file() -> void:
	# 현재 슬롯 파일만 삭제 (게스트/인증 분리).
	if FileAccess.file_exists(_slot_path):
		DirAccess.remove_absolute(_slot_path)
