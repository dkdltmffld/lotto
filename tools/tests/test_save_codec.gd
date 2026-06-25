extends SceneTree
# 대상: scripts/backend/kplay_provider.gd 의 _encode/_decode (세이브 gzip+base64 "z:" 압축 코덱)
# 단독 실행:
#   godot --headless --path "E:/projects/새-게임-프로젝트" --script res://tools/tests/test_save_codec.gd
# 비고:
#   - _init()은 비웹에서 즉시 return 하므로 헤드리스 인스턴스화 안전(autoload 미참조).
#   - 손상 입력 케이스에서 엔진이 ERROR 로그(base64/decompress 실패)를 찍을 수 있으나
#     의도된 노이즈 — 반환값({})과 무크래시만 검증한다.

const KplayProviderScript := preload("res://scripts/backend/kplay_provider.gd")


static func _check(cond: bool, msg: String, fails: Array) -> void:
	if not cond:
		fails.append(msg)


static func run() -> Array:
	var fails: Array = []
	var p := KplayProviderScript.new()

	# --- 1. 라운드트립: 한글 키/값 + 중첩 dict/array ---
	# JSON 경유 시 숫자는 전부 float 로 정규화되므로(코드의 실제 동작),
	# 기대값도 JSON.parse_string(JSON.stringify(원본)) 으로 정규화해 비교한다.
	var data := {
		"gold": 12345,
		"이름": "복권 키우기",
		"settings": {"audio_muted": false, "bgm_volume": 0.5},
		"equips": {"weapon": [{"uid": 1, "item": "녹슨 검", "level": 3}], "armor": []},
		"잡동사니": [1, 2.5, "셋", {"중첩": true}, null],
	}
	var expected: Variant = JSON.parse_string(JSON.stringify(data))
	_check(typeof(expected) == TYPE_DICTIONARY, "기대값 JSON 정규화가 Dictionary 가 아님", fails)

	var enc := p._encode(data)
	_check(enc.begins_with("z:"), "_encode 결과에 'z:' 접두사가 없음: %s" % enc.substr(0, 8), fails)
	var dec := p._decode(enc)
	_check(typeof(dec) == TYPE_DICTIONARY, "라운드트립 _decode 가 Dictionary 가 아님", fails)
	_check(dec == expected, "라운드트립 deep 비교 불일치 (한글/중첩 dict/array)", fails)
	_check(JSON.stringify(dec) == JSON.stringify(expected), "라운드트립 재직렬화 문자열 불일치", fails)

	# --- 2. 하위호환: 구포맷 평문 JSON → 정상 Dictionary ---
	var legacy := JSON.stringify(data)
	_check(not legacy.begins_with("z:"), "평문 JSON 픽스처가 우연히 'z:'로 시작함(픽스처 오류)", fails)
	var dec_legacy := p._decode(legacy)
	_check(dec_legacy == expected, "구포맷(평문 JSON) 디코드 불일치", fails)

	# --- 3. 빈 dict 라운드트립 ---
	var enc_empty := p._encode({})
	_check(enc_empty.begins_with("z:"), "빈 dict 인코드에 'z:' 접두사가 없음", fails)
	var dec_empty := p._decode(enc_empty)
	_check(typeof(dec_empty) == TYPE_DICTIONARY and dec_empty.is_empty(), "빈 dict 라운드트립이 빈 Dictionary 가 아님", fails)

	# --- 4. 큰 dict(수백 키, 반복 구조): 압축이 평문보다 작아야 함 + 라운드트립 ---
	var big := {}
	for i in range(300):
		big["weapon_%03d" % i] = {"item": "weapon_common_sword", "grade": "common", "level": i % 20}
	var big_plain := JSON.stringify(big)
	var big_enc := p._encode(big)
	_check(big_enc.length() < big_plain.length(),
		"큰 dict 압축(%d B)이 평문(%d B)보다 작지 않음" % [big_enc.length(), big_plain.length()], fails)
	var big_dec := p._decode(big_enc)
	_check(big_dec == JSON.parse_string(big_plain), "큰 dict 라운드트립 불일치", fails)

	# --- 5. 손상 입력: 크래시 없이 {} 반환 (코드 기준 기본값) ---
	# 5-1. "z:" 접두사 + base64 로 못 읽는 한글/특수문자
	var bad1 := p._decode("z:손상base64!!!@@@")
	_check(typeof(bad1) == TYPE_DICTIONARY and bad1.is_empty(), "손상 base64('z:손상…')가 빈 dict 가 아님", fails)
	# 5-2. 비JSON 평문
	var bad2 := p._decode("이건 JSON 아님 {{{")
	_check(typeof(bad2) == TYPE_DICTIONARY and bad2.is_empty(), "비JSON 평문이 빈 dict 가 아님", fails)
	# 5-3. 빈 문자열
	var bad3 := p._decode("")
	_check(typeof(bad3) == TYPE_DICTIONARY and bad3.is_empty(), "빈 문자열이 빈 dict 가 아님", fails)
	# 5-4. 접두사만 ("z:")
	var bad4 := p._decode("z:")
	_check(typeof(bad4) == TYPE_DICTIONARY and bad4.is_empty(), "'z:'만 있는 입력이 빈 dict 가 아님", fails)
	# 5-5. 유효 JSON이지만 Dictionary 가 아님(배열) → 코드 기준 {} 반환
	var bad5 := p._decode("[1,2,3]")
	_check(typeof(bad5) == TYPE_DICTIONARY and bad5.is_empty(), "JSON 배열 입력이 빈 dict 가 아님", fails)
	# 5-6. 유효 base64지만 gzip 이 아닌 바이트
	var bad6 := p._decode("z:" + Marshalls.raw_to_base64("gzip 아님".to_utf8_buffer()))
	_check(typeof(bad6) == TYPE_DICTIONARY and bad6.is_empty(), "비gzip base64 입력이 빈 dict 가 아님", fails)

	return fails


func _initialize() -> void:
	var fails := run()
	for f in fails:
		printerr("  FAIL: %s" % f)
	if fails.is_empty():
		print("[test_save_codec] PASS")
		quit(0)
	else:
		print("[test_save_codec] FAIL (%d)" % fails.size())
		quit(1)
