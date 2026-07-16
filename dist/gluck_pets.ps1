
# ================================================================
#  GLUCK PETS v2 — 나나 & 모모 실사 데스크톱 펫 (PowerShell/WinForms)
#  설치 불필요. assets/ 의 실사 PNG + manifest.json 로드.
#  ※ gen_ps1_photo.py 가 생성. 직접 수정 금지.
# ================================================================
param($SplashForm = $null)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:LogFile = Join-Path (Join-Path $env:LocalAppData 'GLUCK_PETS') 'log.txt'
function ELog($m) { try { Add-Content -Path $script:LogFile -Value ((Get-Date -Format 'HH:mm:ss.f') + " [pet] " + $m) -Encoding UTF8 } catch {} }
ELog "엔진 시작"

# P/Invoke + ULW 헬퍼 — System.Drawing 참조 필수 (PS5.1 기본 참조에 없음)

Add-Type -ReferencedAssemblies 'System.Drawing','System.Windows.Forms' -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class GPWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int n, int v);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
  public static void HideFromAltTab(IntPtr h) {
    int ex = GetWindowLong(h, -20);
    ex = (ex | 0x80) & ~0x40000;
    SetWindowLong(h, -20, ex);
  }
  public static void MakeLayered(IntPtr h) {
    int ex = GetWindowLong(h, -20);
    SetWindowLong(h, -20, ex | 0x80000 | 0x80);
  }
  public static void UnLayer(IntPtr h) {
    int ex = GetWindowLong(h, -20);
    SetWindowLong(h, -20, (ex & ~0x80000) | 0x80);
  }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int x, y; }
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(PT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, int flags);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int a, int b, int c, int d, int e, int f);
  [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr hdc, int x, int y);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
  public static uint ScreenPixel(int x, int y) {
    IntPtr dc = GetDC(IntPtr.Zero);
    uint c = GetPixel(dc, x, y);
    ReleaseDC(IntPtr.Zero, dc);
    return c;
  }
  public static long TopWindowAt(int x, int y) {
    PT p; p.x = x; p.y = y;
    IntPtr h = WindowFromPoint(p);
    if (h == IntPtr.Zero) return 0;
    return GetAncestor(h, 2).ToInt64();   // GA_ROOT
  }
  public static List<long[]> Platforms(long[] exclude, int workTop) {
    var res = new List<long[]>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      long hv = h.ToInt64();
      for (int i=0;i<exclude.Length;i++) if (exclude[i]==hv) return true;
      if (!IsWindowVisible(h) || IsIconic(h)) return true;
      if (GetWindowTextLength(h)==0) return true;
      var sb = new StringBuilder(96); GetClassName(h, sb, 96);
      string c = sb.ToString();
      if (c=="Progman"||c=="WorkerW"||c=="Shell_TrayWnd"||c=="Shell_SecondaryTrayWnd"||c=="Windows.UI.Core.CoreWindow"||c=="XamlExplorerHostIslandWindow") return true;
      int cloaked=0; DwmGetWindowAttribute(h,14,out cloaked,4); if (cloaked!=0) return true;
      RECT r; int ok = DwmGetWindowAttribute(h,9,out r,16);
      if (ok!=0) { if (!GetWindowRect(h,out r)) return true; }
      int w=r.right-r.left, ht=r.bottom-r.top;
      if (w<260||ht<160) return true;
      if (r.top<=workTop+4) return true;
      res.Add(new long[]{hv, r.left, r.top, r.right});
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
public class GPLayer {
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int x, y; public POINT(int a,int b){x=a;y=b;} }
  [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; public SIZE(int a,int b){cx=a;cy=b;} }
  [StructLayout(LayoutKind.Sequential)] struct BLEND { public byte op, flags, alpha, fmt; }
  [StructLayout(LayoutKind.Sequential)] struct BMIH {
    public uint biSize; public int biWidth; public int biHeight;
    public ushort biPlanes; public ushort biBitCount; public uint biCompression;
    public uint biSizeImage; public int biXPPM; public int biYPPM;
    public uint biClrUsed; public uint biClrImportant;
  }
  [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLEND pblend, int dwFlags);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
  [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hDC);
  [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
  [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hDC, IntPtr h);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
  [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr hdc, ref BMIH bmi, uint usage, out IntPtr bits, IntPtr hSection, uint offset);
  [DllImport("kernel32.dll", EntryPoint="RtlMoveMemory")] static extern void CopyMemory(IntPtr dst, IntPtr src, UIntPtr len);
  // GetHbitmap 는 일부 PC에서 픽셀 알파를 잃어 ULW가 '성공'을 반환해도 화면엔 안 그려짐(개 투명).
  // 32bpp 프리멀티플라이드 DIB 섹션을 직접 만들어 넘기는 정석 경로로 교체.
  public static bool Draw(IntPtr hwnd, System.Drawing.Bitmap bmp, int x, int y) {
    int w = bmp.Width, h = bmp.Height;
    IntPtr screenDc = GetDC(IntPtr.Zero);
    IntPtr memDc = CreateCompatibleDC(screenDc);
    IntPtr hBmp = IntPtr.Zero; IntPtr old = IntPtr.Zero;
    System.Drawing.Imaging.BitmapData bd = null;
    try {
      BMIH bi = new BMIH();
      bi.biSize = (uint)Marshal.SizeOf(typeof(BMIH));
      bi.biWidth = w; bi.biHeight = -h;   // top-down
      bi.biPlanes = 1; bi.biBitCount = 32; bi.biCompression = 0;
      IntPtr bits;
      hBmp = CreateDIBSection(screenDc, ref bi, 0, out bits, IntPtr.Zero, 0);
      if (hBmp == IntPtr.Zero || bits == IntPtr.Zero) return false;
      bd = bmp.LockBits(new System.Drawing.Rectangle(0,0,w,h),
             System.Drawing.Imaging.ImageLockMode.ReadOnly,
             System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
      int rowBytes = w * 4;
      for (int r = 0; r < h; r++) {
        CopyMemory(new IntPtr(bits.ToInt64() + (long)r * rowBytes),
                   new IntPtr(bd.Scan0.ToInt64() + (long)r * bd.Stride),
                   (UIntPtr)(uint)rowBytes);
      }
      bmp.UnlockBits(bd); bd = null;
      old = SelectObject(memDc, hBmp);
      POINT dst = new POINT(x, y);
      SIZE sz = new SIZE(w, h);
      POINT src = new POINT(0, 0);
      BLEND bf = new BLEND(); bf.op = 0; bf.flags = 0; bf.alpha = 255; bf.fmt = 1;  // AC_SRC_ALPHA
      return UpdateLayeredWindow(hwnd, screenDc, ref dst, ref sz, memDc, ref src, 0, ref bf, 2);  // ULW_ALPHA
    } catch { return false; }
    finally {
      if (bd != null) { try { bmp.UnlockBits(bd); } catch {} }
      if (old != IntPtr.Zero) SelectObject(memDc, old);
      if (hBmp != IntPtr.Zero) DeleteObject(hBmp);
      if (memDc != IntPtr.Zero) DeleteDC(memDc);
      ReleaseDC(IntPtr.Zero, screenDc);
    }
  }
  // 크로마키 폴백용: 반투명 가장자리를 1비트 마스크로 다져서 마젠타 후광 제거
  public static System.Drawing.Bitmap Matte(System.Drawing.Bitmap src, byte thr, byte cr, byte cg, byte cb) {
    int w = src.Width, h = src.Height;
    var rect = new System.Drawing.Rectangle(0, 0, w, h);
    var sd = src.LockBits(rect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
    int sStride = sd.Stride;
    byte[] sbuf = new byte[sStride * h];
    Marshal.Copy(sd.Scan0, sbuf, 0, sbuf.Length);
    src.UnlockBits(sd);
    var dst = new System.Drawing.Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
    var dd = dst.LockBits(rect, System.Drawing.Imaging.ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
    int dStride = dd.Stride;
    byte[] dbuf = new byte[dStride * h];
    for (int y = 0; y < h; y++) {
      int so = y * sStride, doo = y * dStride;
      for (int xx = 0; xx < w; xx++) {
        byte a = sbuf[so + xx * 4 + 3];
        int di = doo + xx * 3;
        if (a < thr) { dbuf[di] = cb; dbuf[di + 1] = cg; dbuf[di + 2] = cr; }   // BGR = 크로마
        else { dbuf[di] = sbuf[so + xx * 4]; dbuf[di + 1] = sbuf[so + xx * 4 + 1]; dbuf[di + 2] = sbuf[so + xx * 4 + 2]; }
      }
    }
    Marshal.Copy(dbuf, 0, dd.Scan0, dbuf.Length);
    dst.UnlockBits(dd);
    return dst;
  }
}
public class GPQuietForm : System.Windows.Forms.Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override System.Windows.Forms.CreateParams CreateParams {
    get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000; return cp; }  // WS_EX_NOACTIVATE — 포커스 강탈 방지
  }
}
"@

try {
  # Per-Monitor V2: 모니터 배율이 달라도 OS가 창을 강제 확대하지 않게 (모니터별 크기 널뜀 방지)
  if (-not [GPWin]::SetProcessDpiAwarenessContext((New-Object IntPtr(-4)))) { [void][GPWin]::SetProcessDPIAware() }
} catch { try { [void][GPWin]::SetProcessDPIAware() } catch {} }
ELog "Add-Type OK"

# ---------------------------------------------------------------- 설정
$HomeDir = Join-Path $env:LocalAppData 'GLUCK_PETS'
$PET_H = 250            # 기본값 — settings.json(우클릭 메뉴 '크기')로 변경 가능
try {
  $sf = Join-Path $HomeDir 'settings.json'
  if (Test-Path $sf) {
    $cfg = (Get-Content $sf -Raw -Encoding UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ($cfg.pet_h) { $PET_H = [Math]::Max(150, [Math]::Min(420, [int]$cfg.pet_h)) }
  }
} catch {}
$TICK_MS = 30
$PETS = @( @{name='나나';kind='nana'}, @{name='모모';kind='momo'} )
$CHROMA = [System.Drawing.Color]::FromArgb(255,255,0,255)

$AssetDir = Join-Path $PSScriptRoot 'assets'
$Manifest = Get-Content (Join-Path $AssetDir 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$CANVAS = [int]$Manifest.canvas
$SC = $PET_H / $CANVAS
$SPR = [int]($CANVAS * $SC)     # 정사각 캔버스 → 창 크기

$WALK_SPEED = $SPR * 0.032
$RUN_SPEED = $SPR * 0.076
$GRAVITY = $SPR * 0.017
$MAX_FALL = $SPR * 0.28

$rng = New-Object System.Random
$Frames = @{}      # "kind|frame|facing" -> Bitmap
$FootPad = @{}     # "kind|frame" -> px (창 하단에서 발바닥까지)
$HasFrame = @{}
$script:UseULW = $true
$App = @{ pets=(New-Object System.Collections.ArrayList); hearts=(New-Object System.Collections.ArrayList); speeches=(New-Object System.Collections.ArrayList); plat=@{}; tick=0 }

function Sign1($c) { if ($c) { return 1 } else { return -1 } }

# 마우스 핸들러 — New-Pet 폼과 크로마 폴백 PictureBox 양쪽에서 재사용
# 더블클릭은 두 번째 MouseDown(Clicks>=2)에서 분기 — down→grab이 선점하는 순서 문제 회피
# 주의: 핸들러 안에서는 $s.Tag만 쓸 것 ($p 등 바깥 변수는 동적 스코프로 엉뚱한 펫에 바인딩될 수 있음)
$script:HDown = { param($s,$e)
  if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  $pet = $s.Tag
  if ($e.Clicks -ge 2) {
    if (@('drag','fall') -contains $pet.state) { $pet.state='idle'; $pet.vx=0; $pet.vy=0 }
    Pet-Head $pet
  } else {
    On-Grab $pet
  }
}
$script:HUp = { param($s,$e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { On-Release $s.Tag } }

# ---------------------------------------------------------------- 에셋 로드
function Build-Frames {
  $cnt = 0
  foreach ($im in $Manifest.images) {
    $cnt++
    if (($cnt % 10) -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
    $path = Join-Path $AssetDir ($im.file -replace '/', '\')
    if (-not (Test-Path $path)) { ELog ("누락: " + $im.file); continue }
    try {
      $srcImg = [System.Drawing.Image]::FromFile($path)
    } catch {
      # 손상 파일(부분 다운로드 등): 삭제해서 다음 실행 때 재다운로드 유도
      ELog ("손상 이미지 스킵+삭제: " + $im.file)
      try { Remove-Item $path -Force } catch {}
      continue
    }
    $bmp = New-Object System.Drawing.Bitmap($SPR, $SPR, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($srcImg, 0, 0, $SPR, $SPR)
    $g.Dispose(); $srcImg.Dispose()
    $flip = $bmp.Clone()
    $flip.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
    $key = "$($im.dog)|$($im.view)_$($im.pose)"
    $fc = 'R'
    if ($im.PSObject.Properties['facing'] -and $im.facing) { $fc = $im.facing }
    if ($fc -eq 'L') { $Frames["$key|1"] = $flip; $Frames["$key|-1"] = $bmp }
    else { $Frames["$key|1"] = $bmp; $Frames["$key|-1"] = $flip }
    $HasFrame[$key] = $true
    $pad = 4
    if ($im.bbox) { $pad = [int](($CANVAS - 1 - [int]$im.bbox[3]) * $SC) }
    $FootPad[$key] = $pad
  }
}

function F($kind, $frame) { return $HasFrame.ContainsKey("$kind|$frame") }

$script:Cyc = @{}   # "kind|view_pose" -> 정렬된 변형 번호 목록
function AF($p, $base, $per) {
  # 포즈 변형(base1..base9)이 있으면 주기 $per 틱으로 순환, 없으면 base 그대로
  $ck = "$($p.kind)|$base"
  if ($script:Cyc.ContainsKey($ck)) {
    $lst = $script:Cyc[$ck]
    return ($base + $lst[([int][Math]::Floor($p.anim / $per)) % $lst.Count])
  }
  return $base
}

$script:WalkCyc = @{}
$script:RunCyc = @{}
function Build-Cycles {
  foreach ($k in @($HasFrame.Keys)) {
    if ($k -match '^([a-z]+)\|(.+?)([1-9])$') {
      $ck = $Matches[1] + '|' + $Matches[2]
      if (-not $script:Cyc.ContainsKey($ck)) { $script:Cyc[$ck] = @() }
      $script:Cyc[$ck] = @($script:Cyc[$ck] + [int]$Matches[3] | Sort-Object)
    }
  }
  foreach ($kind in @('nana','momo')) {
    $wc = @()
    foreach ($n in @('side_walk1','side_walk2','side_walk3','side_walk4')) { if (F $kind $n) { $wc += $n } }
    if ($wc.Count -ge 2) { $script:WalkCyc[$kind] = $wc }   # 진짜 보행 사이클 (발 교차)
    else { $script:WalkCyc[$kind] = @('side_walk') }         # 폴백: 단일 컷 + 바운스 (사진 교대 반짝임 방지)
    $rc = @()
    foreach ($n in @('side_run1','side_run2','side_run3')) { if (F $kind $n) { $rc += $n } }
    if ($rc.Count -ge 2) { $script:RunCyc[$kind] = $rc }
    else { $script:RunCyc[$kind] = @('side_run') }
  }
}
function Pick($kind, $frames) {
  $ok = @($frames | Where-Object { F $kind $_ })
  if ($ok.Count -eq 0) { return 'side_stand' }
  return $ok[$rng.Next($ok.Count)]
}

# ---------------------------------------------------------------- 플랫폼(창)
function Refresh-Platforms {
  # 멀티 모니터: 모든 화면의 작업영역을 세계로 사용
  $scrs = New-Object System.Collections.ArrayList
  $wl = [int]::MaxValue; $wt = [int]::MaxValue; $wr = [int]::MinValue; $wb = [int]::MinValue
  foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
    $wa2 = $s.WorkingArea
    [void]$scrs.Add(@{ left=$wa2.Left; top=$wa2.Top; right=$wa2.Right; bottom=$wa2.Bottom })
    if ($wa2.Left -lt $wl) { $wl = $wa2.Left }
    if ($wa2.Top -lt $wt) { $wt = $wa2.Top }
    if ($wa2.Right -gt $wr) { $wr = $wa2.Right }
    if ($wa2.Bottom -gt $wb) { $wb = $wa2.Bottom }
  }
  $App.plat.screens = $scrs
  $App.plat.workLeft = $wl; $App.plat.workTop = $wt
  $App.plat.workRight = $wr; $App.plat.workBottom = $wb
  $ex = New-Object System.Collections.ArrayList
  foreach ($p in $App.pets) { [void]$ex.Add([long]$p.form.Handle.ToInt64()) }
  foreach ($h in $App.hearts) { [void]$ex.Add([long]$h.form.Handle.ToInt64()) }
  foreach ($s in $App.speeches) { [void]$ex.Add([long]$s.form.Handle.ToInt64()) }
  if ($ex.Count -eq 0) { [void]$ex.Add([long]0) }
  $raw = [GPWin]::Platforms([long[]]$ex.ToArray([long]), [int]$App.plat.workTop)
  $wins = New-Object System.Collections.ArrayList
  foreach ($w in $raw) { [void]$wins.Add(@{ id=$w[0]; left=[int]$w[1]; top=[int]$w[2]; right=[int]$w[3] }) }
  $App.plat.windows = $wins
  $own = @{}
  foreach ($h in $ex) { $own[[long]$h] = $true }
  $App.plat.own = $own
}

function Foot($p) { $k = "$($p.kind)|$($p.frame)"; if ($FootPad.ContainsKey($k)) { return $FootPad[$k] } return 4 }
function Screen-Of($x) {
  $best = $null; $bd = [double]::MaxValue
  foreach ($s in $App.plat.screens) {
    if ($x -ge $s.left -and $x -lt $s.right) { return $s }
    $d = [Math]::Min([Math]::Abs($x - $s.left), [Math]::Abs($x - $s.right))
    if ($d -lt $bd) { $bd = $d; $best = $s }
  }
  return $best
}
function Ground-Y($p) { $s = Screen-Of (Cx $p); return $s.bottom - $SPR + (Foot $p) }
function Stand-Y($p, $plat) { return $plat.top - $SPR + (Foot $p) }
function Find-Plat($id) { foreach ($w in $App.plat.windows) { if ($w.id -eq $id) { return $w } } return $null }
function Feet($p) { return $p.y + $SPR - (Foot $p) }
function Cx($p) { return $p.x + $SPR / 2 }
function Other-Pet($p) { foreach ($q in $App.pets) { if ($q.id -ne $p.id) { return $q } } return $null }

function Plat-Visible($plat, $cx) {
  # 창 상단이 다른 창에 가려졌는지 — 펫 좌우 바깥 두 지점에서 최상위 창을 조회
  $y = [int]($plat.top + 8)
  foreach ($px in @(($cx - $SPR * 0.75), ($cx + $SPR * 0.75))) {
    if ($px -lt ($plat.left + 6) -or $px -gt ($plat.right - 6)) { continue }
    $h = [GPWin]::TopWindowAt([int]$px, $y)
    if ($h -eq $plat.id) { return $true }
    if ($App.plat.own.ContainsKey([long]$h)) { return $true }   # 우리 펫/말풍선이 덮은 지점
  }
  # 두 지점 모두 span 밖(좁은 창 가장자리)이면 중앙 한 점으로 판정
  $cxc = [Math]::Max($plat.left + 6, [Math]::Min($plat.right - 6, $cx))
  $h2 = [GPWin]::TopWindowAt([int]$cxc, $y)
  return ($h2 -eq $plat.id -or $App.plat.own.ContainsKey([long]$h2))
}

function Landing($cx, $prevFeet, $newFeet) {
  $best = $null
  foreach ($w in $App.plat.windows) {
    if (($w.left+8) -le $cx -and $cx -le ($w.right-8) -and $prevFeet -le $w.top -and $w.top -le $newFeet) {
      if (($null -eq $best -or $w.top -lt $best.top) -and (Plat-Visible $w $cx)) { $best = $w }
    }
  }
  if ($null -ne $best) { return $best }
  $gb = (Screen-Of $cx).bottom
  if ($newFeet -ge $gb) { return 'ground' }
  return $null
}

# ---------------------------------------------------------------- 렌더
$script:FadeCM = New-Object System.Drawing.Imaging.ColorMatrix
$script:FadeIA = New-Object System.Drawing.Imaging.ImageAttributes
$FADE_TICKS = 5   # 프레임 전환 크로스페이드 길이 (5틱 = 150ms)

# 크로마 폴백에서 쓸 '후광 제거' 프레임 캐시 — 원본 비트맵 참조를 키로 지연 생성
$script:ChromaCache = @{}
function Get-ChromaFrame($bmp) {
  if ($null -eq $bmp) { return $null }
  if ($script:ChromaCache.ContainsKey($bmp)) { return $script:ChromaCache[$bmp] }
  # Matte 실패 시 원본(소프트 알파)을 캐시하면 마젠타 후광이 영구화됨 → null 반환(직전 프레임 유지)
  $m = $null
  try { $m = [GPLayer]::Matte($bmp, [byte]110, [byte]255, [byte]0, [byte]255) } catch { return $null }
  $script:ChromaCache[$bmp] = $m
  return $m
}

function Render-Pet($p) {
  $key = "$($p.kind)|$($p.frame)|$($p.facing)"
  $bmp = $Frames[$key]
  if ($null -eq $bmp) { $bmp = $Frames["$($p.kind)|side_stand|$($p.facing)"] }
  if ($null -eq $bmp) { return }
  # 프레임 전환 감지 → 페이드 시작
  # 단, 같은 동작의 사이클 프레임(walk1→walk2 등)과 시퀀스 재생 중엔 페이드 금지 —
  # 진짜 애니메이션에 반투명 겹침이 매 프레임 걸리면 잔상이 반짝거림 (v17 실기 보고)
  if ($p.lastKey -ne $key) {
    $ob = $p.lastKey -replace '[1-9]\|', '|'
    $nb = $key -replace '[1-9]\|', '|'
    $noFadeState = @('seqplay','landing','jump','jumpprep','fall') -contains $p.state
    if ($null -ne $p.lastBmp -and $p.lastBmp -ne $bmp -and $ob -ne $nb -and -not $noFadeState) {
      $p.fadeFrom = $p.lastBmp; $p.fade = $FADE_TICKS
    } else {
      $p.fade = 0; $p.fadeFrom = $null    # 사이클 진행 중엔 진행 중이던 페이드도 끊음 (잔상 제거)
    }
    $p.lastKey = $key; $p.lastBmp = $bmp
  }
  if ($script:UseULW) {
    $draw = $bmp
    if ($p.fade -gt 0 -and $null -ne $p.fadeFrom) {
      # 이전/새 프레임 알파 블렌드 (스크래치 비트맵 재사용)
      if ($null -eq $p.scratch) {
        $p.scratch = New-Object System.Drawing.Bitmap($SPR, $SPR, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        $p.scratchG = [System.Drawing.Graphics]::FromImage($p.scratch)
      }
      $t = 1.0 - ($p.fade / [double]$FADE_TICKS)
      $g = $p.scratchG
      $g.Clear([System.Drawing.Color]::FromArgb(0,0,0,0))
      $rect = New-Object System.Drawing.Rectangle(0, 0, $SPR, $SPR)
      $script:FadeCM.Matrix33 = [float](1.0 - $t)
      $script:FadeIA.SetColorMatrix($script:FadeCM)
      $g.DrawImage($p.fadeFrom, $rect, 0, 0, $SPR, $SPR, [System.Drawing.GraphicsUnit]::Pixel, $script:FadeIA)
      $script:FadeCM.Matrix33 = [float]$t
      $script:FadeIA.SetColorMatrix($script:FadeCM)
      $g.DrawImage($bmp, $rect, 0, 0, $SPR, $SPR, [System.Drawing.GraphicsUnit]::Pixel, $script:FadeIA)
      $p.fade--
      if ($p.fade -le 0) { $p.fadeFrom = $null }
      $draw = $p.scratch
    }
    $ok = $false
    try { $ok = [GPLayer]::Draw($p.form.Handle, $draw, [int]$p.x, [int]$p.y) } catch {}
    if ($ok) { return }
    $script:UseULW = $false
    ELog "ULW 실패(FALSE/예외) → 크로마 폴백 전환"
  }
  if ($null -eq $p.pb) {
    # ULW 실패 시 크로마키 폴백을 즉석 구성 (레이어드 제거 + 핸들러/메뉴 재부착 필수)
    try { [GPWin]::UnLayer($p.form.Handle) } catch {}
    $p.form.BackColor = $CHROMA; $p.form.TransparencyKey = $CHROMA
    $pb2 = New-Object System.Windows.Forms.PictureBox
    $pb2.Width=$SPR; $pb2.Height=$SPR; $pb2.BackColor=$CHROMA; $pb2.SizeMode='Zoom'
    $pb2.Tag = $p
    $pb2.add_MouseDown($script:HDown); $pb2.add_MouseUp($script:HUp)
    $pb2.ContextMenuStrip = $p.form.ContextMenuStrip
    $p.form.Controls.Add($pb2)
    $p.pb = $pb2
  }
  $cf = Get-ChromaFrame $bmp
  if ($null -ne $cf -and $p.pb.Image -ne $cf) { $p.pb.Image = $cf }
  $p.form.Left = [int]$p.x; $p.form.Top = [int]$p.y
}

# ---------------------------------------------------------------- 소셜/상호작용
function Detach-Social($p) {
  if ($null -ne $p.partner) {
    $q = $p.partner; $p.partner = $null
    if ($null -ne $q.partner -and $q.partner.id -eq $p.id) {
      $q.partner = $null
      if ($q.state -eq 'ride') { $q.state='fall'; $q.vx=0; $q.vy=-6 }   # 라이더는 낙하로 (바닥 순간이동 방지)
      elseif (@('chase','flee','carry') -contains $q.state) { $q.state = 'idle'; $q.timer = 40 }
    }
  }
  if ($p.state -eq 'ride') { $p.vy = -6 }
}
function Interruptible($p) { return (@('idle','walk','trot','sit','sniff','lookaround') -contains $p.state) }
function On-GroundLevel($p) { return ($null -eq $p.platform -and [Math]::Abs($p.y - (Ground-Y $p)) -lt ($SPR*0.1)) }
function Start-Chase($p,$o) { $p.partner=$o; $o.partner=$p; $p.state='chase'; $o.state='flee'; $t=$rng.Next(120,220); $p.timer=$t; $o.timer=$t }
function Start-Ride($r,$c) { $r.partner=$c; $c.partner=$r; $r.state='ride'; $c.state='carry'; $t=$rng.Next(150,300); $r.timer=$t; $c.timer=$t }

$SAY = @{
  'front_happy'   = @('히히','오늘도 좋은 하루!','좋아좋아')
  'front_curious' = @('뭐 해?','그거 뭐야?','응?')
  'front_beg'     = @('간식... 주라?','한 번만~','플리즈...')
  'front_sleepy'  = @('졸려...','흐아암','스르르...')
  'front_wink'    = @('윙크!','찡긋')
  'front_tongue'  = @('메롱!','냐하')
  'front_laugh'   = @('오늘도 화이팅!','기분 최고!')
  'front_sad'     = @('심심해...','놀아줘...')
  'front_focus'   = @('열일하네~','집중집중')
  'side_excited'  = @('놀자놀자!','월! 월!','신난다~')
}

function Position-Speech($sp) {
  $p = $sp.pet
  $sp.form.Left = [int]((Cx $p) - $sp.form.Width / 2)
  $sp.form.Top = [int]($p.y + (($CANVAS - 1) * $SC * 0.08) - $sp.form.Height - 2)
}

function Style-Bubble($form) {
  # 라운드 코너 — 크기 바뀔 때마다 다시 적용
  try {
    $r = [GPWin]::CreateRoundRectRgn(0, 0, $form.Width + 1, $form.Height + 1, 18, 18)
    $form.Region = [System.Drawing.Region]::FromHrgn($r)
  } catch {}
}

function Say($p, $text, $life=95) {
 try {
  foreach ($s in $App.speeches) { if ($s.pet.id -eq $p.id) { return } }
  # 개별 파스텔: 나나=크림, 모모=연핑크
  if ($p.kind -eq 'momo') {
    $bg = [System.Drawing.Color]::FromArgb(255,255,233,239)
    $fg = [System.Drawing.Color]::FromArgb(255,150,84,100)
  } else {
    $bg = [System.Drawing.Color]::FromArgb(255,255,243,214)
    $fg = [System.Drawing.Color]::FromArgb(255,122,88,50)
  }
  $bf = New-Object GPQuietForm
  $bf.FormBorderStyle='None'; $bf.ShowInTaskbar=$false; $bf.TopMost=$true; $bf.StartPosition='Manual'
  $bf.BackColor = $bg
  $lbl = New-Object System.Windows.Forms.Label
  $lbl.AutoSize=$true; $lbl.Text=$text
  $lbl.Font=New-Object System.Drawing.Font('Malgun Gothic', 10, [System.Drawing.FontStyle]::Bold)
  $lbl.BackColor=$bg
  $lbl.ForeColor=$fg
  $lbl.BorderStyle='None'
  $lbl.Padding=(New-Object System.Windows.Forms.Padding(12,7,12,8))
  $bf.Controls.Add($lbl)
  $sz = $lbl.PreferredSize
  $bf.ClientSize = New-Object System.Drawing.Size($sz.Width, $sz.Height)
  Style-Bubble $bf
  $sp = @{ form=$bf; pet=$p; life=$life }
  [void]$App.speeches.Add($sp)
  Position-Speech $sp
  $bf.Show()
  try { [GPWin]::HideFromAltTab($bf.Handle) } catch {}
 } catch { ELog ("말풍선 오류(무시): " + $_.Exception.Message) }
}

function Say-Emotion($p, $frame) {
  if ($SAY.ContainsKey($frame)) {
    $arr = $SAY[$frame]
    Say $p ($arr[$rng.Next($arr.Count)])
  }
}

function Spawn-Hearts($x, $y, $n) {
 try {
  if ($App.hearts.Count -gt 8) { return }
  for ($i=0; $i -lt $n; $i++) {
    $hf = New-Object GPQuietForm
    $hf.FormBorderStyle='None'; $hf.ShowInTaskbar=$false; $hf.TopMost=$true; $hf.StartPosition='Manual'
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize=$true; $lbl.Text=[string][char]0x2764
    $lbl.Font=New-Object System.Drawing.Font('Segoe UI Emoji', 14)
    $lbl.ForeColor=[System.Drawing.Color]::FromArgb(255,239,109,138)
    $lbl.BackColor=$CHROMA
    $hf.BackColor=$CHROMA; $hf.TransparencyKey=$CHROMA
    $hf.Controls.Add($lbl)
    $hf.ClientSize = $lbl.PreferredSize
    $heart = @{ form=$hf; x=[double]($x + $rng.Next(-20,20)); y=[double]$y; life=24 }
    [void]$App.hearts.Add($heart)
    $hf.Left=[int]$heart.x; $hf.Top=[int]$heart.y; $hf.Show()
    try { [GPWin]::HideFromAltTab($hf.Handle) } catch {}
  }
 } catch { ELog ("하트 오류(무시): " + $_.Exception.Message) }
}

function Restart-Pets {
  try { $script:Timer.Stop() } catch {}
  foreach ($q in $App.pets) { try { $q.form.Close() } catch {} }
  try { $script:Mutex.ReleaseMutex() } catch {}
  try { $script:Mutex.Dispose() } catch {}
  $vbs = Join-Path $HomeDir '글룩펫_실행.vbs'
  if (Test-Path $vbs) { Start-Process wscript.exe ('"' + $vbs + '"') }
  [System.Windows.Forms.Application]::Exit()
}
function Set-PetSize($h) {
  try {
    @{ pet_h = $h } | ConvertTo-Json | Set-Content -Path (Join-Path $HomeDir 'settings.json') -Encoding UTF8
  } catch {}
  Restart-Pets
}

function Force-State($p,$state,$ticks) {
  if (@('drag','jump','fall','ride') -contains $p.state) { return }   # 공중 상태에서 강제 전이 시 순간이동 방지
  Detach-Social $p; $p.state=$state; $p.timer=$ticks; $p.vx=0; $p.seq=0
}
function Pet-Head($p) {
  if (@('drag','fall','jump','ride') -contains $p.state) { return }
  try {
    Detach-Social $p; $p.state='facecam'; $p.timer=60; $p.vx=0
    $p.camframe = Pick $p.kind @('front_happy','front_laugh','front_wink')
    Say-Emotion $p $p.camframe
    Spawn-Hearts ((Cx $p) - 20) ($p.y + $SPR*0.1) 3
  } catch {
    ELog ("쓰다듬기 연출 오류(계속 실행): " + $_.Exception.Message)
    $p.state = 'idle'; $p.timer = 40
  }
}

# ---------------------------------------------------------------- 드래그 (4단계 시선)
function On-Grab($p) {
  Detach-Social $p; $p.state='drag'; $p.platform=$null; $p.jump=$null
  # 커서가 목덜미(상단 중앙)를 잡은 것처럼 — 클릭 지점과 무관
  $p.dragOff = @(($SPR * 0.5), ($SPR * 0.10))
  $p.trail.Clear()
  $p.dragStage = 3; $p.dragHold = 0; $p.dragWant = 3
}
function On-Release($p) {
  if ($p.state -ne 'drag') { return }
  # trail = 최근 틱별 위치 스냅샷 → 틱당 속도로 환산 (이벤트 빈도 무관)
  if ($p.trail.Count -ge 2) {
    $first = $p.trail[0]; $last = $p.trail[$p.trail.Count - 1]
    $n = $p.trail.Count - 1
    $p.vx = [Math]::Max(-22, [Math]::Min(22, ($last[0] - $first[0]) / $n))
    $p.vy = [Math]::Max(-18, [Math]::Min(14, ($last[1] - $first[1]) / $n))
  } else { $p.vx = 0; $p.vy = 0 }
  $p.state = 'fall'
}

function Drag-Frame($p) {
  # 대롱대롱 4단계 — 펫이 커서를 스프링 추종하므로 dx(커서-펫 편차)가 살아 움직인다
  $cur = [System.Windows.Forms.Cursor]::Position
  $tx = $cur.X - $p.dragOff[0]; $ty = $cur.Y - $p.dragOff[1]
  $p.x += ($tx - $p.x) * 0.28
  $p.y += ($ty - $p.y) * 0.34
  [void]$p.trail.Add(@($p.x, $p.y))          # 틱별 위치 (던지기 속도용)
  while ($p.trail.Count -gt 6) { $p.trail.RemoveAt(0) }
  $dx = $tx - $p.x
  $ratio = [Math]::Abs($dx) / ($SPR * 0.6)
  # 단계 판정 (0.75/0.45/0.15) + 같은 후보 3틱(90ms) 연속 시 확정
  $want = 3
  if ($ratio -ge 0.75) { $want = 0 }
  elseif ($ratio -ge 0.45) { $want = 1 }
  elseif ($ratio -ge 0.15) { $want = 2 }
  if ($want -eq $p.dragStage) { $p.dragHold = 0 }
  elseif ($want -eq $p.dragWant) {
    $p.dragHold++
    if ($p.dragHold -ge 3) { $p.dragStage = $want; $p.dragHold = 0 }
  } else { $p.dragWant = $want; $p.dragHold = 1 }
  if ([Math]::Abs($dx) -gt 3) { $p.facing = Sign1 ($dx -gt 0) }
  $stages = @('side_hang90','side_hang60','side_hang30','front_hang0')
  $f = $stages[$p.dragStage]
  if (F $p.kind $f) { return (AF $p $f 7) }
  if ($p.dragStage -ge 2 -and (F $p.kind 'front_scared')) { return 'front_scared' }
  if (F $p.kind 'side_startle') { return 'side_startle' }
  return 'side_stand'
}

# ---------------------------------------------------------------- 행동 결정
function Decide($p) {
  $o = Other-Pet $p
  $r = $rng.NextDouble()
  if ($null -ne $o -and (Interruptible $o) -and (Interruptible $p)) {
    $bothGround = ($null -eq $p.platform -and $null -eq $o.platform)
    if ($bothGround -and $r -lt 0.07) { Start-Chase $p $o; return }
    if ((On-GroundLevel $p) -and (On-GroundLevel $o) -and [Math]::Abs((Cx $p)-(Cx $o)) -lt ($SPR*1.3) -and $r -lt 0.14) { Start-Ride $p $o; return }
  }
  if ($r -lt 0.13 -and (Plan-Jump $p)) { return }
  if ($null -ne $p.platform -and $r -lt 0.2) { Hop-Off $p; return }
  $r = $rng.NextDouble()
  if ($r -lt 0.11) { $p.state='walk'; $p.facing=Sign1($rng.Next(2) -eq 0); $p.timer=$rng.Next(70,220) }
  elseif ($r -lt 0.16) { $p.state='trot'; $p.facing=Sign1($rng.Next(2) -eq 0); $p.timer=$rng.Next(60,150) }
  elseif ($r -lt 0.24) { $p.state='run'; $p.facing=Sign1($rng.Next(2) -eq 0); $p.timer=$rng.Next(40,110) }
  elseif ($r -lt 0.31) { $p.state='zoomies'; $p.facing=Sign1($rng.Next(2) -eq 0); $p.timer=$rng.Next(80,160); $p.skid=0 }
  elseif ($r -lt 0.38) { $p.state='sniff'; $p.facing=Sign1($rng.Next(2) -eq 0); $p.timer=$rng.Next(80,170) }
  elseif ($r -lt 0.44) { $p.state='sneak'; $p.facing=Sign1($rng.Next(2) -eq 0); $p.timer=$rng.Next(70,140) }
  elseif ($r -lt 0.50) { $p.state='groom'; $p.timer=$rng.Next(150,260); $p.seq=0 }
  elseif ($r -lt 0.55) { $p.state='rollplay'; $p.timer=$rng.Next(120,200); $p.seq=0 }
  elseif ($r -lt 0.60) { $p.state='stretchy'; $p.timer=$rng.Next(100,160); $p.seq=0 }
  elseif ($r -lt 0.65) { $p.state='lookaround'; $p.timer=$rng.Next(60,120) }
  elseif ($r -lt 0.70) { $p.state='facecam'; $p.timer=$rng.Next(70,130)
    $p.camframe = Pick $p.kind @('front_happy','front_curious','front_focus','front_wink','front_tongue','front_beg','front_laugh','front_stare','front_sleepy','front_sad')
    if ($p.camframe -ne 'front_stare' -and $rng.NextDouble() -lt 0.55) { Say-Emotion $p $p.camframe } }
  elseif ($r -lt 0.77) { $p.state='idle'; $p.timer=$rng.Next(50,150) }
  elseif ($r -lt 0.80) { $p.state='excited'; $p.timer=$rng.Next(60,110)
    if ($rng.NextDouble() -lt 0.5) { Say-Emotion $p 'side_excited' } }
  elseif ($r -lt 0.90) { Start-Seq $p @('side_sitdown1','side_sitdown2') 6 'sit' ($rng.Next(120,280)) }
  else { Start-Seq $p @('side_prone1','side_prone2','side_prone3','side_liedown1','side_liedown2','side_liedown3') 7 'sleep' ($rng.Next(350,750)) }
}

function Plan-Jump($p) {
  $myFeet = Feet $p
  $options = New-Object System.Collections.ArrayList
  foreach ($w in $App.plat.windows) {
    if ($null -ne $p.platform -and $w.id -eq $p.platform.id) { continue }
    $rise = $myFeet - $w.top
    if ($rise -lt 40 -or $rise -gt 860) { continue }
    if (($w.right - $w.left) -lt ($SPR*1.6)) { continue }
    $lx = [Math]::Max($w.left + $SPR*0.6, [Math]::Min($w.right - $SPR*1.6, $p.x))
    if ([Math]::Abs($lx - $p.x) -gt 760) { continue }
    if (-not (Plat-Visible $w ($lx + $SPR*0.5))) { continue }   # 가려진 창 제외
    [void]$options.Add(@($w, $lx))
  }
  if ($options.Count -eq 0) { return $false }
  $pick = $options[$rng.Next($options.Count)]
  $w = $pick[0]; $lx = $pick[1]
  $ty = $w.top - $SPR + 6
  $t = [Math]::Max(16, [Math]::Min(34, [int]([Math]::Abs($ty - $p.y)/14 + [Math]::Abs($lx - $p.x)/24)))
  $p.jump = @{ plat=$w; t=$t; tick=0; lx=$lx; ty=$ty; vx=(($lx - $p.x)/$t); vy=((($ty - $p.y) - 0.5*$GRAVITY*$t*$t)/$t) }
  $p.facing = Sign1 ($lx -ge $p.x)
  if (F $p.kind 'side_jump1') {
    # 도약 준비 웅크림 — 발사 시점에 속도 재계산 (플랫폼은 발사 때까지 유지)
    $p.state = 'jumpprep'; $p.timer = 5
  } else {
    $p.state = 'jump'; $p.platform = $null
  }
  return $true
}

function Hop-Off($p) {
  $p.state='fall'; $p.platform=$null
  $p.vx = (Sign1 ($rng.Next(2) -eq 0)) * $WALK_SPEED * 1.6
  $p.vy = -4
  $p.facing = Sign1 ($p.vx -gt 0)
}

function Land-On($p, $plat) {
  if ($plat -is [string]) { $plat = $null }
  $p.platform = $plat
  $p.vx = 0; $p.vy = 0
  $p.state = 'landing'; $p.timer = 9; $p.seq = 0
  $p.frame = 'side_land'
  if ($null -ne $plat) { $p.platLeft = $plat.left; $p.y = Stand-Y $p $plat } else { $p.y = Ground-Y $p }
}

# 일회성 전이 시퀀스 재생 (프레임 없으면 목적 상태로 직행 — 안전 폴백)
function Start-Seq($p, $frames, $per, $next, $nextTimer) {
  $avail = @($frames | Where-Object { F $p.kind $_ })
  if ($avail.Count -eq 0) {
    $p.state = $next; $p.timer = $nextTimer
    if ($next -eq 'sleep') { $p.zseq = 0 }
    return
  }
  $p.seqFrames = $avail; $p.seqPer = $per
  $p.seqNextState = $next; $p.seqNextTimer = $nextTimer
  $p.state = 'seqplay'; $p.seq = 0; $p.timer = 9999
}

# ---------------------------------------------------------------- 틱
function Update-Pet($p) {
  $p.anim++
  $st = $p.state

  if ($st -eq 'drag') {
    # MouseUp 유실(캡처 강탈) 시 자가 복구
    if (([System.Windows.Forms.Control]::MouseButtons -band [System.Windows.Forms.MouseButtons]::Left) -eq 0) {
      On-Release $p; return
    }
    $p.frame = Drag-Frame $p; return
  }

  if ($st -eq 'ride') {
    $c = $p.partner
    if ($null -eq $c) { $p.state='fall'; $p.vx=0; $p.vy=0; return }
    $p.facing = $c.facing
    $p.x = $c.x - $c.facing * ($SPR * 0.18)
    $p.y = $c.y - $SPR * 0.42
    $p.frame = 'side_sit'
    $p.timer--
    if ($p.timer -le 0) { Detach-Social $p; $p.state='fall'; $p.vx=(Sign1($rng.Next(2) -eq 0))*$WALK_SPEED }
    return
  }

  if ($st -eq 'jump') {
    $j = $p.jump; $j.tick++
    $vyNow = $j.vy + $GRAVITY * ($j.tick - 1)
    $p.x += $j.vx
    $p.y += $vyNow
    # 포물선 단계별 프레임: 상승 jump2 → 정점 jump3 → 하강 jump4 (프레임별 개별 폴백)
    $jf = 'side_jump'
    $band = $GRAVITY * 1.5
    if ($vyNow -lt (-$band)) { if (F $p.kind 'side_jump2') { $jf = 'side_jump2' } }
    elseif ($vyNow -gt $band) { if (F $p.kind 'side_jump4') { $jf = 'side_jump4' } }
    else { if (F $p.kind 'side_jump3') { $jf = 'side_jump3' } }
    $p.frame = $jf
    if ($j.tick -ge $j.t) {
      $w = Find-Plat $j.plat.id
      if ($null -eq $w) { $p.state='fall'; $p.vx=$j.vx; $p.vy=2 } else { Land-On $p $w }
      $p.jump = $null
    }
    return
  }

  if ($st -eq 'fall') {
    $prevFeet = Feet $p
    $p.vy = [Math]::Min($MAX_FALL, $p.vy + $GRAVITY)
    $p.x += $p.vx; $p.y += $p.vy
    $p.x = [Math]::Max($App.plat.workLeft - 8, [Math]::Min($App.plat.workRight - $SPR + 8, $p.x))
    $hit = Landing (Cx $p) $prevFeet (Feet $p)
    if ($null -ne $hit) { Land-On $p $hit }
    elseif ((Feet $p) -gt $App.plat.workBottom) { Land-On $p 'ground' }
    else { $p.frame = 'side_startle' }
    return
  }

  # ---- 지지 상태
  if ($null -ne $p.platform) {
    $w = Find-Plat $p.platform.id
    if ($null -eq $w) { $p.platform=$null; $p.state='fall'; $p.vy=0; return }
    $p.x += $w.left - $p.platLeft
    $p.platLeft = $w.left; $p.platform = $w
    $mycx = Cx $p
    if ($mycx -lt $w.left -or $mycx -gt $w.right) { $p.platform=$null; $p.state='fall'; $p.vy=0; return }
    if ((($App.tick + $p.id * 4) % 8) -eq 0 -and -not (Plat-Visible $w $mycx)) {
      $p.platform=$null; $p.state='fall'; $p.vy=0; return   # 창이 다른 창에 가려짐 → 낙하
    }
    $p.y = Stand-Y $p $w
    $leftLim = $w.left + 4; $rightLim = $w.right - $SPR - 4
    if ($leftLim -gt $rightLim) { $leftLim = $w.left; $rightLim = $w.right - $SPR }
  } else {
    $p.y = Ground-Y $p
    $leftLim = $App.plat.workLeft + 2; $rightLim = $App.plat.workRight - $SPR - 2
  }

  $p.timer--

  if (@('walk','run','chase','flee','carry','zoomies','sniff','sneak','trot') -contains $st) {
    $speed = $WALK_SPEED
    $frame = 'side_walk'
    switch ($st) {
      'walk'    { $speed=$WALK_SPEED
                  $cyc = $script:WalkCyc[$p.kind]
                  $per = if ($cyc.Count -ge 3) { 5 } else { 8 }
                  $frame = $cyc[([int]([Math]::Floor($p.anim / $per))) % $cyc.Count] }
      'trot'    { $speed=$WALK_SPEED*1.5; $frame = AF $p 'side_trot' 5 }
      'run'     { $speed=$RUN_SPEED
                  $cyc = $script:RunCyc[$p.kind]
                  $frame = $cyc[([int]([Math]::Floor($p.anim / 4))) % $cyc.Count] }
      'chase'   { $speed=$RUN_SPEED*1.2
                  $cyc = $script:RunCyc[$p.kind]
                  $frame = $cyc[([int]([Math]::Floor($p.anim / 4))) % $cyc.Count] }
      'flee'    { $speed=$RUN_SPEED*0.85
                  $cyc = $script:RunCyc[$p.kind]
                  $frame = $cyc[([int]([Math]::Floor($p.anim / 4))) % $cyc.Count] }
      'carry'   { $speed=$WALK_SPEED*0.6
                  $cyc = $script:WalkCyc[$p.kind]
                  $frame = $cyc[([int]([Math]::Floor($p.anim / 8))) % $cyc.Count] }
      'zoomies' { $speed=$RUN_SPEED*1.5
                  $cyc = $script:RunCyc[$p.kind]
                  $frame = $cyc[([int]([Math]::Floor($p.anim / 4))) % $cyc.Count] }
      'sniff'   { $speed=$WALK_SPEED*0.4;  $frame = AF $p 'side_sniff' 7 }
      'sneak'   { $speed=$WALK_SPEED*0.45; $frame = AF $p 'side_sneak' 7 }
    }
    if ($st -eq 'zoomies') {
      if ($p.skid -gt 0) { $p.skid--; $frame='side_skid'; $speed=$speed*0.3 }
      elseif ($rng.NextDouble() -lt 0.05) { $p.facing = -$p.facing; $p.skid = 7 }
    }
    if ($st -eq 'chase' -and $null -ne $p.partner) {
      $p.facing = Sign1 ($p.partner.x -gt $p.x)
      if ([Math]::Abs($p.partner.x - $p.x) -lt ($SPR*0.7)) {
        $q = $p.partner; Detach-Social $p
        $p.state='pounce'; $p.timer=16; $p.seq=0
        $q.state='caught'; $q.timer=26
        Spawn-Hearts (Cx $p) ($p.y + 6) 2
      }
    } elseif ($st -eq 'flee' -and $null -ne $p.partner) {
      $p.facing = Sign1 ($p.partner.x -lt $p.x)
    }
    $prevX = $p.x
    $p.x += $speed * $p.facing
    if ($null -eq $p.platform) {
      $gNew = Ground-Y $p
      if (($gNew - $p.y) -gt ($SPR * 0.25)) {
        # 옆 모니터 바닥이 더 낮음 → 자연 낙하로 넘어가기
        $p.state = 'fall'; $p.vy = 0; $p.frame = $frame; return
      } elseif (($p.y - $gNew) -gt ($SPR * 0.25)) {
        # 더 높은 모니터 단차 → 올라가지 못하고 돌아섬
        $p.x = $prevX; $p.facing = -$p.facing
      }
    }
    if ($p.x -le $leftLim -or $p.x -ge $rightLim) {
      $atRight = $p.x -ge $rightLim
      $p.x = [Math]::Max($leftLim, [Math]::Min($rightLim, $p.x))
      if ($null -ne $p.platform -and (@('run','chase','flee','zoomies') -contains $st) -and $rng.NextDouble() -lt 0.5) { Hop-Off $p; return }
      # 화면 가장자리 벽에 앞발 올리고 기대기
      if ($null -eq $p.platform -and (@('walk','run','sniff') -contains $st) -and $rng.NextDouble() -lt 0.3 -and (F $p.kind 'side_wallstand')) {
        $p.facing = Sign1 $atRight
        $p.x += $p.facing * $SPR * 0.06     # 앞발이 경계에 닿게 살짝 밀착
        $p.state = 'wallstand'; $p.timer = $rng.Next(70,140)
        $p.frame = 'side_wallstand'
        return
      }
      $p.facing = -$p.facing
      if ($st -eq 'zoomies') { $p.skid = 7 }
    }
    $p.frame = $frame
  }
  elseif ($st -eq 'pounce') {
    $p.frame = AF $p (@('side_crouch','side_pounce')[([int]($p.seq / 8)) % 2]) 5
    $p.seq++
    if ($p.timer -le 0) { $p.state='facecam'; $p.timer=50; $p.camframe = Pick $p.kind @('front_laugh','front_happy') }
  }
  elseif ($st -eq 'caught') {
    $p.frame = AF $p 'side_startle' 6
    if ($p.timer -le 0) { $p.state='facecam'; $p.timer=40; $p.camframe='front_happy' }
  }
  elseif ($st -eq 'jumpprep') {
    $p.frame = 'side_jump1'
    if ($p.timer -le 0) {
      $j = $p.jump
      $j.vx = (($j.lx - $p.x) / $j.t)
      $j.vy = ((($j.ty - $p.y) - 0.5 * $GRAVITY * $j.t * $j.t) / $j.t)
      $p.state = 'jump'; $p.platform = $null
      return
    }
  }
  elseif ($st -eq 'seqplay') {
    $idx = [int][Math]::Floor($p.seq / $p.seqPer)
    if ($null -eq $p.seqFrames -or $idx -ge $p.seqFrames.Count) {
      $ns = $p.seqNextState
      $p.state = $ns; $p.timer = $p.seqNextTimer; $p.seq = 0
      if ($ns -eq 'sleep') { $p.zseq = 0 }
      return
    }
    $p.frame = $p.seqFrames[$idx]
    $p.seq++
  }
  elseif ($st -eq 'landing') {
    $lf = @(@('side_land1','side_land2') | Where-Object { F $p.kind $_ })
    if ($lf.Count -gt 0) { $p.frame = $lf[[Math]::Min($lf.Count - 1, [int][Math]::Floor($p.seq / 5))]; $p.seq++ }
    else { $p.frame = AF $p 'side_land' 4 }
    if ($p.timer -le 0) {
      if ($rng.NextDouble() -lt 0.3) { $p.state='shakeoff'; $p.timer=26 } else { $p.state='idle'; $p.timer=$rng.Next(25,70) }
    }
  }
  elseif ($st -eq 'excited') {
    $p.frame = AF $p 'side_excited' 5
  }
  elseif ($st -eq 'shakeoff') {
    $p.frame = AF $p 'side_shake' 3
    if ($p.timer -le 0) { $p.state='idle'; $p.timer=$rng.Next(30,80) }
  }
  elseif ($st -eq 'groom') {
    $stagesG = @('side_scratch','side_lickpaw','side_licknose')
    $p.frame = AF $p ($stagesG[[Math]::Min(2, [int]($p.seq / 70))]) 6
    $p.seq++
  }
  elseif ($st -eq 'rollplay') {
    $stagesR = @('side_roll','side_belly')
    $p.frame = AF $p ($stagesR[[Math]::Min(1, [int]($p.seq / 60))]) 6
    $p.seq++
  }
  elseif ($st -eq 'stretchy') {
    $stagesS = @('side_stretch','side_yawn')
    $p.frame = AF $p ($stagesS[[Math]::Min(1, [int]($p.seq / 55))]) 6
    $p.seq++
  }
  elseif ($st -eq 'lookaround') {
    $opts = @('side_lookback','side_lookup','side_lookdown','side_stand')
    $p.frame = AF $p ($opts[([int]([Math]::Floor($p.anim/22))) % $opts.Count]) 8
    if (($p.anim % 22) -eq 0 -and $rng.NextDouble() -lt 0.4) { $p.facing = -$p.facing }
  }
  elseif ($st -eq 'facecam') {
    $p.frame = AF $p $p.camframe 8
  }
  elseif ($st -eq 'wallstand') {
    $p.frame = AF $p 'side_wallstand' 8
  }
  elseif ($st -eq 'exhausted') {
    $p.frame = AF $p 'side_tired' 10
  }
  elseif ($st -eq 'sit') {
    $p.frame = AF $p 'side_sit' 20
    if ($rng.NextDouble() -lt 0.004) { $p.frame = AF $p 'side_yawn' 6 }
  }
  elseif ($st -eq 'sleep') {
    $p.frame = AF $p 'side_sleep' 22
    $p.zseq++
    if (($p.zseq % 40) -eq 0) {
      $zt = @('z','z Z','z Z Z')[([int]($p.zseq / 40)) % 3]
      foreach ($s in $App.speeches) { if ($s.pet.id -eq $p.id) { $s.form.Controls[0].Text = $zt; $s.form.ClientSize = $s.form.Controls[0].PreferredSize; Style-Bubble $s.form; $s.life = 45; Position-Speech $s; $zt=$null; break } }
      if ($zt) { Say $p $zt 45 }
    }
  }
  else { # idle — 서기 변주
    $opts = @('side_stand','side_proud','side_pawup')
    $p.frame = AF $p ($opts[([int]([Math]::Floor($p.anim/45))) % $opts.Count]) 10
  }

  # 프레임 확정 후 y 재계산 — 프레임 간 발높이(FootPad) 차이로 인한 떨림 방지
  if ($null -ne $p.platform) { $p.y = Stand-Y $p $p.platform } else { $p.y = Ground-Y $p }
  if (@('run','chase','flee','zoomies') -contains $st) {
    $p.y -= [int](([Math]::Abs([Math]::Sin($p.anim*0.5))) * $SPR * 0.03)
  }
  elseif (@('walk','trot','carry','sniff','sneak') -contains $st) {
    $p.y -= [int](([Math]::Abs([Math]::Sin($p.anim*0.3))) * $SPR * 0.012)
  }

  if ($p.timer -le 0 -and (@('landing','pounce','caught','shakeoff','seqplay','jumpprep') -notcontains $st)) {
    if ($null -ne $p.partner) { Detach-Social $p }
    if ($st -eq 'zoomies') { $p.state='exhausted'; $p.timer=70; $p.frame='side_tired'; return }
    if ($st -eq 'sleep') {
      # 깨어나기: 눕기 역순 → 일어나기 → 잠깐 서기 (프레임 없으면 바로 idle)
      Start-Seq $p @('side_liedown3','side_liedown2','side_liedown1','side_rise1','side_rise2') 6 'idle' ($rng.Next(40,90))
      return
    }
    Decide $p
  }
}

# ---------------------------------------------------------------- 펫 생성
function New-Pet($id, $name, $kind, $x) {
  $f = New-Object GPQuietForm
  $f.FormBorderStyle='None'; $f.ShowInTaskbar=$false; $f.TopMost=$true; $f.StartPosition='Manual'
  $f.Width=$SPR; $f.Height=$SPR
  $pb = $null
  if (-not $script:UseULW) {
    $f.BackColor=$CHROMA; $f.TransparencyKey=$CHROMA
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Width=$SPR; $pb.Height=$SPR; $pb.BackColor=$CHROMA; $pb.SizeMode='Zoom'
    $f.Controls.Add($pb)
  }

  $p = @{ id=$id; name=$name; kind=$kind; form=$f; pb=$pb; x=[double]$x; y=[double]0;
          vx=0.0; vy=0.0; facing=(Sign1($rng.Next(2) -eq 0)); state='idle';
          timer=$rng.Next(30,90); anim=0; platform=$null; platLeft=0; jump=$null;
          partner=$null; dragOff=@(0,0); trail=(New-Object System.Collections.ArrayList);
          frame='side_stand'; seq=0; zseq=0; skid=0; camframe='front_happy';
          seqFrames=$null; seqPer=6; seqNextState='idle'; seqNextTimer=40;
          dragStage=3; dragHold=0; dragWant=3;
          lastKey=''; lastBmp=$null; fadeFrom=$null; fade=0; scratch=$null; scratchG=$null }
  $p.y = [double](Ground-Y $p)

  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $menu.Tag = $p
  $hd = $menu.Items.Add($name); $hd.Enabled = $false
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  $mi = $menu.Items.Add(("쓰다듬기 " + [char]0x2665)); $mi.add_Click({ param($s,$e) Pet-Head $s.Owner.Tag })
  $mi = $menu.Items.Add("앉아!"); $mi.add_Click({ param($s,$e) Force-State $s.Owner.Tag 'sit' 200 })
  $mi = $menu.Items.Add("코~ 자자"); $mi.add_Click({ param($s,$e) Force-State $s.Owner.Tag 'sleep' 600 })
  $mi = $menu.Items.Add("일어나!"); $mi.add_Click({ param($s,$e) Force-State $s.Owner.Tag 'idle' 30 })
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  $mi = $menu.Items.Add("크기: 작게"); $mi.add_Click({ Set-PetSize 190 })
  $mi = $menu.Items.Add("크기: 보통"); $mi.add_Click({ Set-PetSize 250 })
  $mi = $menu.Items.Add("크기: 크게"); $mi.add_Click({ Set-PetSize 310 })
  $mi = $menu.Items.Add("크기: 아주 크게"); $mi.add_Click({ Set-PetSize 380 })
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  $mi = $menu.Items.Add("펫 모두 종료"); $mi.add_Click({ [System.Windows.Forms.Application]::Exit() })
  $f.ContextMenuStrip = $menu
  if ($null -ne $pb) { $pb.ContextMenuStrip = $menu; $pb.Tag = $p }
  $f.Tag = $p

  $f.add_MouseDown($script:HDown); $f.add_MouseUp($script:HUp)
  if ($null -ne $pb) {
    $pb.add_MouseDown($script:HDown); $pb.add_MouseUp($script:HUp)
  }

  $null = $f.Handle
  try {
    if ($script:UseULW) { [GPWin]::MakeLayered($f.Handle) } else { [GPWin]::HideFromAltTab($f.Handle) }
  } catch {}
  return $p
}

# ---------------------------------------------------------------- 메인
function Start-App {
  $createdNew = $false
  $script:Mutex = New-Object System.Threading.Mutex($true, 'GLUCK_PETS_NANA_MOMO_SINGLE', [ref]$createdNew)
  if (-not $createdNew) {
    ELog "이미 실행 중 (뮤텍스) — 종료"
    [System.Windows.Forms.MessageBox]::Show("나나·모모가 이미 실행 중이에요!`n안 보이면 작업관리자에서 'Windows PowerShell'을 종료 후 다시 실행해 주세요.", "GLUCK 펫", 'OK', 'Information') | Out-Null
    return
  }

  # 부트스트랩이 스플래시 창을 먼저 만들면 예외모드 변경이 불가 — 실패해도 무해(핸들러는 기본 모드에서도 동작)
  try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) }
  catch { ELog "예외모드 변경 생략 (스플래시 선생성)" }
  $script:ErrCount = 0
  [System.Windows.Forms.Application]::add_ThreadException({
    param($s,$e)
    $script:ErrCount++
    ELog ("이벤트 오류 #" + $script:ErrCount + ": " + $e.Exception.Message + " || " + $e.Exception.StackTrace)
    if ($script:ErrCount -eq 1) {
      # 첫 오류만 알리고 계속 실행 (일회성 결함으로 앱이 죽지 않게)
      [System.Windows.Forms.MessageBox]::Show(("나나모모에 사소한 오류가 있었지만 계속 실행합니다.`n(반복되면 이 내용을 캡처해 주세요)`n`n" + $e.Exception.Message), "나나모모", 'OK', 'Information') | Out-Null
    }
    if ($script:ErrCount -ge 30) {
      try { if ($script:Timer) { $script:Timer.Stop() } } catch {}
      [System.Windows.Forms.MessageBox]::Show(("오류가 반복되어 종료합니다. 로그: " + $script:LogFile + "`n`n" + $e.Exception.Message), "나나모모", 'OK', 'Error') | Out-Null
      [System.Windows.Forms.Application]::Exit()
    }
  })

  # ULW(픽셀 알파) 실제 렌더 검증 — 화면 구석에 마젠타를 찍고 되읽어 확인
  # (일부 PC는 UpdateLayeredWindow가 성공을 반환해도 실제로는 안 그려짐 → 개가 투명하게 안 보임)
  $script:UseULW = $false
  $tf = $null; $tb = $null
  try {
    $pw = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $px = $pw.Left + 3; $py = $pw.Top + 3
    $tf = New-Object GPQuietForm
    $tf.FormBorderStyle='None'; $tf.ShowInTaskbar=$false; $tf.TopMost=$true; $tf.StartPosition='Manual'
    $tf.Left=$px; $tf.Top=$py; $tf.Width=10; $tf.Height=10
    $null = $tf.Handle
    [GPWin]::MakeLayered($tf.Handle)
    $tb = New-Object System.Drawing.Bitmap(10,10,[System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    for ($yy=0; $yy -lt 10; $yy++) { for ($xx=0; $xx -lt 10; $xx++) { $tb.SetPixel($xx,$yy,[System.Drawing.Color]::FromArgb(255,255,0,255)) } }
    $tf.Show()
    [void][GPLayer]::Draw($tf.Handle, $tb, $px, $py)
    [System.Windows.Forms.Application]::DoEvents()
    [System.Threading.Thread]::Sleep(90)
    [System.Windows.Forms.Application]::DoEvents()
    $c = [GPWin]::ScreenPixel($px+4, $py+4)
    $rr = $c -band 0xFF; $gg = ($c -shr 8) -band 0xFF; $bb = ($c -shr 16) -band 0xFF
    if ($rr -gt 200 -and $bb -gt 200 -and $gg -lt 90) {
      $script:UseULW = $true
      ELog "ULW 검증 성공 (픽셀 알파 모드) — readback rgb=$rr,$gg,$bb"
    } else {
      ELog "ULW 화면에 안 찍힘 → 크로마 모드로 전환 — readback rgb=$rr,$gg,$bb"
    }
  } catch {
    ELog ("ULW 테스트 예외 → 크로마 모드: " + $_.Exception.Message)
  } finally {
    # 예외가 나도 시험용 마젠타 점이 화면에 남지 않게
    if ($null -ne $tf) { try { $tf.Close() } catch {} }
    if ($null -ne $tb) { try { $tb.Dispose() } catch {} }
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  Build-Frames
  Build-Cycles
  ELog ("프레임 로드: " + $Frames.Count + "개, " + [int]$sw.Elapsed.TotalSeconds + "s / 걷기사이클 nana=" + $script:WalkCyc['nana'].Count + " momo=" + $script:WalkCyc['momo'].Count)
  if ($Frames.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(("assets 폴더에 이미지가 없습니다:`n" + $AssetDir), "GLUCK 펫", 'OK', 'Warning') | Out-Null
    return
  }
  Refresh-Platforms
  $waW = $App.plat.workRight - $App.plat.workLeft
  $i = 0
  foreach ($def in $PETS) {
    $x = $App.plat.workLeft + $waW * (0.3 + 0.35 * $i) + $rng.Next(-40, 40)
    $p = New-Pet $i $def.name $def.kind $x
    [void]$App.pets.Add($p)
    $p.form.Show()
    Render-Pet $p
    $i++
  }
  Refresh-Platforms
  ELog ("펫 " + $App.pets.Count + "마리 표시 완료 (ULW=" + $script:UseULW + ")")
  if ($null -ne $SplashForm) { try { $SplashForm.Close() } catch {} }

  # 바로가기를 '나나모모'로 갱신 + 새 아이콘 (기존 설치 자동 마이그레이션)
  # icon2.ico = 나나·모모 얼굴 클로즈업 (새 파일명 → 윈도우 아이콘 캐시 우회)
  try {
    $script:IconWC = New-Object System.Net.WebClient
    $script:IconWC.DownloadFileAsync(
      (New-Object Uri('https://raw.githubusercontent.com/highest14-del/gluck-pets/AI%EA%B4%80%EC%A0%9C/dist/icon2.ico')),
      (Join-Path $HomeDir 'icon2.ico'))
  } catch {}
  try {
    $vbsPath = Join-Path $HomeDir '글룩펫_실행.vbs'
    if (Test-Path $vbsPath) {
      # 주의: PS 변수는 대소문자 무시 — $sc를 쓰면 스케일 $SC를 덮어써 op_Multiply COM 오류 발생 (실사례)
      $wshell = New-Object -ComObject WScript.Shell
      $desk = [Environment]::GetFolderPath('Desktop')
      $lnkObj = $wshell.CreateShortcut((Join-Path $desk '나나모모.lnk'))
      $lnkObj.TargetPath = 'wscript.exe'
      $lnkObj.Arguments = '"' + $vbsPath + '"'
      $lnkObj.WorkingDirectory = $HomeDir
      $ic2 = Join-Path $HomeDir 'icon2.ico'
      if (Test-Path $ic2) { $lnkObj.IconLocation = $ic2 }
      else { $lnkObj.IconLocation = (Join-Path $HomeDir 'icon.ico') }
      $lnkObj.Description = '나나와 모모 - 실사 데스크톱 펫'
      $lnkObj.WindowStyle = 7
      $lnkObj.Save()
      $old = Join-Path $desk 'GLUCK 펫.lnk'
      if (Test-Path $old) { Remove-Item $old -Force }
      ELog "바로가기 '나나모모' 갱신"
    }
  } catch { ELog ("바로가기 갱신 실패(무시): " + $_.Exception.Message) }

  # 부트스트랩 자기 갱신 (펫 표시 후 조용히 — 다음 실행부터 새 부트스트랩 적용)
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $script:BootWC = New-Object System.Net.WebClient
    $script:BootWC.DownloadFileAsync(
      (New-Object Uri('https://raw.githubusercontent.com/highest14-del/gluck-pets/AI%EA%B4%80%EC%A0%9C/dist/bootstrap.ps1')),
      (Join-Path $HomeDir 'bootstrap.ps1.tmp'))
    ELog "부트스트랩 자기 갱신 시작(비동기, tmp)"
  } catch { ELog ("부트스트랩 갱신 실패(무시): " + $_.Exception.Message) }

  $script:Timer = New-Object System.Windows.Forms.Timer
  $script:Timer.Interval = $TICK_MS
  $script:Timer.add_Tick({
    $App.tick++
    if ($App.tick -eq 500) {
      # 부트스트랩 tmp 검증 → 마커 있으면 원자 교체, 아니면 폐기 (반쪽 파일 벽돌 방지)
      try {
        $bTmp = Join-Path $HomeDir 'bootstrap.ps1.tmp'
        if (Test-Path $bTmp) {
          $bTail = Get-Content $bTmp -Tail 3 -Encoding UTF8
          if ($bTail -match 'GLUCK-PETS-EOF') {
            Move-Item -Force $bTmp (Join-Path $HomeDir 'bootstrap.ps1')
            ELog "부트스트랩 자기 갱신 완료(검증됨)"
          } else { Remove-Item $bTmp -Force; ELog "부트스트랩 tmp 폐기(불완전)" }
        }
      } catch { ELog ("부트스트랩 교체 실패(무시): " + $_.Exception.Message) }
    }
    if (($App.tick % 16) -eq 1) { Refresh-Platforms }
    foreach ($p in $App.pets) { Update-Pet $p }
    $dead = New-Object System.Collections.ArrayList
    foreach ($h in $App.hearts) {
      $h.y -= 3; $h.life--
      if ($h.life -le 0) { [void]$dead.Add($h) } else { $h.form.Top = [int]$h.y }
    }
    foreach ($h in $dead) { $h.form.Close(); $App.hearts.Remove($h) }
    $deadSp = New-Object System.Collections.ArrayList
    foreach ($s in $App.speeches) {
      $s.life--
      if ($s.life -le 0) { [void]$deadSp.Add($s) } else { Position-Speech $s }
    }
    foreach ($s in $deadSp) { $s.form.Close(); $App.speeches.Remove($s) }
    foreach ($p in $App.pets) { Render-Pet $p }
  })
  $script:Timer.Start()
  $ctx = New-Object System.Windows.Forms.ApplicationContext
  [System.Windows.Forms.Application]::Run($ctx)
}

try { Start-App } catch {
  [System.Windows.Forms.MessageBox]::Show(("GLUCK 펫 실행 오류:`n" + $_.Exception.Message + "`n`n" + $_.ScriptStackTrace), "GLUCK 펫", 'OK', 'Error') | Out-Null
}
# GLUCK-PETS-EOF
