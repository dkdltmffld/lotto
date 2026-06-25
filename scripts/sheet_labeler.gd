extends Control
# UI_sheet.png 에 각 조각의 번호(#)와 외곽선을 그려 보여주는 임시 뷰어.
# 사용자가 "이거 #몇번으로" 하고 가리킬 참조 그림용. (에디터에서 해당 씬 F6 실행 또는 MCP run)
# _draw()로 시트·외곽선·번호를 같은 스케일/오프셋으로 직접 그려 정확히 정렬 + 화면에 꽉 맞게 중앙 배치.
# RECTS = scan_sheet.gd 가 뽑은 컴포넌트 인덱스/Rect2 (시트 바꾸면 scan 재실행 후 갱신).

const SHEET := "res://assets/ui/UI_sheet.png"
const CAPTURE := false  # true로 두고 이 씬 실행(F6/MCP run) → 번호 시트를 CAPTURE_PATH 로 저장 후 종료. 평소 false.
const CAPTURE_PATH := "res://docs/ref/ui_sheet_numbered.png"

# 좌표 단일 출처 = scripts/sheet_rects.gd (구 로컬 RECTS 사본 폐기 — 2026-06-09 'labeler 갱신 누락' 사고 재발 방지).
# 인덱스 = 라벨 #번호 = ui_skin R_* 매핑과 동일. 시트 교체 시 sheet_rects.gd 만 갱신.
const _SR := preload("res://scripts/sheet_rects.gd")
const SHEET_W := _SR.SHEET_W
const SHEET_H := _SR.SHEET_H
const RECTS := _SR.RECTS

var _tex: Texture2D
var _font: Font


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex = load(SHEET)
	_font = ThemeDB.fallback_font
	resized.connect(queue_redraw)
	queue_redraw()
	if CAPTURE:
		_capture()


func _capture() -> void:
	# 창을 시트 비율(2:3)로 키워 번호 오버레이를 꽉 채워 렌더 → 뷰포트 이미지를 PNG로 저장 후 종료.
	DisplayServer.window_set_size(Vector2i(int(SHEET_W * 0.66) + 16, int(SHEET_H * 0.66) + 16))
	await get_tree().process_frame
	await get_tree().process_frame
	queue_redraw()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(CAPTURE_PATH)
	print("[labeler] saved %s err=%d size=%s" % [CAPTURE_PATH, err, str(img.get_size())])
	get_tree().quit()


func _draw() -> void:
	var avail: Vector2 = size
	if avail.x < 1.0 or avail.y < 1.0:
		avail = get_viewport_rect().size
	# 시트 전체가 화면에 들어오도록 fit-scale + 중앙 배치
	var s: float = min((avail.x - 8.0) / SHEET_W, (avail.y - 8.0) / SHEET_H)
	var dw: float = SHEET_W * s
	var dh: float = SHEET_H * s
	var off := Vector2((avail.x - dw) * 0.5, (avail.y - dh) * 0.5)

	draw_rect(Rect2(Vector2.ZERO, avail), Color(0.07, 0.07, 0.09), true)
	if _tex != null:
		draw_texture_rect(_tex, Rect2(off, Vector2(dw, dh)), false)

	for i in RECTS.size():
		var r: Rect2 = RECTS[i]
		var pr := Rect2(off + r.position * s, r.size * s)
		draw_rect(pr, Color(1.0, 0.85, 0.15, 0.95), false, 1.0)
		var tp := pr.position + Vector2(3.0, 13.0)
		if _font != null:
			draw_string(_font, tp + Vector2(1, 1), "#%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0))
			draw_string(_font, tp, "#%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.35))
