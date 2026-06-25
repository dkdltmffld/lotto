extends SceneTree
# scan_sheet.gd — UI 시트(여러 조각이 투명 간격으로 배치된 단일 PNG)에서 각 조각의
# 불투명 바운딩 박스(Rect2)를 연결요소(connected component)로 자동 추출.
# 실행: godot --headless --path . --script res://tools/scan_sheet.gd [상대경로]
# 기본 대상: assets/ui/UI_sheet.png. 결과를 좌상단부터 정렬해 출력(역할 매핑은 사람이).

const DEFAULT := "res://assets/ui/UI_sheet.png"
const ALPHA_MIN := 16      # 이 알파(0-255) 초과면 불투명으로 간주
const MIN_AREA := 200      # 노이즈 컴포넌트 제거(너무 작은 조각)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := DEFAULT
	if args.size() > 0:
		path = args[0]
	var tex: Texture2D = load(path)
	if tex == null:
		printerr("로드 실패: ", path)
		quit(1)
		return
	var img: Image = tex.get_image()
	if img == null:
		printerr("get_image 실패: ", path)
		quit(1)
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()  # RGBA8 연속 바이트
	print("[scan] %s  %dx%d" % [path, w, h])

	var n := w * h
	var visited := PackedByteArray()
	visited.resize(n)
	var comps: Array = []  # {x0,y0,x1,y1,area}
	var stack := PackedInt32Array()

	for start in n:
		if visited[start] == 1:
			continue
		visited[start] = 1
		if data[start * 4 + 3] <= ALPHA_MIN:
			continue
		# BFS 플러드필 (4-이웃)
		var x0 := start % w
		var y0 := start / w
		var x1 := x0
		var y1 := y0
		var area := 0
		stack.clear()
		stack.push_back(start)
		while stack.size() > 0:
			var idx := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var cx := idx % w
			var cy := idx / w
			area += 1
			if cx < x0: x0 = cx
			if cx > x1: x1 = cx
			if cy < y0: y0 = cy
			if cy > y1: y1 = cy
			# 이웃
			var nb := [
				idx - 1 if cx > 0 else -1,
				idx + 1 if cx < w - 1 else -1,
				idx - w if cy > 0 else -1,
				idx + w if cy < h - 1 else -1,
			]
			for ni in nb:
				if ni < 0 or visited[ni] == 1:
					continue
				visited[ni] = 1
				if data[ni * 4 + 3] > ALPHA_MIN:
					stack.push_back(ni)
		if area >= MIN_AREA:
			comps.append({"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1, "area": area})

	# 좌상단 → 우하단 정렬(행 단위: y 60px 버킷 후 x)
	comps.sort_custom(func(a, b):
		var ay: int = a["y"] / 60
		var by: int = b["y"] / 60
		if ay != by:
			return ay < by
		return a["x"] < b["x"]
	)
	print("[scan] 컴포넌트 %d개 (area>=%d):" % [comps.size(), MIN_AREA])
	for i in comps.size():
		var c = comps[i]
		print("  #%2d  Rect2(%4d, %4d, %4d, %4d)  area=%d" % [i, c["x"], c["y"], c["w"], c["h"], c["area"]])
	quit(0)
