extends SceneTree
# UI_sheet 조각을 3배 확대 크롭해 docs/ref/piece_*.png 로 저장(9-slice 마진 진단용).
# 실행: godot --headless --path . --script res://tools/crop_pieces.gd

func _initialize() -> void:
	var tex: Texture2D = load("res://assets/ui/UI_sheet.png")
	var img: Image = tex.get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var specs := [
		["01_navbg", 25, 138, 694, 74],
		["03_buy", 752, 235, 248, 59],
		["06_navbtn", 752, 323, 248, 55],
		["15_panel", 744, 810, 255, 166],
		["23_topbar", 788, 1268, 210, 91],
		["26_close", 641, 1392, 79, 74],
	]
	for s in specs:
		var r := Rect2i(int(s[1]), int(s[2]), int(s[3]), int(s[4]))
		var c := img.get_region(r)
		c.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
		c.save_png("res://docs/ref/piece_%s.png" % s[0])
		print("saved %s %s" % [s[0], str(r)])
	quit()
