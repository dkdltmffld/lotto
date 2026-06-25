extends SceneTree
# #24(초록 게이지 바) 영역 안에서 '초록 채움'의 바운딩 박스를 찾아, 좌/우/상/하 캡(비초록 테두리) 폭을 출력.
# 이 값으로 game.gd의 게이지 NinePatch patch_margin + 마스크 inner inset을 정확히 맞춘다.
# 실행: godot --headless --path . --script res://tools/scan_bar.gd

const SHEET := "res://assets/ui/UI_sheet.png"
const REGION := Rect2i(30, 1416, 465, 27)  # ui_skin R_BAR_FILL (#24)


func _initialize() -> void:
	var img: Image = (load(SHEET) as Texture2D).get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var rx := REGION.position.x
	var ry := REGION.position.y
	var rw := REGION.size.x
	var rh := REGION.size.y
	var gx0 := rw
	var gy0 := rh
	var gx1 := -1
	var gy1 := -1
	for cy in rh:
		for cx in rw:
			var c := img.get_pixel(rx + cx, ry + cy)
			# '초록 채움' 판정: 불투명 + 초록이 빨강/파랑보다 우세하고 어느 정도 밝음
			if c.a > 0.5 and c.g > 0.33 and c.g >= c.r and c.g >= c.b and (c.g - minf(c.r, c.b)) > 0.08:
				if cx < gx0: gx0 = cx
				if cx > gx1: gx1 = cx
				if cy < gy0: gy0 = cy
				if cy > gy1: gy1 = cy
	if gx1 < 0:
		print("[scan_bar] 초록 픽셀 못 찾음 — 판정 기준 조정 필요")
		quit(1)
		return
	var cap_l := gx0
	var cap_r := rw - 1 - gx1
	var cap_t := gy0
	var cap_b := rh - 1 - gy1
	print("[scan_bar] region %dx%d" % [rw, rh])
	print("[scan_bar] green bbox: x[%d..%d] y[%d..%d]" % [gx0, gx1, gy0, gy1])
	print("[scan_bar] CAP  left=%d  right=%d  top=%d  bottom=%d  (px, 소스 기준)" % [cap_l, cap_r, cap_t, cap_b])
	quit(0)
