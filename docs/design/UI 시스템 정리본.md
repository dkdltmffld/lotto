# UI 시스템

> 화면 구성·HUD·캐릭터 표시·시각 이펙트·데이터 위치 정리. 상위 컨셉은 [[게임 컨셉 정리본]], 전투 의도는 [[전투 시스템 정리본]] 참조.

## 1. 개요

본 게임의 화면 구성·HUD·캐릭터 표시·시각 이펙트·데이터 분리 등 UI 전반을 정리한다. 일부 항목(데미지 플로터, 체력바, 사망 연출 등)은 전투 시스템 기획서와 겹치는데, 본 기획서는 **UI 구조·레이아웃·데이터 위치 위주**이며 게임플레이 의도는 전투 시스템 기획서를 참조한다.

## 2. 해상도와 화면 적응

### 2-1. 디자인 해상도

- **360 × 780** (9:19.5 portrait, 모바일 세로)
- 개발 윈도우: 432 × 936 (1.2배, 데스크탑 1080p 모니터용)
- Orientation: SCREEN_PORTRAIT 강제

### 2-2. Stretch 설정

- **Mode**: `canvas_items` (UI는 네이티브 해상도, 스프라이트는 픽셀 룩 유지)
- **Aspect**: `keep` (2026-05-29 확정) — 디자인 360×780 전체를 비율 유지하며 화면에 맞춰 확대/축소, 안 맞는 부분은 **레터박스(여백)**. 게임 전체가 항상 정상 비율로 보임.
- **Texture Filter**: 전역 `nearest` (픽셀 아트 룩)

> 변천: keep→expand→keep_height→cover(SubViewport)→**keep**. expand/keep_height는 비율이 바뀌 때 보이는 영역이 달라져 배치가 틀어졌고, cover는 가로(16:9) 웹 프레임에서 세로 게임이 과확대돼 깨졌다. 임의 비율에서 전체 화면을 보장하기 위해 `keep`을 사용한다.

### 2-3. 적응 동작 (keep)

- 화면 비율이 360×780(9:19.5)과 **같으면**: 여백 없이 꽉 참.
- 비율이 **다르면**: 게임 전체가 비율 유지된 채 가운데 정렬되고, 남는 쪽에 레터박스 여백.
  - 세로 폰(9:19.5~9:21): 여백 미미.
  - 가로/4:3 프레임: 게임은 가운데 세로로 정상 표시 + 좌우 여백.
- 모든 비율에서 **배치·입력 모두 네이티브로 안정** (게임이 항상 360×780 좌표계).

### 2-4. 안전 영역 가이드

- 상단 ~60px: 상태바·노치 회피용 (현재 HUD 40px이므로 여유 있음)
- 하단 ~40px: 홈 인디케이터 회피용 (BottomLabel 영역과 일치)

## 3. 화면 영역 / 레이아웃

`scenes/main.tscn`의 노드 구조와 각 영역의 anchor:

| 노드 | 역할 | Anchor / Offset |
|---|---|---|
| `Main` | 루트 Control, fill | preset 15 (전체) |
| `ParallaxBackground` | 배경 (CanvasLayer, layer = -10) — `ParallaxLayer` + `Sprite2D`(`bg_01.png`) 구조. 가로 무한 타일링(`motion_mirroring`)으로 PC run 시뮬레이션에 맞춰 좌로 흐름 | layer 단위, 화면 전체 |
| `TopHUD` | 상단 HUD — **가로 시트 바(#23=`UISkin.R_TOPBAR`, 9-slice 가로 가득) 배경**(`game.gd._build_top_bar`, y6~52) 위에 [가장 왼쪽 ~46px 비움=프로필 예약 슬롯] · 닉네임(=계정, `account_label` 좌측) · 골드/다이아 칩(가로 나란히, 우편/설정 버튼 자리 확보 위해 좌측 이동 gold_x=102/dia_x=184) · 우편함 버튼(`icon_mail`, 바 오른쪽 끝의 설정 왼쪽) · 설정 버튼(`icon_settings`, 바 오른쪽 끝). 그 아래로 스테이지 배너(y58~)·BOSS 배지 | top anchor (자식이 52 아래로 확장) |
| `Arena` | 게임 영역 | top(40) ~ bottom(-308), 비율 따라 늘어남 |
| `Arena/Player` | PC 스프라이트 | 동적 (코드 제어) |
| `TicketBackground` | 스크래치 영역 뒤편 티켓 디자인 배경 (Sprite2D, `assets/ui/ticket_bg_01.png`) — 영역과 독립 (Main 자식, 화면 절대 좌표) | sibling order에서 ScratchCardArea보다 앞에 위치 (카드보다 뒤에 그려짐) |
| `ScratchCardArea` | 스크래치 카드 영역 | 하단 anchor (-308 ~ -38) |
| `ScratchCardArea/CardBackground` | 카드 영역 어두운 배경 (현재 visible=false, 임시 비활성) | fill |
| `BottomLabel` | 안내 텍스트 | 하단 anchor (-33 ~ 0) |
| `TopHUD/StageLabel` + 진행 게이지 + `BOSS` 배지 | 중앙 상단 스테이지 배너 — **#2 시트 프레임 칩**(`UISkin.header`) 안에 `"스테이지 N"` 라벨 **가로·세로 중앙 정렬**, 그 아래 **진행 게이지**(§5-3) + `BOSS` 배지. 코드 생성 `game.gd._build_stage_banner` | 중앙 상단(라벨 .tscn, 칩/게이지/배지는 코드 배치) |
| `ScratchBackdrop` (코드) | 스크래치 영역 뒤 배경 프레임 (#16 시트, `UISkin.scratch_bg`, `game.gd._build_scratch_bg`) — 내비 아래~화면 바닥, 티켓/카드보다 뒤에 그려짐 | 코드 배치 |
| `NavDock` | 하단 고정 내비 도크 (코드 빌드 Control, `scripts/nav_dock.gd`) — **강화/장비/유물/모험/상점** 5탭. **강화·장비·유물·상점 동작**(장비=보유 인벤토리, 유물=보유/장착 관리[2026-06-10], 상점=소환 메뉴; 2026-06-09). **던전만** "준비 중" 토스트(`_on_nav_tab`의 default 분기 — **주요 컨텐츠 예정 = [[던전 시스템 정리본]]("시련의 탑")**, 설계 확정·코드 미착수. 2026-06-18 '모험'→'던전' id `adventure`→`dungeon`). 2026-06-08 '스킬'→'유물'(`nav_dock.gd` id `skill`→`relic`). **탭 음영(잠금) = `set_locked(id, on)`**(modulate, 누름은 통과): ①**유물 탭 = 스테이지 10 클리어 전 음영**(진입 시 "스테이지 10을 클리어하면 열립니다" 토스트, [[족보 스킬 시스템 정리본]] §5-4) ②**튜토리얼 단계별 음영/강조**([[튜토리얼 시스템 정리본]] §4 — `game._update_nav_tab_locks`). 전투↔스크래치 사이 고정 밴드 | 코드 배치 (밴드 top `NAV_TOP_Y=490`, height `HEIGHT≈58`) |
| `UpgradePanel` | 강화 패널 (코드 빌드 하단 시트, `scripts/upgrade_panel.gd`) — 전투·내비 도크를 가리지 않고 **스크래치 영역만**(내비 바 아래 ~ 화면 바닥) 덮음. 서브탭 강화/성장/승급(강화만 구현), 드래그/스와이프 스크롤 | 코드 배치 (top `NAV_TOP_Y+HEIGHT` ~ 화면 바닥) |
| `ShopPanel` | 상점 패널 (코드 빌드 오버레이, `scripts/shop_panel.gd`) — 내비 "상점" 탭. 레퍼런스(슬레이어 키우기) 소환 화면식: 카테고리 탭(소환/패키지/재화) + 서브탭(장비/유물) + 좌측 캐릭터 슬롯(빈 프레임 placeholder — 컷인 미사용, `assets/shop/summon_char.png` 드롭 시 표시)·안내 + 우측 소환 리스트(데이터 `pools`마다 1행). **소환>장비 = 가챠(1회 / 11연차, 다이아 — 시스템 상세 [[BM 시스템 정리본]] §4)** + 전체화면 결과 팝업(희귀도색 카드). **재화 = 유물 가루 구매(다이아 결제, 2026-06-17 — `dust_shop`/`buy_dust_with_dia`)**, 패키지 = 준비 중. 광고 버튼·소환 레벨바 = 비활성 placeholder. **탭·좌측 캐릭터 영역은 패널 크기에 고정, 우측 소환 리스트만 세로 스크롤**. **소환 > 유물 서브탭은 스테이지 10 클리어 전 음영 + 진입 시 토스트**(유물 탭과 통일 — `_select_sub` 게이트, [[족보 스킬 시스템 정리본]] §5-4) | 코드 배치 (top `NAV_TOP_Y+HEIGHT` ~ 화면 바닥 — **강화 패널과 동일 밴드**, 전투·내비 안 가리고 스크래치 영역만 덮음) |
| `EquipmentPanel` | 장비 인벤토리 (코드 빌드 오버레이, `scripts/equipment_panel.gd`) — 내비 "장비" 탭. **헤더 = 무기/방어구 종류 탭**(강화 패널 탭과 동일 위치·크기: `0×40`·font16·subtab) **+ 닫기**(#26 팔각, 43×40). 그 아래 한 줄에 **장착 현황 라벨 + 합성 버튼**(우). 그 아래 **보유 인스턴스 목록**(행: 이름·강화레벨·스탯 보너스 + 장착/장착중 + 강화비용[🪙]). 등급↓레벨↓ 정렬. 데이터=`BackendService.get_equips`/`Gacha.item_info`·`equip_bonus`. 장착=`set_equipped`·강화=`enhance_equip`·합성=`combine_equips`(→`changed`→game HUD·최대HP 갱신) | 코드 배치 (강화/상점과 동일 밴드, 스크래치 영역만) |
| `RelicPanel` | 유물 보유/장착 패널 (코드 빌드 오버레이, `scripts/relic_panel.gd`, 2026-06-10) — 내비 "유물" 탭. **보유/장착(5슬롯) 관리 전용**(헤더=가루 잔액+닫기). 유물 뽑기는 여기가 아니라 **상점 > 소환 > 유물**(가루 소비). 변경 시 분포·HUD 즉시 반영(`Events.relics_changed`) | 코드 배치 (강화/상점과 동일 밴드, 스크래치 영역만) |
| `TopHUD/SettingsButton` | 설정 버튼 — 텍스트 없이 **`icon_settings` 아이콘 버튼**(#19 시트 배경 스킨, `game.gd._build_top_bar`+`_set_button_icon`). 누르면 설정 메뉴(§10-2) | 우측 anchor, 38×38 (offset -44~-6) |
| `TopHUD/MailButton` (코드) | 우편함 버튼 (2026-06-11) — 설정 버튼 바로 왼쪽. 텍스트 없이 **`icon_mail` 아이콘 버튼**(#19 시트 배경 스킨, 설정과 통일). 받을 보상 있으면 자식 **`RedDot`**(빨간 점, `scripts/red_dot.gd`)로 표시. 누르면 `_on_mailbox_pressed` → `UIManager.open_overlay("mailbox")`(`MailboxPanel`) | 우측 anchor, 38×38 (offset -84~-46) |
| `TopHUD/QuestButton` (코드) | 퀘스트 버튼 (2026-06-12) — 설정 버튼 **바로 아래**(상단 바 아래, 우측 정렬). **`icon_quest.png` 아이콘만(배경 없음 — 투명 버튼)**. 메일·설정의 `#19` 우드 박스와 달리 배경 스킨을 안 쓰고 `flat`+`StyleBoxEmpty`(전 상태)로 아이콘만 노출(`_set_button_icon` LINEAR·여백 2, **40×40 버튼·아이콘 36px**, 2026-06-15 텍스트→아이콘→배경제거→크기조정). 받을 **일일** 퀘스트 있으면 자식 **`RedDot`**로 알림. 누르면 `_on_quest_pressed` → `UIManager.open_overlay("quest")`(`QuestPanel` — 일일 퀘스트 전용). ⚠️ 위치 잠정 | 우측 anchor, offset -46~-6 / 상단 바 아래(`bar_bottom+4 ~ +44`) |
| `QuestTracker` (코드) | 메인 퀘스트 상시 트래커 (2026-06-12, `scripts/quest_tracker.gd`) — 내비 도크 위 우측에 떠 있는 위젯. **다음 미수령 메인 퀘 1개**만 목표 설명·진행바·x/target로 표시, 완료 시 클릭=수령→즉시 다음 노출, 전부 수령 시 숨김(수령 시퀀스 우편함 미러). 튜토리얼 중 숨김. 오버레이보다 먼저 add(딤이 트래커를 덮게) | 코드 배치 (우측 anchor, offset -158~-8 / `NAV_TOP_Y-66 ~ NAV_TOP_Y-8`) |
| `QuestPanel` (코드) | 일일 퀘스트 패널 (2026-06-12, `scripts/quest_panel.gd`) — 전체화면 오버레이(`UIManager.register_overlay`, `panel_overlay_base` 재사용). 행: 제목·진행바·x/target·보상·받기. 수령 시퀀스 = 우편함 미러(`valid_rewards` 0개면 claimed 미표시) | 전체화면 오버레이 |
| `NotificationManager` (autoload) | **전역 알림/토스트 레이어** (`scripts/notification_manager.gd`, CanvasLayer layer 80, 2026-06-11) — 떴다 사라지는 알림의 단일 경로. 슬롯 4종: **top**(보상 `reward` — 상단 노랑 대형)·**bottom**(안내 `info` — 내비 "준비 중")·**panel**(패널 피드백 `panel_feedback`, "보유 골드 부족" 등 — 패널 글로벌 rect 기준 기존 위치 재현, `panel_overlay_base._toast`가 위임)·**hand**(족보 결과 `hand_result` — 화면 중앙). 같은 슬롯에 새 토스트가 뜨면 기존 즉시 제거(겹침 방지), 다른 슬롯은 공존. 업적 해금 칩은 별도 큐(금색 제목+설명, 여러 개는 순차). 씬 독립(전환에도 유지)·PROCESS_MODE_ALWAYS(컷인 pause 중에도 트윈 진행) | autoload CanvasLayer (씬 외부, 게임 UI 전부 위) |

> 화면 세로 배치(위→아래): **전투 영역(Arena) → 하단 내비 도크(NavDock) → 스크래치 카드(ScratchCardArea)**. 강화 등 메뉴 패널(UpgradePanel)은 내비 탭을 누르면 스크래치 영역 위로 겹쳐 뜬다. 구 단독 "강화 버튼"(`$UpgradeButton`)·전체화면 강화 오버레이는 폐지됨(내비 도크 탭으로 진입).

> 성장 4축 역할(2026-06-08): **강화**=골드 무한 수직 스탯 / **장비**=능력치+가챠(BM 기둥) / **유물**=슬롯 빌드 '재미'·수평·비파워 / **족보**=매칭 등급. ⚠️ **유물≠장비**(유물=빌드 재미, 장비=능력치+BM). 상위는 [[게임 컨셉 정리본]] 참조.

### 3-2. UI 스킨 (자체 시트, 2026-06-05)

코드빌드 UI(내비 도크·강화 패널·스테이지 배너·진행 게이지·HP 바·설정/구매/닫기 버튼·아이콘 슬롯)의 룩은 **`scripts/ui_skin.gd`(`UISkin`)** 한 곳에서 관리. 사용자 자체 시트 **`assets/ui/UI_sheet.png`**(다크 우드/판타지 톤)의 조각을 `AtlasTexture(region)`로 잘라 9-slice `StyleBoxTexture`/`NinePatchRect`로 사용.

- 역할→시트 영역은 `R_*` 상수(예: 패널 #15, 내비바 #1, 탭 #6, 구매 #3, 닫기 #26, 배너 #2, 진행바 #24, 아이콘 슬롯 #13, 스크래치 배경 #16, 설정 #19). **역할의 `R_*`만 바꾸면 룩 교체** — 시트가 바뀌면 `tools/scan_sheet.gd`로 좌표 재추출 후 갱신(번호는 `scenes/sheet_labeler.tscn` 뷰어로 확인).
- 다크 톤이라 패널/탭 위 텍스트는 밝게(크림·골드·초록). 상세·매핑 이력은 CLAUDE.md / 메모리(`reference_ui_skin`).
- **개별 아이콘 에셋**(`assets/ui/icon/`, UI_sheet와 별개 PNG, 2026-06-09): 재화=`icon_gold`/`icon_dia`(HUD 칩 좌측, `_make_currency_icon`), 닫기 버튼=`UISkin.skin_close_icon(btn)`(#26 팔각형 close 배경[9-slice 없이 `texture_margin 0` 통짜 스트레치] + `icon_close`[흰색 X를 크림색 `CLOSE_ICON_COLOR`로 틴트] 중앙·텍스트 없음·`icon_max_width=20`). 강화/상점/장비 패널 코너 닫기에 적용(설정/치트의 전체폭 메뉴 버튼은 텍스트 유지). **재화 비용 표시**(상점 소환 다이아·강화/장비강화 골드)에도 동일 아이콘 — 버튼 `icon`(`icon_max_width`) 또는 TextureRect로 비용 숫자 앞에 표기(2026-06-09).
- **시트 번호 뷰어**(`scenes/sheet_labeler.tscn`): UI_sheet에 조각별 #번호·외곽선 오버레이(사용자가 "#N"으로 조각 지칭용). `RECTS`=`tools/scan_sheet.gd` 추출값(인덱스=ui_skin R_* 매핑). **시트 변경 시 scan_sheet 재실행 → ui_skin R_* + labeler RECTS 둘 다 갱신**(2026-06-09 갱신: 31개).

## 4. 상단 HUD

상단 HUD는 **가로 시트 바(#23) 배경 위에 한 줄로 정렬**(2026-06-08 레퍼런스식 재구성, `game.gd._build_top_bar`). 가로 순서: [가장 왼쪽 ~46px 비움=프로필 예약] → 닉네임 → 골드/다이아 칩(가로 나란히) → 우편함 버튼(`icon_mail` + RedDot) → 설정 버튼(`icon_settings`, 둘 다 오른쪽 끝).

- **배경 바 (#23 시트, 9-slice 가로 가득)**: `UISkin.top_bar()`(`R_TOPBAR`)를 `y6~52` 범위에 깔고 맨 뒤로. ⚠️ 임시 placeholder(추후 UI 에셋 교체).
- **프로필 (`AccountLabel`, 좌측, offset_left 46)**: `"구글"` 또는 `"게스트"` 표시. font_size 12, 크림색(`Color(0.96,0.93,0.82)`)+그림자. `game.gd._refresh_account_label()`.
- **골드/다이아 (가로 나란히 칩)**: 각 재화는 검은 반투명 둥근 칩(`_make_chip`, `Color(0,0,0,0.55)`) 위에 **아이콘(`assets/ui/icon/icon_gold`·`icon_dia`, `_make_currency_icon`, Linear 필터) + 숫자**로 표기(2026-06-09 — 구 "골드/다이아" 텍스트 prefix 제거, 아이콘이 칩 좌측). 통화는 단일 골드가 아니라 **다중(골드/다이아)**.
  - 골드(`ScoreLabel`/`gold_label`): 숫자 N(§5-4 포맷, 좌측 금화 아이콘), font_size 11, **노란 `GOLD_COLOR`**. `_refresh_hud()`가 `BackendService.get_gold()`로 갱신. 골드 뒤 검은 백판(`ScoreBackground` ColorRect)은 제거됨(칩+그림자로 가독성). ⚠️ `main.tscn`에는 `ScoreBackground`/`ScoreLabel` 노드가 잔존하나 `game.gd._ready`가 `ScoreBackground`를 런타임 `queue_free()`로 정리. *(점수/타이머는 방치형 피벗(2026-06-01)으로 폐기 — 메인 재화는 골드)*
  - 다이아(`_dia_label`): 숫자 N(§5-4 포맷, 좌측 다이아 아이콘), font_size 11, **하늘색 `DIA_COLOR`**(`Color(0.45,0.8,1.0)`). `_refresh_hud()`가 `BackendService.get_dia()`로 갱신. 획득처 = 치트 패널 + 현재 **퀘스트 보상**(메인·일일, `quests.gd` 카탈로그 대부분이 다이아 지급)·**우편함**(`mailbox.gd` 일부 우편)도 지급하나, 이는 **임시 더미 지급**이며 **정식 획득 곡선·밸런스는 미설계**(TBD). 소비처 = **상점 > 소환 > 장비**(장비 가챠, `ShopPanel`). 상점 패널 안에는 다이아를 중복 표기하지 않음(상단 HUD 상시 노출).
- **우편함 버튼 (`MailButton`, 설정 바로 왼쪽, 38×38)**: 텍스트 없이 **`icon_mail` 아이콘**(`_set_button_icon`) + **#19 시트 배경 스킨**(설정과 통일). 받을 보상 있으면 자식 **`RedDot`**(빨간 점, `scripts/red_dot.gd`, `set_active(on)`)로 알림. 누르면 `_on_mailbox_pressed` → `UIManager.open_overlay("mailbox")`(`MailboxPanel`). (2026-06-11 신설)
- **설정 버튼 (`SettingsButton`, 바 오른쪽 끝, 38×38)**: 텍스트 없이 **`icon_settings` 아이콘**(`_set_button_icon`) + **#19 시트 배경 스킨**(`UISkin.skin_button(.., "settings")`). 누르면 계정 설정 메뉴 — [[설정 시스템 정리본]]. (2026-06-11 텍스트 "설정" → 아이콘)
- **퀘스트 버튼 (`QuestButton`, 설정 버튼 바로 아래, 우측 정렬)**: **`icon_quest.png` 아이콘만(배경 없음 — 투명 버튼)**. 메일·설정의 #19 박스와 달리 배경 스킨 없이 아이콘만(2026-06-15 텍스트→아이콘→배경제거). 받을 **일일** 퀘스트 있으면 자식 **`RedDot`**로 알림. 누르면 `_on_quest_pressed` → `UIManager.open_overlay("quest")`(`QuestPanel`, 일일 전용). 메인 퀘스트는 상단 버튼이 아니라 **상시 트래커**(`QuestTracker`, 내비 도크 위)로 노출. (2026-06-12 신설, 위치 잠정)

⏸ **상단 HUD PC 체력바는 현재 비활성**: `_build_hp_bar()`(좌측 녹색 마스크 바, §5-3 구조)는 함수·머리 위 PC HP 바와 함께 유지되나 `_ready`에서 **호출하지 않음**(언제 쓸지 미정). 따라서 현재 PC HP 표시는 **머리 위 PC 체력바(§5-1)로 대체**된다.

데미지 플로터·적/PC 머리 위 체력바는 캐릭터 위에 표시(§5). HUD 한 줄 = 닉네임 + 골드/다이아 + 설정.

## 5. 캐릭터 UI

### 5-1. 머리 위 체력바

- **적/보스** 머리 위 ProgressBar (공용 `scenes/hp_bar.tscn` 50×8, `enemy.tscn` instance, `enemy.gd`가 값 갱신 + `_style_hp_bar`로 스타일).
- **PC** 머리 위 ProgressBar (`player_controller`가 생성). 일반몹도 PC를 공격하므로 **교전 중 항상 표시**(튜토리얼 중엔 숨김). 좌상단 HUD에도 PC 체력바가 있어 둘 다 표시(§4).
- **색 규칙 (2026-06-05): 차있는 부분 = 색 / 깎인 부분 = 검은색에 가까운 어두운 회색**(`Color(0.12,0.12,0.14)`). PC 채움 = **녹색**(`Color(0.27,0.82,0.32)`), 몬스터 채움 = **빨강**(`Color(0.85,0.27,0.24)`). StyleBoxFlat(코너 2px) 코드 스타일.

### 5-2. 데미지 플로터

- 캐릭터 머리 위에 떠오르는 텍스트. 형식: 공격 `n`(적/보스 머리 위), 피격 `-n`(보스/잡몹에게 맞는 PC 머리 위).
- 공격 플로터는 전투 2레이어에 맞춰 **차등**(`Effects.spawn_damage_floater`의 `big` 인자). **색은 2026-06-17에 노랑/금색 → 빨강 계열로 변경**(자동/스킬/피격을 밝기로 구분):
  - **일반 공격(자동)** = `big=false`: font 22, 진한 빨강 `DAMAGE_FLOATER_OUTGOING` = `Color(1.0, 0.28, 0.22)`, 위로 36px 상승.
  - **스크래치 스킬(버스트)** = `big=true`: font 36, 밝은 빨강 `DAMAGE_FLOATER_SKILL` = `Color(1.0, 0.45, 0.35)`(신규 상수, 구 금색 `Color(1.0,0.85,0.2)` 폐기), 스케일 팝, 위로 52px 상승.
- 피격(`-n`)은 연한 붉은 `DAMAGE_FLOATER_INCOMING` = `Color(1.0, 0.4, 0.4)`.
- **✅ 스킬 버스트 = 다타격(연타) 연출 (2026-06-17, `game._skill_multihit`)**: 스킬 1회가 족보 count만큼 연속 타격(`SKILL_HIT_INTERVAL` 0.05s 간격), 한 타 = 총딜/타수(누적 반올림 → **총합·밸런스 불변**, "쪼개기"). 플로터를 `jitter`로 흩뿌려 **다다다닥** 표현. 마지막 타 전엔 HP를 최소 1로 클램프해 **약한 적도 마지막 타에 처치**. 잭팟(count ≥ `AOE_MIN_COUNT`=9)은 살아있는 무리 전체에 각 타 적용. 튜토리얼은 단일 타격. (구 `_skill_aoe`는 `_skill_multihit`로 통합·폐기.) 의도 상세 [[전투 시스템 정리본]] §3-3.
- 동작: 시작 위치에서 위로 상승(36/52px) + 알파 → 0, 총 0.8초. 검정 그림자(alpha 0.75, offset 2px).
- 스킬 버스트엔 족보 티어별 연출이 추가된다: 화면 흔들림(`Effects.screen_shake` — 잭팟 ≥9 화면 전체 강하게 / 고족보 ≥4 전투영역 중간 / 그 외 약하게)과 더미 스킬 이펙트(`Effects.spawn_skill_effect`, 족보 count 티어별).
- HUD 카테고리로 분류 (캐릭터 따라가는 좌표지만 카메라 도입 시에도 카메라 영향 없음).

### 5-3. 스테이지 진행 게이지 (2026-06-05)

스테이지 배너(§3) 아래 가로 게이지 — 잡몹 처치 진행도(`mobs_killed / MOBS_PER_STAGE`). 좌상단 HUD PC 체력바(§4)도 같은 구조(색·구동값만 다름).

- **구성 = 시트 바 + 마스크**: #24 초록 바(`UISkin.R_BAR_FILL`)를 균일 스트레치로 깔고, 그 위 **어두운 마스크(ColorRect)**를 덮어 **진행도만큼 왼쪽부터 마스크를 걷어** 초록 노출(`_bar_mask.anchor_left = 진행도`). ProgressBar의 fill 9-slice 크롭이 어색해 채택.
- **마스크 정렬**: #24 아트(`UISkin.R_BAR_FILL` = `Rect2(30, 1416, 465, 27)`)의 초록 채움 bbox를 `tools/scan_bar.gd`로 스캔(좌·우 캡 5px 대칭 — x[5..460]/465, y[5..22]/27) → 분수 anchor(`_build_masked_bar`의 `G_L`/`G_R`/`G_T`/`G_B`)로 정확히 맞춰 양 끝 캡 장식은 안 가림. (2026-06-08 시트 교체로 scan_bar 재실행)
- **마스크 세로 정렬 폴리시 (2026-06-08)**: 초록은 비트맵 스케일, 마스크 밴드는 벡터라 래스터화 픽셀 반올림으로 ~1px 어긋나 하단에 초록이 노출되던 잠복 버그 → `inner`를 `MASK_Y_NUDGE≈1.0px` 아래로 시프트(상단 1px 확장 포함)해 초록 밴드에 정렬. 초록 밝기는 `modulate`로 보정, 바 두께는 절반(높이 ↓). 정렬이 안 맞으면 `MASK_Y_NUDGE` 한 값만 조정. 스테이지·HP 바 공용.
- **클리어 연출**: 마지막 몹/보스 처치로 스테이지를 넘기면 게이지 **100% 유지**(`_show_full_gauge`) + **이동 시간 ↑**(`STAGE_CLEAR_DELAY` 1.3s, 일반 `POST_KILL_DELAY` 0.6s), 다음 몹 조우(`_enter_idle`)에서 0% 리셋. 보스 스테이지는 1.0 고정.

### 5-4. 재화 숫자 포맷 / 색 (2026-06-08)

골드·다이아 표시 규칙. **포맷 단일 출처는 `UISkin.fmt_currency`(`scripts/ui_skin.gd`)** — `game.gd._fmt`는 `return UISkin.fmt_currency(n)` 1줄 위임이다(구 `game.gd`의 `FMT_*`·`_comma`는 폐기되고 정책·상수가 `ui_skin.gd`로 이전). 옛 'K/M/B 축약·흰색'을 다음으로 교체(정책 동일):

- **포맷(`UISkin.fmt_currency`)**: `FMT_RAW_MAX`(10억=1e9) 미만은 **콤마 raw**(예 `12,345,678`). 그 이상은 **`FMT_STEP`(1000)씩 나눠 접미사**(`FMT_SUFFIXES` = `K`·`M`·`B`·`T`·`Q`)를 붙이되 **접미사 앞 숫자(mantissa)는 10억 미만으로 유지** → 10억 = `1,000,000K`, 1조 = `1,000,000M`, 1e18 = `1,000,000T`. (큰 수를 그대로 보이게 하는 의도.) 노브: `ui_skin.gd`의 `FMT_RAW_MAX`/`FMT_STEP`/`FMT_SUFFIXES`, 콤마는 `_comma_num()`. (구 `UISkin.fmt_abbrev`[천부터 K]는 폐기.)
- **색 고정**: 골드 = 노란 `GOLD_COLOR`(`Color(1.0,0.84,0.25)`), 다이아 = 하늘 `DIA_COLOR`(`Color(0.45,0.8,1.0)`).

## 6. PC 위치 / 크기 데이터

PC의 화면상 위치·크기·속도는 `scripts/player_data.gd`의 const로 관리. `main.tscn`의 Player 노드 position/scale은 placeholder이며 `_ready()`에서 PlayerData 값으로 덮어쓴다. **튜닝은 `player_data.gd`에서.**

| 키 | 의미 |
|---|---|
| `HOME_X` | PC X 좌표 (Arena 좌상단 기준). attack 잽도 이 값 기준 |
| `Y_FROM_BOTTOM` | PC 중심 Y (Arena 하단 기준 위로 N px). 비율 변경 시 자동 적응 |
| `VISUAL_SCALE` | 스프라이트 다운스케일 (256×256 텍스처 × 0.4 = 화면상 ≈102×102) |
| `RUN_SPEED` | run 상태 이동 속도 (px/sec) |

## 7. 스크래치 카드 UI

### 7-1. 그리드 구성

- 3×3 그리드, 각 셀에 sub-cell 격자 (**10×10 = 100개**, 2026-05-29)
- 1~9 무작위 숫자, 셀 배경은 **테두리 타일**(Panel+StyleBoxFlat, 베이지 바탕+어두운 테두리)
- sub-cell 덮개는 **코팅 이미지**(`assets/ui/scratch.png`)를 칸마다 같은 이미지로, 6×6→10×10 조각(`AtlasTexture`)으로 슬라이스해 덮음. 긁으면 조각이 사라짐.
- 그리드 크기·sub-cell 분할·브러시 반경·완료 임계값은 `scratch_card.gd`의 `@export`에서 조정 (자세한 건 스크래치 시스템 기획서 7번)

### 7-2. 활성 / 잠금 상태 시각

#### 시각

- **잠금 상태**: 카드 전체 `modulate = LOCKED_TINT (0.45, 0.45, 0.45, 1.0)` — 색만 어둡게, 불투명 (뒤편 숫자 안 비침)
- **활성 상태** (idle 진입 시): `ACTIVE_FLASH_TINT (1.5, 1.5, 0.8, 1.0)` → 흰색으로 0.4초 트윈 (노란 펑 강조)

#### 잠금/활성 타이밍

| 시점 | 처리 |
|---|---|
| 게임 시작 직후 | 잠금 (PC 첫 출현 idle 동안 카드 비활성) |
| run 진입 (게임 시작 첫 run, 적 사망 후 run) | 잠금 유지 + `reset_card()`로 새 카드 발행 |
| 적 조우 → PC idle | 잠금 해제 + 활성 이펙트 발동 |
| 9칸 완료 (`_complete()`) | `is_locked = true`로 즉시 잠금만(자체 타이머 해제 없음). 해제는 game.gd가 상태에 맞춰 소유 — 조우→idle 시 해제(`_enter_idle`) / 적 생존 시 `reset_card()`로 새 카드+해제 / 이동·처치 중엔 잠금 유지. (구 `lock_duration` @export는 코드에서 완전 제거됨) |
| **적 사망 즉시** | 잠금 + LOCKED_TINT 즉시 적용 (사망 ~ run 시작 사이 1초 동안 카드 못 긁게) |
| 1초 대기 후 run 진입 | 잠금 유지하면서 reset_card |

#### reset_card 호출 시점

| 시점 | reset 호출? |
|---|---|
| attack 종료 시점에 적이 살아있을 때 | ✅ 호출 (새 카드, 잠금 해제) |
| attack 종료 시점에 적이 사망했을 때 | ❌ 호출 안 함 (사망 처리에서 잠금 유지 우선) |
| run 진입 시 | ✅ 호출 (새 카드, 잠금은 외부에서 유지) |

위 분기 덕분에 "사망 즉시 카드 잠금 → 1초 후 새 카드"라는 일관된 흐름이 보장된다.

### 7-3. 70% 완료 피드백 (셀 단위)

한 셀의 sub-cell이 **70%(`completion_threshold`) 이상 사라지거나, 가운데 정사각 영역(`center_complete_ratio`=0.5)이 전부 긁히면**(둘 중 하나, OR — `_center_cleared`, 2026-06-17 추가) 셀 완료 처리. 가운데 조건은 **수동 긁기 전용**(자동은 칸 전체를 한 번에 벗겨 무관). 완료 시 세 가지 시각 효과 동시 발동:

1. **남은 sub-cell 일제 페이드아웃** (0.15초) — "더 긁을 필요 없음" 신호
2. **셀 배경 노란 플래시**: 베이지 → `Color(1.0, 0.95, 0.5)` → 베이지 (0.1 + 0.25초)
3. **숫자 라벨 펑**: scale 1 → 1.3 → 1 (BACK ease, 0.12 + 0.2초)

### 7-4. 9칸 전체 완료

- `_complete()`가 `is_locked = true`로 카드를 즉시 잠금(자체 타이머 해제 없음 — 잠금/해제는 game.gd가 소유)
- `card_completed` 시그널 발생 → 화면 중앙 족보 결과 토스트(`NotificationManager.hand_result(value, count, jackpot)`) 표시
- 새 카드 생성은 attack 모션 종료 후 외부(game.gd)가 `reset_card()` 호출
- ⚠️ 과거엔 `lock_duration`초 후 자체 해제했으나 이동 중 재긁힘 버그를 유발해 제거됨 — `lock_duration` @export도 코드에서 완전 삭제됨

## 8. 족보 결과 (NotificationManager.hand_result)

9칸 완료 시 화면 중앙에 큰 텍스트 표시. 2026-06-11에 씬 노드 `HandResultLabel`(+`Effects.show_hand_result`/`_spawn_jackpot_tag`)을 제거하고 autoload 토스트 `NotificationManager.hand_result(value, count, jackpot)`("hand" 슬롯)로 이전(연출 수치 동일):

- 형식: `"{value} X {count} {!*count}"` (예: `1 X 3 !!!`, `7 X 9 !!!!!!!!!`)
- font_size 44, 노란 (`Color(1, 0.95, 0.35)`), 검정 그림자 (offset 3px)
- 모션: scale 0.3 → 1.0 (BACK ease, 0.18초) → 0.5초 유지 → 알파 페이드 (0.3초)
- 잭팟(count ≥ `JACKPOT_COUNT`) 시 아래에 금색 `JACKPOT` 태그 동반(`_jackpot_tag`).
- HUD 카테고리 (캐릭터 위치 무관, 화면 중앙 고정)

## 9. 전투 이펙트

### 9-1. 임팩트 burst

- 적이 데미지 받는 순간, 적 머리 위 근처에 흰 사각형이 잠깐 표시
- 20×20 ColorRect → scale 2.5, 알파 → 0 (0.25초)

### 9-2. 폭발 (적 사망)

더미 폭발 — ColorRect 기반:

- **코어**: 36×36 노란 사각형, scale 1 → 2.8, 알파 → 0 (0.3초)
- **파편 12개**: 4~8px 정사각형, 무작위 색상(노랑·주황·빨강) + 무작위 각도(±0.15rad 흔들림) + 무작위 속도(70~130 px/sec). 0.6초간 위치 이동 + 알파 페이드.
- **적 본체**: scale 0.4 + 알파 → 0 (0.2초). 폭발에 휩쓸려 사라지는 느낌.

### 9-3. 피격 플래시

본체 Sprite에 빨간 modulate 잠깐 적용:
- 적: 데미지 받을 때 `Color(1.6, 0.5, 0.5)` 0.05초 → 흰색 0.15초.
- PC: **보스에게** 맞을 때 `Color(2.0, 0.5, 0.5)` 0.05초 → 흰색 0.2초.

### 9-4. PC 공격 모션 (2레이어)

PC 공격은 두 레이어로 나뉜다(전투 2레이어, [[전투 시스템 정리본]] §3 참조). 프레임 수는 고정 7이 아니라 시트 width / `FRAME_SIZE`로 자동 계산되며(`player_controller._build_animations`), 모든 모션 재생은 `player_controller._play()`를 경유해 시트별 크기 정규화·발끝 정렬을 거친다.

**(1) 일반 공격(자동) — `play_auto_attack`**

- 교전 중 **고정 주기**(`Balance.AUTO_ATK_SPEED` = 초당 횟수, 현재 3.3)마다 타이머로 자동 발동(`game.gd._auto_attack`). 2026-06-15 옛 `attack_speed`(공격속도) 강화 트랙은 폐지되고 그 max값(3.3)을 모두에게 기본 제공 — 자동공격 속도는 고정이며 DPS는 공격력(`attack`)으로만 성장.
- 가벼운 잽 모션(`HOME_X + 12`, modulate 강조 생략).
- 데미지(= 공격력 × `AUTO_ATK_COEF`)는 애니 종료를 기다리지 않고 **타이머 발동 시점에 즉시** 적용.

**(2) 스크래치 스킬(버스트) — `play_attack`**

- 9칸 완성 시 발동, attack 애니메이션과 **동기**되는 위치 트윈 + modulate 강조:
  - 위치: `HOME_X` → `HOME_X + 24` → `HOME_X` (잽 모션, 0.12 + 0.03 + 0.35 = 0.5초)
  - modulate: 흰색 → `Color(1.4, 1.4, 1.6)` → 흰색 (0.1 + 0.4 = 0.5초)
- 데미지(= 공격력 × 복권 배율 × 족보배율)·이펙트는 attack 애니 종료 시점(`attack_motion_completed`)에 적용 (트윈 종료와 일치).

### 9-5. 보스 공격 / PC 사망 (보스전 한정)

- **보스 공격**: 보스가 주기적으로 PC를 공격 → PC `attacked` 모션 + 피격 플래시(9-3) + 피격 플로터(5-2) + PC HP 감소.
- **PC 사망**: PC HP 0 → 진행 중 모션·트윈 취소 후 `PC_dead` 모션 재생 → 몇 스테이지 소폭 후퇴([[스테이지 시스템 정리본]] §5). 연출 상세 TBD.

## 10. 계정 / 랭킹 접근

게임오버가 없으므로(실패 조건 없음) 게임오버 패널도 없다. 계정 관련 동작은 **설정 메뉴**(§10-2)에서 접근한다.

- **로그아웃** → `BackendService.logout()` (현재 로컬 세션만 정리, 저장 파일 유지) → 로그인 화면 복귀
- **메인 메뉴** → `login.tscn`(메인 메뉴 역할 겸용)로 복귀
- **계정 탈퇴**(`BackendService.delete_account()`, 현재 로컬 프로필의 저장 파일 삭제): 배치 위치 미정(TBD).
- 동작 상세는 [[로그인 시스템 정리본]] 참조.

## 10-2. 설정 패널

우측 상단 `SettingsButton`(`icon_settings` 아이콘) → `SettingsPanel`(코드 빌드 오버레이). 구성: **사운드 섹션**(음소거 토글 + BGM·SFX 슬라이더, autoload `Audio` 직접 호출·즉시 반영·저장) + 계정 버튼 메인 메뉴(계정 변경) / 로그아웃 / 계정 탈퇴 / 닫기. **게임은 멈추지 않음**(방치형 — 일시정지 없음).

> 상세는 **[[설정 시스템 정리본]]** 참조.

## 11. 데이터 분리 위치 요약

UI 관련 튜닝 값의 위치 (어디서 수정하는지):

| 카테고리 | 파일 | 주요 키 |
|---|---|---|
| PC 위치/크기/속도 | `scripts/player_data.gd` | `HOME_X`, `Y_FROM_BOTTOM`, `VISUAL_SCALE`, `RUN_SPEED` |
| 적 등장 위치 | `scripts/enemy_data.gd` | `SPAWN_OFFSET_FROM_RIGHT`, `SPAWN_Y_FROM_BOTTOM`, `STOP_X` |
| 배경 (스케일/위치/스크롤) | `scripts/background_data.gd` | `SCALE`, `Y_OFFSET`, `SCROLL_SPEED_RATIO` |
| 스크래치 영역 (위치/크기/스케일) | `scripts/scratch_card_layout.gd` | `HEIGHT`, `WIDTH`, `BOTTOM_MARGIN`, `SCALE`, `X_OFFSET`, `Y_OFFSET`, `TICKET_BG_SCALE`, `TICKET_BG_X`, `TICKET_BG_Y` |
| UI 색상 | `scripts/ui_palette.gd` | `DAMAGE_FLOATER_OUTGOING`(자동 공격, 빨강), `DAMAGE_FLOATER_SKILL`(스킬 버스트, 밝은 빨강), `DAMAGE_FLOATER_INCOMING`(피격, 연한 붉은색) |
| 상단 바 / 재화 색 | `scripts/game.gd` | `_build_top_bar`/`_make_chip`/`_set_button_icon`, `GOLD_COLOR`·`DIA_COLOR`, `_fmt`(→`UISkin.fmt_currency` 위임) |
| 재화 숫자 포맷·콤마 | `scripts/ui_skin.gd` | `UISkin.fmt_currency`, `FMT_RAW_MAX`/`FMT_STEP`/`FMT_SUFFIXES`, `_comma_num` |
| 카드 잠금/활성 색 | `scripts/game.gd` | `LOCKED_TINT`, `ACTIVE_FLASH_TINT` (향후 `ui_palette.gd`로 이전 가능) |
| 데미지 플로터 위치 | `scripts/game.gd` | `ENEMY_FLOATER_OFFSET`(적), `PLAYER_FLOATER_OFFSET`(보스전 PC) |
| **이펙트 함수** (정적 헬퍼) | `scripts/effects.gd` | `Effects.spawn_*`, `Effects.flash_modulate` |
| 족보 결과 토스트 (중앙) | `scripts/notification_manager.gd` | `NotificationManager.hand_result(value, count, jackpot)` (구 `Effects.show_hand_result`+`HandResultLabel` 대체) |
| 퀘스트 UI (트래커/패널) | `scripts/quest_tracker.gd`·`scripts/quest_panel.gd` | 메인=상시 트래커, 일일=오버레이 패널. 카탈로그·판정=`scripts/quests.gd` |
| **PC 모션·상태** (노드 attach) | `scripts/player_controller.gd` | SpriteFrames 빌드, idle/run/attack(+보스전 attacked/dead) 모션, `attack_motion_completed` 시그널 |
| 스크래치 그리드/sub-cell/브러시 | `scenes/scratch_card.tscn` (인스펙터 `@export`) | `grid_cols`, `grid_rows`, `subdivisions_per_cell`, `brush_radius`, `completion_threshold`, `center_complete_ratio`, `cell_padding`, `number_min`, `number_max` |
| 체력바 사이즈 | `scenes/hp_bar.tscn` | `custom_minimum_size`, `offset_right`/`offset_bottom` |
| 화면 레이아웃 (각 영역 위치) | `scenes/main.tscn` | 각 노드 anchor·offset |

## 12. 미결정 사항 (TBD)

- ~~ProgressBar의 픽셀 아트 톤 일관화~~ → **대부분 적용됨**: 코드빌드 UI는 자체 시트 스킨(§3-2), 스테이지/HP 게이지는 시트 바+마스크(§5-3), 머리 위 체력바는 StyleBoxFlat 색 규칙(§5-1). 남은 더미: 폭발/스킬 이펙트(ColorRect), 스크래치 코팅
- 카드 잠금/활성 시각의 정식 색상 (`LOCKED_TINT`/`ACTIVE_FLASH_TINT`는 임시값)
- 데미지 플로터 색상 = 자동(진빨강)/스킬(밝은빨강)/피격(연한붉은색) 빨강 3종으로 1차 정리됨(`ui_palette.gd` 상수, 2026-06-17). 톤 미세조정 여지만 남음
- 폭발 정식 이펙트 (현재는 ColorRect 더미)
- 계정 탈퇴 버튼 배치 위치 (게임오버 패널이 없어 미정 — §10).
- 카드 잠금/활성 색을 `ui_palette.gd`로 이관할지 여부 (현재는 `game.gd`의 const)
- 배경 패럴랙스·정식 지면/하늘 텍스처 도입 시 레이아웃 재정리
