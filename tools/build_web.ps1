# 웹(HTML5) 빌드 → build/web/index.html  (kplay 진입점 = index.html)
#
# 사용:
#   powershell -ExecutionPolicy Bypass -File tools/build_web.ps1
#   (또는 세션에서)  ! powershell -File tools/build_web.ps1
#
# 빌드 후 테스트:  python tools/serve.py
#
# ⚠️ 주의 (reference_html5_build 메모리):
# - 로컬 테스트용 빌드는 에디터가 켜져 있어도 됨(godot-mcp autoload가 들어가지만 무해 — 콘솔에 무해한
#   "File not found" 에러만). kplay 정식 배포본은 에디터를 닫고 빌드해야 mcp 재주입을 막을 수 있음.
# - thread_support=false 단일 스레드 빌드.

param(
    [string]$GodotExe = "C:\Users\jaeyeop.im.SUPERCAT\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe",
    [string]$Preset = "Web",
    [switch]$Release   # release export로 빌드. 기본=debug export — 치트 게이트(CHEAT_ENABLED and OS.is_debug_build())가 로컬 웹 테스트에서 살아있게. 배포는 deploy_kplay.ps1이 자체적으로 release 빌드.
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $ProjectDir "build\web"
$OutFile = Join-Path $OutDir "index.html"

if (-not (Test-Path $GodotExe)) {
    Write-Error "Godot 실행 파일 없음: $GodotExe  (-GodotExe 로 경로 지정)"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# build/.gdignore 자가 복구 — 없으면 에디터가 빌드 산출물을 임포트(UID 오염·pck 재귀 패킹).
# (.gitignore가 build/* 라 재클론/클린 시 사라질 수 있어 빌드 때마다 보장)
$GdIgnore = Join-Path $ProjectDir "build\.gdignore"
if (-not (Test-Path $GdIgnore)) { New-Item -ItemType File -Path $GdIgnore | Out-Null }

$ExportFlag = "--export-debug"
$Flavor = "debug"
if ($Release) { $ExportFlag = "--export-release"; $Flavor = "release" }
Write-Host "빌드 중($ExportFlag): $Preset -> $OutFile"
& $GodotExe --headless --path $ProjectDir $ExportFlag $Preset $OutFile

# 빌드 flavor 마커 — deploy_kplay.ps1 -SkipBuild 가 debug 산출물을 공개 업로드하지 않게 검사용.
Set-Content -Path (Join-Path $OutDir ".build_flavor") -Value $Flavor -Encoding Ascii

# 페이지 배경(레터박스 여백) 이미지를 build/web/로 복사 (index.html의 CSS가 frame_bg.png 참조)
$FrameBgSrc = Join-Path $ProjectDir "web\frame_bg.png"
if (Test-Path $FrameBgSrc) {
    Copy-Item $FrameBgSrc (Join-Path $OutDir "frame_bg.png") -Force
    Write-Host "여백 배경 복사: frame_bg.png"
}

if (Test-Path $OutFile) {
    Write-Host "완료: $OutFile"
    Write-Host "테스트:  python tools/serve.py"
} else {
    Write-Error "빌드 산출물이 없습니다. 위 출력에서 에러를 확인하세요."
}
