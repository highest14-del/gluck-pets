
# ================================================================
#  GLUCK PETS 부트스트랩 — 자동 업데이트 후 실행
#  공개 저장소(dist/version.json)에서 최신 엔진·이미지를 받아온다.
#  인터넷이 없으면 로컬 캐시로 그냥 실행.
# ================================================================
$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Base = 'https://raw.githubusercontent.com/highest14-del/gluck-pets/AI%EA%B4%80%EC%A0%9C/dist'
$Home_ = Join-Path $env:LocalAppData 'GLUCK_PETS'
$Assets = Join-Path $Home_ 'assets'
New-Item -ItemType Directory -Force -Path $Assets | Out-Null

$wc = New-Object System.Net.WebClient
$wc.Encoding = [System.Text.Encoding]::UTF8

$localVerFile = Join-Path $Home_ 'version.json'
$localVer = -1
if (Test-Path $localVerFile) {
  try { $localVer = (Get-Content $localVerFile -Raw | ConvertFrom-Json).version } catch {}
}

$remote = $null
try { $remote = $wc.DownloadString("$Base/version.json") | ConvertFrom-Json } catch {}

if ($null -ne $remote -and [int]$remote.version -gt [int]$localVer) {
  try {
    # 엔진 + 매니페스트
    $wc.DownloadFile("$Base/gluck_pets.ps1", (Join-Path $Home_ 'gluck_pets.ps1'))
    $wc.DownloadFile("$Base/manifest.json", (Join-Path $Assets 'manifest.json'))
    # 이미지 (버전 오를 때만 전체 동기화)
    $man = Get-Content (Join-Path $Assets 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($im in $man.images) {
      $rel = $im.file -replace '/', '\'
      $dst = Join-Path $Assets $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      $url = "$Base/" + $im.file
      if (-not (Test-Path $dst) -or $remote.force) { $wc.DownloadFile($url, $dst) }
    }
    Set-Content -Path $localVerFile -Value ($remote | ConvertTo-Json) -Encoding UTF8
  } catch {}
}

$engine = Join-Path $Home_ 'gluck_pets.ps1'
if (-not (Test-Path $engine)) {
  # 최초 설치: 배포 zip 폴더의 파일을 로컬로 복사
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
  Copy-Item (Join-Path $here 'gluck_pets.ps1') $engine -Force
  if (Test-Path (Join-Path $here 'assets')) {
    Copy-Item (Join-Path $here 'assets\*') $Assets -Recurse -Force
  }
}
& $engine
