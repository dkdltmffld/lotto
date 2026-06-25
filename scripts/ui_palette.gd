class_name UIPalette
extends RefCounted

# 데미지 플로터 색상 — 기획서 5-2.
# 피격(-n)과 공격(n)을 시각적으로 구분.
const DAMAGE_FLOATER_INCOMING: Color = Color(1.0, 0.4, 0.4)  # 피격: 붉은 계열
const DAMAGE_FLOATER_OUTGOING: Color = Color(1.0, 0.28, 0.22)  # 공격(자동): 붉은 계열(쨍한 빨강 — 피격용 연한 붉은색과 구분)
const DAMAGE_FLOATER_SKILL: Color = Color(1.0, 0.45, 0.35)      # 스킬 버스트(긁어서 공격): 밝고 쨍한 빨강(자동 빨강과 구분, 크기·팝으로 강조)

# 향후 추가 가능: HUD 강조 색, 상태 표시 색, 게임오버 패널 색 등
