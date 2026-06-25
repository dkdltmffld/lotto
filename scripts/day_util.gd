class_name DayUtil
extends RefCounted

# 날짜 헬퍼 — 일일 리셋(퀘스트·추후 리텐션 출석) 공용 시간 추상화. (기획: 퀘스트 §5)
# ⚠️ 1차는 로컬 시계 폴백 — 서버 시간 확보 전까지 시계 조작 가능성은 감수(기획 §5).
#    서버/플랫폼 시간이 준비되면 today() 한 지점만 교체/통합한다.
# ⚠️ class_name 있음 — 단, game.gd 등 stale 캐시 회피 위해 호출부는 preload(DayUtilScript) 권장.


static func today() -> String:
	# 로컬 날짜 "YYYY-MM-DD". 일일 퀘스트 리셋 키.
	var t: Dictionary = Time.get_datetime_dict_from_system(false)  # false = 로컬 시간
	return "%04d-%02d-%02d" % [int(t.get("year", 1970)), int(t.get("month", 1)), int(t.get("day", 1))]
