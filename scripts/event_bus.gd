extends Node

# 전역 이벤트 버스 (autoload "Events") — 2026-06-10 싱글톤 매니저 도입 1단계.
# 패널/시스템 간 점대점 시그널 배선(패널→game.gd 수동 connect)을 중앙 신호로 대체한다.
# 발행자는 게임 규칙을 모른 채 "무슨 일이 일어났다"만 알리고, 반응(HUD 갱신·스탯 재계산·분포 재적용)은
# 구독자(game.gd 등)가 소유한다. 새 시스템(리텐션·획득 리듬 등)은 여기 신호만 구독하면 됨.
#
# ⚠️ 구독자가 씬 노드면 씬 전환 시 Godot이 연결을 자동 해제한다(freed object 연결 정리) — 수동 해제 불필요.
# ⚠️ 게임 상태(값)는 싣지 않는다 — 상태의 단일 출처는 BackendService. 여기는 "변했다" 통지만.

signal currency_changed       # 골드/다이아/가루 등 재화 변동(소환·구매 등 이산 이벤트) → HUD 갱신
signal equipment_changed      # 장비 장착/강화/합성 → 최대체력 재계산 + HUD
signal relics_changed         # 유물 장착/해제/뽑기 → 스크래치 분포·와일드 재적용 + HUD
signal upgrade_purchased      # 강화 구매 → 스탯 즉시 반영 + HUD
signal dungeon_enter_requested(floor: int)  # 던전 패널에서 "도전" → game.gd 가 받아 던전 모드 진입
