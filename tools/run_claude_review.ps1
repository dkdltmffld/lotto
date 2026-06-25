param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Topic,

    [Parameter(Position = 1)]
    [string]$CodexNote = "",

    [string]$LogPath = "docs/review/codex_claude_review.md",

    [string]$Model = "sonnet",

    [ValidateSet("low", "medium", "high", "xhigh", "max")]
    [string]$Effort = "high"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw "claude CLI를 찾을 수 없습니다. Claude Code CLI 설치/로그인을 먼저 확인하세요."
}

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType File -Force $LogPath | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
$existingLog = Get-Content -Raw -Encoding UTF8 $LogPath

$prompt = @"
너는 이 Godot HTML5 모바일 세로 게임 프로젝트의 1:1 리뷰 파트너다.

역할:
- Codex의 의견을 그대로 반복하지 말고, 기획/코드 관점에서 반론, 누락, 리스크, 더 나은 대안을 제시한다.
- HTML5 Web Export, Godot 4.x, 모바일 세로 UX, kplay 저장/배포 제약을 우선순위 높게 본다.
- 확실하지 않은 내용은 추정이라고 표시한다.
- 실제 파일 수정은 하지 말고, 리뷰 의견만 한국어로 작성한다.

출력 형식:
## Claude Review

### 핵심 판단
짧게 결론.

### 동의하는 점
- ...

### 우려/반론
- ...

### 제안
- ...

### Codex에게 되묻고 싶은 점
- ...

리뷰 주제:
$Topic

Codex 1차 의견:
$CodexNote

최근 리뷰 로그 참고:
$existingLog
"@

$claudeOutput = claude -p $prompt `
    --model $Model `
    --effort $Effort `
    --permission-mode dontAsk `
    --disallowedTools "Edit,Write,Bash" `
    --output-format text

$entry = @"

---

## $timestamp - $Topic

### Codex Note
$CodexNote

$claudeOutput
"@

Add-Content -Path $LogPath -Value $entry -Encoding UTF8
Write-Host "Claude 리뷰를 $LogPath 에 추가했습니다."
