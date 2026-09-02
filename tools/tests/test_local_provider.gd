extends SceneTree

# Google/게스트가 서로 다른 user:// 파일을 선택하는지 검증한다.
# 실제 세이브는 읽거나 쓰지 않는다.
const LocalProviderMod := preload("res://scripts/backend/local_provider.gd")


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []
	var provider := LocalProviderMod.new()

	_check(provider._slot_path == "user://save.json", "기본 슬롯은 Google 호환 경로여야 함", fails)
	provider.set_slot(BackendProvider.SLOT_GUEST)
	_check(provider._slot_path == "user://save_guest.json", "Guest 슬롯 경로 불일치", fails)
	provider.set_slot(BackendProvider.SLOT_GOOGLE)
	_check(provider._slot_path == "user://save.json", "Google 슬롯 경로 불일치", fails)

	return fails


func _initialize() -> void:
	var fails: Array = run()
	for msg in fails:
		printerr("  FAIL: %s" % str(msg))
	if fails.is_empty():
		print("[test_local_provider] PASS")
	else:
		print("[test_local_provider] FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
