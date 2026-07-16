
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
  [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLEND pblend, int dwFlags);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
  [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hDC);
  [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
  [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hDC, IntPtr h);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
  public static bool Draw(IntPtr hwnd, System.Drawing.Bitmap bmp, int x, int y) {
    IntPtr screenDc = GetDC(IntPtr.Zero);
    IntPtr memDc = IntPtr.Zero; IntPtr hBmp = IntPtr.Zero; IntPtr old = IntPtr.Zero;
    try {
      memDc = CreateCompatibleDC(screenDc);
      hBmp = bmp.GetHbitmap(System.Drawing.Color.FromArgb(0,0,0,0));
      old = SelectObject(memDc, hBmp);
      POINT dst = new POINT(x, y);
      SIZE sz = new SIZE(bmp.Width, bmp.Height);
      POINT src = new POINT(0, 0);
      BLEND bf = new BLEND(); bf.op = 0; bf.alpha = 255; bf.fmt = 1;
      return UpdateLayeredWindow(hwnd, screenDc, ref dst, ref sz, memDc, ref src, 0, ref bf, 2);
    } finally {
      if (old != IntPtr.Zero) SelectObject(memDc, old);
      if (hBmp != IntPtr.Zero) DeleteObject(hBmp);
      if (memDc != IntPtr.Zero) DeleteDC(memDc);
      ReleaseDC(IntPtr.Zero, screenDc);
    }
  }
}
public class GPQuietForm : System.Windows.Forms.Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override System.Windows.Forms.CreateParams CreateParams {
    get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000; return cp; }  // WS_EX_NOACTIVATE — 포커스 강탈 방지
  }
}
"@

[void][GPWin]::SetProcessDPIAware()
ELog "Add-Type OK"

# ---------------------------------------------------------------- 설정
$PET_H = 250            # 화면상 펫 캔버스 높이(px) — 200~340 취향껏
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

$script:WalkCyc = @{}
$script:RunCyc = @{}
function Build-Cycles {
  foreach ($kind in @('nana','momo')) {
    $wc = @()
    foreach ($n in @('side_walk1','side_walk2','side_walk3','side_walk4')) { if (F $kind $n) { $wc += $n } }
    if ($wc.Count -ge 2) { $script:WalkCyc[$kind] = $wc }         # 진짜 보행 사이클 (발 교차)
    else { $script:WalkCyc[$kind] = @('side_walk','side_trot') }  # 폴백: 걷기/종종걸음 교대
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
  $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $App.plat.workLeft = $wa.Left; $App.plat.workTop = $wa.Top
  $App.plat.workRight = $wa.Right; $App.plat.workBottom = $wa.Bottom
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
function Ground-Y($p) { return $App.plat.workBottom - $SPR + (Foot $p) }
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
  if ($newFeet -ge $App.plat.workBottom) { return 'ground' }
  return $null
}

# ---------------------------------------------------------------- 렌더
$script:FadeCM = New-Object System.Drawing.Imaging.ColorMatrix
$script:FadeIA = New-Object System.Drawing.Imaging.ImageAttributes
$FADE_TICKS = 5   # 프레임 전환 크로스페이드 길이 (5틱 = 150ms)

function Render-Pet($p) {
  $key = "$($p.kind)|$($p.frame)|$($p.facing)"
  $bmp = $Frames[$key]
  if ($null -eq $bmp) { $bmp = $Frames["$($p.kind)|side_stand|$($p.facing)"] }
  if ($null -eq $bmp) { return }
  # 프레임 전환 감지 → 페이드 시작
  if ($p.lastKey -ne $key) {
    if ($null -ne $p.lastBmp -and $p.lastBmp -ne $bmp) { $p.fadeFrom = $p.lastBmp; $p.fade = $FADE_TICKS }
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
  if ($p.pb.Image -ne $bmp) { $p.pb.Image = $bmp }
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
function Interruptible($p) { return (@('idle','walk','sit','sniff','lookaround') -contains $p.state) }
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
}

function Say-Emotion($p, $frame) {
  if ($SAY.ContainsKey($frame)) {
    $arr = $SAY[$frame]
    Say $p ($arr[$rng.Next($arr.Count)])
  }
}

function Spawn-Hearts($x, $y, $n) {
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
}

function Force-State($p,$state,$ticks) {
  if (@('drag','jump','fall','ride') -contains $p.state) { return }   # 공중 상태에서 강제 전이 시 순간이동 방지
  Detach-Social $p; $p.state=$state; $p.timer=$ticks; $p.vx=0; $p.seq=0
}
function Pet-Head($p) {
  if (@('drag','fall','jump') -contains $p.state) { return }
  Detach-Social $p; $p.state='facecam'; $p.timer=60; $p.vx=0
  $p.camframe = Pick $p.kind @('front_happy','front_laugh','front_wink')
  Say-Emotion $p $p.camframe
  Spawn-Hearts ((Cx $p) - 20) ($p.y + $SPR*0.1) 3
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
  if ($r -lt 0.16) { $p.state='walk'; $p.facing=Sign1($rng.Next(2) -eq 0); $p.timer=$rng.Next(70,220) }
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
  elseif ($r -lt 0.80) { $p.state='idle'; $p.timer=$rng.Next(50,150) }
  elseif ($r -lt 0.90) { $p.state='sit'; $p.timer=$rng.Next(120,280) }
  else { $p.state='sleep'; $p.timer=$rng.Next(350,750); $p.zseq=0 }
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
  $p.jump = @{ plat=$w; t=$t; tick=0; vx=(($lx - $p.x)/$t); vy=((($ty - $p.y) - 0.5*$GRAVITY*$t*$t)/$t) }
  $p.facing = Sign1 ($lx -ge $p.x)
  $p.state = 'jump'; $p.platform = $null
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
  $p.state = 'landing'; $p.timer = 9
  $p.frame = 'side_land'
  if ($null -ne $plat) { $p.platLeft = $plat.left; $p.y = Stand-Y $p $plat } else { $p.y = Ground-Y $p }
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
    $p.x += $j.vx
    $p.y += $j.vy + $GRAVITY * ($j.tick - 1)
    $p.frame = 'side_jump'
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

  if (@('walk','run','chase','flee','carry','zoomies','sniff','sneak') -contains $st) {
    $speed = $WALK_SPEED
    $frame = 'side_walk'
    switch ($st) {
      'walk'    { $speed=$WALK_SPEED
                  $cyc = $script:WalkCyc[$p.kind]
                  $per = if ($cyc.Count -ge 3) { 5 } else { 8 }
                  $frame = $cyc[([int]([Math]::Floor($p.anim / $per))) % $cyc.Count] }
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
    $p.x += $speed * $p.facing
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
  elseif ($st -eq 'landing') {
    $p.frame = AF $p 'side_land' 4
    if ($p.timer -le 0) {
      if ($rng.NextDouble() -lt 0.3) { $p.state='shakeoff'; $p.timer=26 } else { $p.state='idle'; $p.timer=$rng.Next(25,70) }
    }
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

  if ($p.timer -le 0 -and $st -ne 'landing' -and $st -ne 'pounce' -and $st -ne 'caught' -and $st -ne 'shakeoff') {
    if ($null -ne $p.partner) { Detach-Social $p }
    if ($st -eq 'zoomies') { $p.state='exhausted'; $p.timer=70; $p.frame='side_tired'; return }
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
  [System.Windows.Forms.Application]::add_ThreadException({
    param($s,$e)
    if ($script:Dying) { return }
    $script:Dying = $true
    try { if ($script:Timer) { $script:Timer.Stop() } } catch {}
    ELog ("틱 오류: " + $e.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show(("GLUCK 펫 오류:`n" + $e.Exception.Message + "`n`n" + $e.Exception.StackTrace), "GLUCK 펫", 'OK', 'Error') | Out-Null
    [System.Windows.Forms.Application]::Exit()
  })

  # ULW(픽셀 알파) 사전 테스트 — 실패 시 처음부터 크로마 모드로 생성
  try {
    $tf = New-Object System.Windows.Forms.Form
    $tf.FormBorderStyle='None'; $tf.ShowInTaskbar=$false; $tf.StartPosition='Manual'
    $tf.Left=-2000; $tf.Top=-2000; $tf.Width=8; $tf.Height=8
    $null = $tf.Handle
    [GPWin]::MakeLayered($tf.Handle)
    $tb = New-Object System.Drawing.Bitmap(8,8,[System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $tf.Show()
    [GPLayer]::Draw($tf.Handle, $tb, -2000, -2000)
    $tf.Close(); $tb.Dispose()
    $script:UseULW = $true
    ELog "ULW 테스트 OK (픽셀 알파 모드)"
  } catch {
    $script:UseULW = $false
    ELog ("ULW 실패 → 크로마 모드: " + $_.Exception.Message)
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

  # 부트스트랩 자기 갱신 (펫 표시 후 조용히 — 다음 실행부터 새 부트스트랩 적용)
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $script:BootWC = New-Object System.Net.WebClient
    $script:BootWC.DownloadFileAsync(
      (New-Object Uri('https://raw.githubusercontent.com/highest14-del/gluck-pets/AI%EA%B4%80%EC%A0%9C/dist/bootstrap.ps1')),
      (Join-Path (Join-Path $env:LocalAppData 'GLUCK_PETS') 'bootstrap.ps1'))
    ELog "부트스트랩 자기 갱신 시작(비동기)"
  } catch { ELog ("부트스트랩 갱신 실패(무시): " + $_.Exception.Message) }

  $script:Timer = New-Object System.Windows.Forms.Timer
  $script:Timer.Interval = $TICK_MS
  $script:Timer.add_Tick({
    $App.tick++
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
