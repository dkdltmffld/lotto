extends SceneTree

# 상설 테스트 통합 러너 (2026-06-11 기술 로드맵 ②-1).
# 순수 로직 테스트(tools/tests/test_*.gd)를 한 번에 실행하고 종합 결과를 출력한다.
#
# 실행:
#   & "<godot_console.exe>" --headless --path "E:\projects\새-게임-프로젝트" --script res://tools/tests/run_tests.gd
# 개별 테스트는 같은 방식으로 --script res://tools/tests/test_<이름>.gd (각 파일이 단독 실행 지원).
#
# 계약: 각 테스트 파일은 extends SceneTree + static func run() -> Array(실패 메시지, 빈 배열=통과).
# ⚠️ --script 모드는 autoload 미로드 — BackendService 등 autoload 의존 로직은 여기서 테스트 불가(대상 외).
#    새 테스트 추가 시 TESTS 에 한 줄 추가(경로 preload — class_name 불필요).

const TESTS: Dictionary = {
	"hand_evaluator": preload("res://tools/tests/test_hand_evaluator.gd"),
	"gacha": preload("res://tools/tests/test_gacha.gd"),
	"relics": preload("res://tools/tests/test_relics.gd"),
	"balance": preload("res://tools/tests/test_balance.gd"),
	"local_provider": preload("res://tools/tests/test_local_provider.gd"),
	"mailbox": preload("res://tools/tests/test_mailbox.gd"),
	"quests": preload("res://tools/tests/test_quests.gd"),
	"dungeon": preload("res://tools/tests/test_dungeon.gd"),
}


func _initialize() -> void:
	var total_fails: int = 0
	var failed_suites: Array = []
	print("=== 상설 테스트 실행 (%d 스위트) ===" % TESTS.size())
	for key in TESTS:
		var fails: Array = TESTS[key].run()
		if fails.is_empty():
			print("[%s] PASS" % key)
		else:
			for f in fails:
				printerr("  FAIL: %s" % str(f))
			printerr("[%s] FAIL (%d)" % [key, fails.size()])
			failed_suites.append(key)
			total_fails += fails.size()
	if total_fails == 0:
		print("=== 전체 PASS ===")
	else:
		printerr("=== 실패: %d건 (%s) ===" % [total_fails, ", ".join(failed_suites)])
	quit(0 if total_fails == 0 else 1)
