extends Control

# 개발용 치트 패널 (치트 활성 시 cheat_controller.gd 가 생성). 코드로 UI 빌드.
# 골드 생성 / 스테이지 이동 / HP 회복 / 세이브 초기화 등 테스트 편의 기능.
# 실제 동작은 시그널로 cheat_controller.gd 에 위임.

signal add_gold(amount)
signal add_dia(amount)          # 다이아(장비 뽑기 재화) 지급
signal boost_upgrades(levels)   # 모든 강화 트랙을 levels만큼 올림(골드 무시, 상한 트랙은 max로 clamp)
signal goto_stage_delta(delta)
signal jump_to_boss
signal reset_stage
signal heal
signal wipe_save
signal set_number_dist(spec)   # 스크래치 숫자 분포 변경 (테스트용). spec = {type, …}
signal set_auto_fast(on)       # 자동긁기 속도 치트(8.0) ON/OFF
signal set_pose_attack(on)     # [프로토타입] PC 공격 = 포즈투포즈 모드 ON/OFF (현재 방식과 비교)
signal add_dust(amount)        # 유물 가루 지급
signal grant_relic(effect, grade)  # 유물 지급+장착(테스트). effect=="" 면 랜덤 뽑기
signal clear_relics            # 보유/장착 유물 전부 비움
signal closed


func _ready() -> void:
	# 전체 화면 오버레이 + 가운데 VBox(골드/스테이지/HP/세이브초기화 버튼들). 동작은 시그널로 game.gd 위임.
	var vbox := UISkin.build_dim_center(self, 0.8, 4, 300.0)

	vbox.add_child(_title("치트 (개발용)"))

	vbox.add_child(_label("골드 (10억=1,000,000K, 1조=1,000,000M)"))
	vbox.add_child(_row([
		_btn("+10M", func(): add_gold.emit(1e7)),
		_btn("+10억", func(): add_gold.emit(1e9)),
		_btn("+1조", func(): add_gold.emit(1e12)),
		_btn("+100경", func(): add_gold.emit(1e18)),
	]))

	vbox.add_child(_label("다이아 (장비 뽑기)"))
	vbox.add_child(_row([
		_btn("+100", func(): add_dia.emit(100.0)),
		_btn("+10억", func(): add_dia.emit(1e9)),
		_btn("+1조", func(): add_dia.emit(1e12)),
		_btn("+100경", func(): add_dia.emit(1e18)),
	]))

	vbox.add_child(_label("강화 (풀강화, 골드 무시)"))
	vbox.add_child(_row([
		_btn("전체 +1", func(): boost_upgrades.emit(1)),
		_btn("전체 +10", func(): boost_upgrades.emit(10)),
		_btn("전체 +100", func(): boost_upgrades.emit(100)),
	]))

	vbox.add_child(_label("스테이지"))
	vbox.add_child(_row([
		_btn("-1", func(): goto_stage_delta.emit(-1)),
		_btn("+1", func(): goto_stage_delta.emit(1)),
		_btn("+10", func(): goto_stage_delta.emit(10)),
	]))
	vbox.add_child(_row([
		_btn("다음 보스", func(): jump_to_boss.emit()),
		_btn("1로 리셋", func(): reset_stage.emit()),
	]))

	vbox.add_child(_label("스크래치 숫자 (분포 테스트)"))
	vbox.add_child(_row([
		_btn("기본 1~9", func(): set_number_dist.emit({"type": "range", "min": 1, "max": 9})),
		_btn("고숫자↑", func(): set_number_dist.emit({"type": "weights", "weights": {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 3, 8: 4, 9: 5}})),
	]))
	vbox.add_child(_row([
		_btn("9만(잭팟)", func(): set_number_dist.emit({"type": "pool", "values": [9]})),
		_btn("넓게 1~20", func(): set_number_dist.emit({"type": "range", "min": 1, "max": 20})),
	]))

	vbox.add_child(_label("자동긁기 속도 (치트 전용)"))
	vbox.add_child(_row([
		_btn("빠르게(8)", func(): set_auto_fast.emit(true)),
		_btn("원래대로", func(): set_auto_fast.emit(false)),
	]))

	vbox.add_child(_label("공격 모션 (포즈투포즈 비교)"))
	vbox.add_child(_row([
		_btn("포즈투포즈", func(): set_pose_attack.emit(true)),
		_btn("원래대로", func(): set_pose_attack.emit(false)),
	]))

	vbox.add_child(_label("유물 (가루/지급/장착 - 테스트)"))
	vbox.add_child(_row([
		_btn("가루+1K", func(): add_dust.emit(1000.0)),
		_btn("랜덤뽑기", func(): grant_relic.emit("", "")),
		_btn("유물비우기", func(): clear_relics.emit()),
	]))
	vbox.add_child(_row([
		_btn("분포(신화)", func(): grant_relic.emit("r_dist_low", "mythic")),
		_btn("고보정(전설)", func(): grant_relic.emit("r_boost_high", "legendary")),
		_btn("저보정(영웅)", func(): grant_relic.emit("r_boost_low", "epic")),
	]))
	vbox.add_child(_row([
		_btn("와일드(신화)", func(): grant_relic.emit("r_wild", "mythic")),
		_btn("투페어(전설)", func(): grant_relic.emit("r_expand_2pair", "legendary")),
		_btn("풀하우스(전설)", func(): grant_relic.emit("r_expand_full", "legendary")),
	]))

	vbox.add_child(_btn("HP 풀 회복", func(): heal.emit()))
	var wipe := _btn("세이브 초기화", func(): wipe_save.emit())
	wipe.add_theme_color_override("font_color", Color(1, 0.55, 0.55))
	vbox.add_child(wipe)
	vbox.add_child(_btn("닫기", func(): closed.emit()))


func open() -> void:
	# UIManager.open_overlay() 통일 인터페이스.
	visible = true


# --- UI 빌드 헬퍼 ---

func _title(text: String) -> Label:  # 큰 제목 라벨
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _label(text: String) -> Label:  # 섹션 소제목 라벨(골드/스테이지 등)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 0.9))
	return l


func _row(buttons: Array) -> HBoxContainer:  # 버튼 여러 개를 가로로 균등 배치
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return h


func _btn(text: String, cb: Callable) -> Button:  # 버튼 생성(텍스트 + 콜백)
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 28)
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b
