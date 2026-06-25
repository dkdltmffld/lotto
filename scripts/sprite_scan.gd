extends RefCounted

# 스프라이트 시트 스캔 공용 유틸 — player_controller / enemy 에 중복돼 있던
# _scan_sheet / _first_opaque_row / 렌더 적용부를 단일 출처로.
# ⚠️ class_name 없음(에디터 stale 클래스 캐시 회피) — 사용처는 preload 로 참조:
#   const SpriteScanLib := preload("res://scripts/sprite_scan.gd")
# ⚠️ 시트별 scale/offset_y "계산"(발끝 정렬 공식)은 여기로 옮기지 않는다 —
#   player(idle 실측 기준)와 enemy(BASE_FEET_LOCAL 고정 기준)의 공식·나눗셈 순서가 달라
#   단일화하면 발끝 정렬이 ULP 드리프트로 변할 수 있음(2026-06-10 감사 SS-2 결론: 각 클래스 보존).

const ALPHA_THRESHOLD: float = 0.15  # 이 알파 초과 픽셀 = 불투명(캐릭터)

# 경로|프레임폭 → {feet, char_h} 1회 캐시(전 인스턴스 공유). frame_w를 키에 포함해
# 미래에 다른 프레임 폭으로 같은 시트를 스캔해도 오염되지 않게 한다.
static var _cache: Dictionary = {}


static func scan_sheet(tex: Texture2D, frame_w: int) -> Dictionary:
	# 시트를 프레임별로 스캔해 발끝(불투명 최하단)·대표 캐릭터 높이(프레임 bbox 높이 중앙값)를 구한다.
	# 중앙값이라 무기·투사체 등 이상치 프레임에 강하다. 실패 시 {feet:-1, char_h:-1}.
	if tex == null:
		return {"feet": -1, "char_h": -1}
	var key: String = "%s|%d" % [tex.resource_path, frame_w]
	if _cache.has(key):
		return _cache[key]
	var res: Dictionary = {"feet": -1, "char_h": -1}
	var img: Image = tex.get_image()
	if img != null:
		var h: int = img.get_height()
		var n: int = max(1, int(img.get_width() / frame_w))
		var bots: Array = []
		var heights: Array = []
		for f in n:
			var x0: int = f * frame_w
			var top: int = first_opaque_row(img, x0, frame_w, h, true)
			if top < 0:
				continue  # 빈 프레임
			var bot: int = first_opaque_row(img, x0, frame_w, h, false)
			bots.append(bot)
			heights.append(bot - top + 1)
		if not bots.is_empty():
			bots.sort()
			heights.sort()
			res["feet"] = int(bots[bots.size() / 2])
			res["char_h"] = int(heights[heights.size() / 2])
	_cache[key] = res
	return res


static func first_opaque_row(img: Image, x0: int, fw: int, h: int, from_top: bool) -> int:
	# 한 프레임(x0~x0+fw)에서 위→아래(from_top) 또는 아래→위로 첫 불투명 행. 없으면 -1.
	var ys: Array = range(h) if from_top else range(h - 1, -1, -1)
	for y in ys:
		for x in fw:
			if img.get_pixel(x0 + x, y).a > ALPHA_THRESHOLD:
				return y
	return -1


static func apply_render(spr: AnimatedSprite2D, anim: String, render: Dictionary, fallback_scale: float) -> void:
	# 재생 + 사전 계산된 scale/offset_y 적용(시트별 크기 정규화·발끝 정렬). player/enemy 공용.
	spr.play(anim)
	var r: Dictionary = render.get(anim, {})
	var sc: float = float(r.get("scale", fallback_scale))
	spr.scale = Vector2(sc, sc)
	spr.offset.y = float(r.get("offset_y", 0.0))
