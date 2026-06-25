# kplay.games 배포 스크립트 — 웹 빌드 → 배포 zip → kplay CLI 업로드
#
# ⚠️⚠️ 배포는 사용자가 명시적으로 "배포해"라고 요청할 때만 실행할 것. 자동/임의 실행 금지. ⚠️⚠️
#   (코드 변경·빌드 후에도 이 스크립트를 자동으로 돌리지 말 것 — 업로드는 외부로 공개하는 행위)
#
# ── 사전 준비 (1회, 사용자가 직접 — 대화형이라 자동화 불가) ──────────────────────
#   1) npm install -g @kplay/cli        (Node 20+ 필요, 현재 v24 확인됨)
#   2) kplay login                       (브라우저 인증)
#   3) 첫 배포는 프로젝트 선택/생성이 대화형 → 직접 1회 실행:
#         kplay update .\build\web.zip   (먼저 이 스크립트 -SkipUpload 로 zip만 만든 뒤)
#      또는 새 프로젝트로:
#         kplay update .\build\web.zip --new --title "복권 키우기 : Idle RPG" --public
#      → 성공하면 프로젝트 루트에 .kplay.json 생성(프로젝트 ID 기억). 이후는 비대화형.
#
# ── 이후 배포 (사용자 요청 시) ────────────────────────────────────────────────
#   powershell -ExecutionPolicy Bypass -File tools/deploy_kplay.ps1            # 빌드+zip+업로드
#   powershell -File tools/deploy_kplay.ps1 -SkipBuild                          # 기존 빌드 그대로 업로드
#   powershell -File tools/deploy_kplay.ps1 -SkipUpload                         # zip만 만들고 업로드 안 함
#   powershell -File tools/deploy_kplay.ps1 -ProjectId abcdefg                  # 프로젝트 ID 지정(-p)
#
# 참고: 진입 파일은 index.html (kplay 강제). 빌드 산출물·zip 규칙은 build_web.ps1 / reference_html5_build.

param(
    [string]$GodotExe = "C:\Users\jaeyeop.im.SUPERCAT\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe",
    [string]$Preset = "Web",
    [string]$ProjectId = "",
    [switch]$SkipBuild,    # 빌드 건너뛰고 기존 build/web 사용 (⚠️ 기존 산출물이 release인지 .build_flavor 마커로 검사함)
    [switch]$SkipUpload,   # kplay 업로드 없이 zip까지만 (첫 배포 준비/검증용)
    [switch]$AllowCheats,  # CHEAT_ENABLED=true 인데도 업로드 강행(의도적일 때만). 단 release 빌드에선 OS.is_debug_build() 게이트로 치트가 어차피 비활성 — 배포본에서 치트를 진짜 살리려면 debug 빌드(-AllowDebug)까지 필요.
    [switch]$AllowDebug    # -SkipBuild 산출물이 debug여도 업로드 강행(의도적일 때만 — debug wasm은 크고 느리며 치트 게이트가 살아있음)
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$Web = Join-Path $ProjectDir "build\web"
$Zip = Join-Path $ProjectDir "build\web.zip"

# 캐시 버스팅: 매 배포마다 버전 토큰을 붙여 리소스 파일명을 바꾼다(새 URL → 캐시에 없어 무조건 새로 받음).
# Godot 로더는 executable 기반(${exe}.pck/.wasm/.audio.worklet.js)이라 executable만 바꾸면 됨.
# 버전 붙이는 리소스: index.<ext> → index.<v>.<ext>
$BustExts = @("js", "wasm", "pck", "audio.worklet.js", "audio.position.worklet.js")
# 그대로(버전 없이) 가는 파일: 진입 html + 파비콘 + 페이지 배경 (거의 안 바뀜)
# ⚠️ index.png(부트 스플래시 이미지)는 게임 배경으로 바뀌므로 버전화 대상(아래) — 고정 이름이면 옛 스플래시가 캐시돼 stale.
$StaticFiles = @("index.icon.png", "index.apple-touch-icon.png", "frame_bg.png")
$Deploy = Join-Path $ProjectDir "build\deploy"  # 버전화된 배포본(원본 build/web은 그대로 둠)

# ── 0) kplay CLI 확인 (업로드할 때만 필수) ──
if (-not $SkipUpload -and -not (Get-Command kplay -ErrorAction SilentlyContinue)) {
    Write-Error "kplay CLI 미설치. 먼저:  npm install -g @kplay/cli  →  kplay login  (자세한 건 이 파일 상단 주석)"
}

# ── 1) 웹 빌드 ──
$FlavorFile = Join-Path $Web ".build_flavor"   # build_web.ps1/이 스크립트가 빌드 시 기록(debug|release)
if (-not $SkipBuild) {
    if (-not (Test-Path $GodotExe)) { Write-Error "Godot 실행 파일 없음: $GodotExe  (-GodotExe 로 지정)" }
    New-Item -ItemType Directory -Force -Path $Web | Out-Null
    # build/.gdignore 자가 복구 (재클론/클린 대비 — 없으면 에디터가 빌드 산출물 임포트)
    $GdIgnore = Join-Path $ProjectDir "build\.gdignore"
    if (-not (Test-Path $GdIgnore)) { New-Item -ItemType File -Path $GdIgnore | Out-Null }
    Write-Host "[1/3] 빌드(release): $Preset -> $Web\index.html"
    & $GodotExe --headless --path $ProjectDir --export-release $Preset (Join-Path $Web "index.html")
    Set-Content -Path $FlavorFile -Value "release" -Encoding Ascii
    $FrameBg = Join-Path $ProjectDir "web\frame_bg.png"
    if (Test-Path $FrameBg) { Copy-Item $FrameBg (Join-Path $Web "frame_bg.png") -Force }
} else {
    Write-Host "[1/3] 빌드 건너뜀 (-SkipBuild)"
    # ⚠️ debug 산출물 공개 배포 가드: build_web.ps1 기본이 --export-debug 라서(2026-06-11),
    #    기존 build/web 이 debug 면 더 크고 느린 wasm + OS.is_debug_build()=true(치트 게이트 살아있음)가 올라간다.
    $flavor = if (Test-Path $FlavorFile) { (Get-Content $FlavorFile -TotalCount 1).Trim() } else { "" }
    if ($flavor -ne "release" -and -not $SkipUpload -and -not $AllowDebug) {
        if ($flavor -eq "") {
            Write-Warning "build/web 산출물의 빌드 flavor 마커(.build_flavor)가 없음 — 수동 빌드라면 release인지 직접 확인. debug일 가능성이 있으면 재빌드 권장."
        } else {
            throw "build/web 산출물이 '$flavor' 빌드 — 공개 업로드 차단됨. release로 재빌드(이 스크립트를 -SkipBuild 없이, 또는 build_web.ps1 -Release)하거나, 의도적이면 -AllowDebug 로 강행하세요."
        }
    }
}

# ── 2) 캐시 버스팅 + 배포 zip 생성 ──
# 원본 build/web 산출물이 다 있는지 먼저 확인
$srcNeeded = @("index.html", "index.png") + ($BustExts | ForEach-Object { "index.$_" }) + $StaticFiles
$srcMissing = $srcNeeded | Where-Object { -not (Test-Path (Join-Path $Web $_)) }
if ($srcMissing) { Write-Error "빌드 산출물 누락: $($srcMissing -join ', '). -SkipBuild 없이 다시 빌드하세요." }

# 버전 토큰(매 배포 고유) — 빌드 시각 unix초
$v = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
New-Item -ItemType Directory -Force -Path $Deploy | Out-Null

# 버전 리소스 복사 (index.<ext> → index.<v>.<ext>)
$DeployNames = @("index.html") + $StaticFiles
foreach ($ext in $BustExts) {
    Copy-Item (Join-Path $Web "index.$ext") (Join-Path $Deploy "index.$v.$ext") -Force
    $DeployNames += "index.$v.$ext"
}
# 부트 스플래시 이미지도 버전화 (splash=게임 배경이라 바뀜 → 고정 이름이면 옛 이미지 캐시 stale)
Copy-Item (Join-Path $Web "index.png") (Join-Path $Deploy "index.$v.png") -Force
$DeployNames += "index.$v.png"
# 정적 파일 복사 (그대로)
foreach ($f in $StaticFiles) { Copy-Item (Join-Path $Web $f) (Join-Path $Deploy $f) -Force }

# index.html 패치: 원본 build/web/index.html 기준(절대 패치 안 함) → 버전 참조로 바꿔 build/deploy에 기록
$html = [System.IO.File]::ReadAllText((Join-Path $Web "index.html"), (New-Object System.Text.UTF8Encoding($false)))
$html = $html -replace 'src="index\.js"', "src=`"index.$v.js`""
$html = $html -replace '"executable":"index"', "`"executable`":`"index.$v`""
$html = $html -replace '"index\.pck"', "`"index.$v.pck`""
$html = $html -replace '"index\.wasm"', "`"index.$v.wasm`""
$html = $html -replace 'src="index\.png"', "src=`"index.$v.png`""   # 부트 스플래시 <img> 도 버전화 URL로
[System.IO.File]::WriteAllText((Join-Path $Deploy "index.html"), $html, (New-Object System.Text.UTF8Encoding($false)))

# zip (build/deploy의 버전화된 파일들)
$Files = $DeployNames | ForEach-Object { Join-Path $Deploy $_ }
Compress-Archive -Path $Files -DestinationPath $Zip -CompressionLevel Optimal -Force
$ZipMB = [math]::Round((Get-Item $Zip).Length / 1MB, 2)
Write-Host "[2/3] zip(cache-busted v=$v): $Zip ($ZipMB MB, $($DeployNames.Count)개 파일)"

# 치트 게이트 (공개 배포면 반드시 꺼야 함) — 업로드는 하드 차단, zip-only는 허용.
# ⚠️ 이 게이트는 '현재 소스'만 검사 — 산출물(pck) 안의 값과 다를 수 있음(-SkipBuild + stale 빌드).
#    release 빌드에선 OS.is_debug_build() 이중 게이트로 치트가 어차피 비활성(2026-06-11)이지만,
#    debug 산출물엔 치트가 살아있으므로 위 .build_flavor 가드와 함께 이중으로 막는다.
$cheatOn = Get-Content (Join-Path $ProjectDir "scripts\game.gd") | Select-String "CHEAT_ENABLED\s*:\s*bool\s*=\s*true"
if ($cheatOn) {
    if (-not $SkipUpload -and -not $AllowCheats) {
        throw "CHEAT_ENABLED=true (치트 켜짐) — 공개 업로드 차단됨. game.gd에서 false로 바꿔 재빌드하거나, 의도적이면 -AllowCheats 로 강행하세요. (release 빌드는 is_debug_build 게이트로 치트가 비활성이긴 하나, 소스 false가 표준)"
    }
    Write-Warning "CHEAT_ENABLED=true (치트 켜짐). 업로드 강행/zip-only 진행 중 — release 빌드면 is_debug_build 게이트로 비활성이지만, 공개 배포라면 game.gd에서 false로 바꾸고 재빌드 권장."
}

# ── 3) kplay 업로드 ──
if ($SkipUpload) {
    Write-Host "[3/3] 업로드 건너뜀 (-SkipUpload). zip 준비됨: $Zip"
    return
}
$KplayArgs = @("update", $Zip)
if ($ProjectId) { $KplayArgs += @("-p", $ProjectId) }   # 미지정 시 cwd의 .kplay.json 사용(있어야 비대화형)
Push-Location $ProjectDir   # .kplay.json 을 프로젝트 루트 기준으로 읽도록
try {
    Write-Host "[3/3] kplay $($KplayArgs -join ' ')"
    & kplay @KplayArgs
    if ($LASTEXITCODE -ne 0) { Write-Error "kplay 업로드 실패 (exit $LASTEXITCODE)" }
    Write-Host "배포 완료."
} finally {
    Pop-Location
}
