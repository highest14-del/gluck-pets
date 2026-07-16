
# ================================================================
#  GLUCK PETS 부트스트랩 — 자동 업데이트 + 로딩표시 + 로그 후 실행
# ================================================================
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
  Add-Type -Namespace GPB -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
  # Per-Monitor V2 우선 (모니터 배율 달라도 OS 강제 확대 없음), 실패 시 시스템 DPI 인식
  if (-not [GPB.Dpi]::SetProcessDpiAwarenessContext((New-Object IntPtr(-4)))) { [void][GPB.Dpi]::SetProcessDPIAware() }
} catch { try { [void][GPB.Dpi]::SetProcessDPIAware() } catch {} }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Base = 'https://raw.githubusercontent.com/highest14-del/gluck-pets/AI%EA%B4%80%EC%A0%9C/dist'
$Home_ = Join-Path $env:LocalAppData 'GLUCK_PETS'
$Assets = Join-Path $Home_ 'assets'
New-Item -ItemType Directory -Force -Path $Assets | Out-Null
$Log = Join-Path $Home_ 'log.txt'
function WLog($m) { try { Add-Content -Path $Log -Value ((Get-Date -Format 'HH:mm:ss.f') + " [boot] " + $m) -Encoding UTF8 } catch {} }
Set-Content -Path $Log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ---- GLUCK PETS 시작 ----") -Encoding UTF8

# 로딩 표시 (작은 안내창)
$splash = New-Object System.Windows.Forms.Form
$splash.FormBorderStyle='None'; $splash.ShowInTaskbar=$false; $splash.TopMost=$true
$splash.StartPosition='Manual'; $splash.BackColor=[System.Drawing.Color]::FromArgb(255,255,250,235)
$sl = New-Object System.Windows.Forms.Label
$sl.AutoSize=$true; $sl.Font=New-Object System.Drawing.Font('Malgun Gothic',11)
$sl.ForeColor=[System.Drawing.Color]::FromArgb(255,90,70,50)
$sl.Padding=(New-Object System.Windows.Forms.Padding(16,10,16,10))
$sl.Text='GLUCK 펫 준비 중...'
$splash.Controls.Add($sl); $splash.ClientSize=$sl.PreferredSize
$wa=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$splash.Left=$wa.Right-$splash.Width-24; $splash.Top=$wa.Bottom-$splash.Height-24
$splash.Show(); [System.Windows.Forms.Application]::DoEvents()
function Splash($t) { $sl.Text=$t; $splash.ClientSize=$sl.PreferredSize; [System.Windows.Forms.Application]::DoEvents() }

$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8

$localVerFile = Join-Path $Home_ 'version.json'
$localVer = -1
if (Test-Path $localVerFile) {
  try { $localVer = (Get-Content $localVerFile -Raw | ConvertFrom-Json).version } catch {}
}
WLog "로컬 버전: $localVer"

$remote = $null
try {
  # TrimStart(U+FEFF): BOM 포함 저장 시 5.1 ConvertFrom-Json 즉사 방지
  $remote = $wc.DownloadString("$Base/version.json").TrimStart([char]0xFEFF) | ConvertFrom-Json
  WLog ("원격 버전: " + $remote.version)
}
catch { WLog ("버전 확인 실패(오프라인?): " + $_.Exception.Message) }

if ($null -ne $remote -and [int]$remote.version -gt [int]$localVer) {
  try {
    Splash '새 버전 다운로드 중... (최대 1분)'
    WLog "업데이트 시작 → v$($remote.version)"
    # 엔진: 임시 파일 + EOF 마커 검증 후에만 교체 (반쪽 파일 벽돌 방지)
    $engTmp = Join-Path $Home_ 'gluck_pets.ps1.tmp'
    $wc.DownloadFile("$Base/gluck_pets.ps1", $engTmp)
    $tail = Get-Content $engTmp -Tail 3 -Encoding UTF8
    if (-not ($tail -match 'GLUCK-PETS-EOF')) { throw '엔진 다운로드 불완전 (마커 없음)' }
    Move-Item -Force $engTmp (Join-Path $Home_ 'gluck_pets.ps1')
    # 매니페스트: JSON 파싱 검증 후 교체
    $manTmp = Join-Path $Assets 'manifest.json.tmp'
    $wc.DownloadFile("$Base/manifest.json", $manTmp)
    $null = (Get-Content $manTmp -Raw -Encoding UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
    Move-Item -Force $manTmp (Join-Path $Assets 'manifest.json')
    $man = Get-Content (Join-Path $Assets 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $n = 0
    foreach ($im in $man.images) {
      $rel = $im.file -replace '/', '\'
      $dst = Join-Path $Assets $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      # 필요 판정: 없음 / 강제 / 크기 불일치(내용 교체·손상 감지)
      $need = -not (Test-Path $dst)
      if (-not $need -and $remote.force) { $need = $true }
      if (-not $need -and $im.PSObject.Properties['size'] -and $im.size) {
        if ((Get-Item $dst).Length -ne [long]$im.size) { $need = $true }
      }
      if ($need) {
        $tmp = $dst + '.tmp'
        $wc.DownloadFile(("$Base/" + $im.file), $tmp)      # 임시 파일로 받고
        Move-Item -Force $tmp $dst                          # 성공 시에만 원자적 교체
      }
      $n++
      if (($n % 12) -eq 0) { Splash ("이미지 받는 중... " + $n + "/" + $man.images.Count) }
      [System.Windows.Forms.Application]::DoEvents()
    }
    Set-Content -Path $localVerFile -Value ($remote | ConvertTo-Json) -Encoding UTF8
    WLog "업데이트 완료 ($n개 확인)"
  } catch { WLog ("업데이트 실패: " + $_.Exception.Message) }
}

$engine = Join-Path $Home_ 'gluck_pets.ps1'
if (-not (Test-Path $engine)) {
  WLog "최초 설치: zip 폴더에서 복사"
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
  Copy-Item (Join-Path $here 'gluck_pets.ps1') $engine -Force
  if (Test-Path (Join-Path $here 'assets')) {
    Copy-Item (Join-Path $here 'assets\*') $Assets -Recurse -Force
  } elseif (Test-Path (Join-Path $here 'manifest.json')) {
    # dist 평면 레이아웃(개발/저장소 직접 실행) 대응
    Copy-Item (Join-Path $here 'manifest.json') (Join-Path $Assets 'manifest.json') -Force
    if (Test-Path (Join-Path $here 'img')) { Copy-Item (Join-Path $here 'img') $Assets -Recurse -Force }
  }
}

Splash '나나·모모 부르는 중...'
WLog "엔진 실행"
try {
  & $engine -SplashForm $splash
  WLog "엔진 정상 종료"
} catch {
  WLog ("엔진 오류: " + $_.Exception.Message + " || " + $_.ScriptStackTrace)
  try { $splash.Close() } catch {}
  [System.Windows.Forms.MessageBox]::Show(("GLUCK 펫 실행 오류:`n" + $_.Exception.Message + "`n`n로그: " + $Log), "GLUCK 펫", 'OK', 'Error') | Out-Null
}
try { if (-not $splash.IsDisposed) { $splash.Close() } } catch {}
# GLUCK-PETS-EOF
