# 컷인 일러스트

고족보 컷인(`scripts/cut_in.gd`)에 쓰는 일러스트를 여기에 둔다.

## 넣는 법
- 파일명: **`cutin.png`** (이 경로 고정: `res://assets/cutin/cutin.png`)
- `cut_in.gd`가 시작 시 이 파일이 있으면 **자동으로 사용**(없으면 PC 스프라이트 placeholder로 폴백).
- 에디터가 켜져 있으면 파일을 넣는 즉시 자동 임포트됨. (없으면 에디터 포커스 시 임포트)

## 권장 스펙
- **PNG, 투명 배경** (배경/밴드 위에 캐릭터만 떠 보이게 — 박스 없이 raw 표시됨).
- **세로형(portrait)** 권장 — 표시 슬롯이 세로로 긺(약 214×278). 비율 유지로 중앙 맞춤되니 비율은 자유.
- **크기**: 웹 다운로드 고려해 한 변 ~1024px 이하 권장. 더 크면 import에서 `process/size_limit`로 다운스케일 가능(타이틀 로고처럼).
- **필터**: 부드러운(비픽셀) 일러스트면 import에서 Filter=Linear로. 픽셀 아트면 기본(nearest) 유지.

## 표시 크기/위치 조정
`cut_in.gd play()`의 `iw`(폭) 공식과 holder offset으로 크기·위치 조정. 현재 잭팟(tier4) 기준 약 214px 폭.

## 여러 장(족보별/티어별)
지금은 단일 `cutin.png`. 추후 족보/티어별로 다르게 하려면 경로를 배열/딕셔너리로 확장(예: `cutin_jackpot.png`, `cutin_four.png`).
