
# ================================================================
#  GLUCK PETS v2 — 나나 & 모모 실사 데스크톱 펫 (PowerShell/WinForms)
#  설치 불필요. assets/ 의 실사 PNG + manifest.json 로드.
#  ※ gen_ps1_photo.py 가 생성. 직접 수정 금지.
# ================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
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
  public static void Draw(IntPtr hwnd, System.Drawing.Bitmap bmp, int x, int y) {
    IntPtr screenDc = GetDC(IntPtr.Zero);
    IntPtr memDc = CreateCompatibleDC(screenDc);
    IntPtr hBmp = bmp.GetHbitmap(System.Drawing.Color.FromArgb(0,0,0,0));
    IntPtr old = SelectObject(memDc, hBmp);
    POINT dst = new POINT(x, y);
    SIZE sz = new SIZE(bmp.Width, bmp.Height);
    POINT src = new POINT(0, 0);
    BLEND bf = new BLEND(); bf.op = 0; bf.alpha = 255; bf.fmt = 1;
    UpdateLayeredWindow(hwnd, screenDc, ref dst, ref sz, memDc, ref src, 0, ref bf, 2);
    SelectObject(memDc, old);
    DeleteObject(hBmp);
    DeleteDC(memDc);
    ReleaseDC(IntPtr.Zero, screenDc);
  }
}
"@

[void][GPWin]::SetProcessDPIAware()

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

# ---------------------------------------------------------------- 에셋 로드
function Build-Frames {
  foreach ($im in $Manifest.images) {
    $path = Join-Path $AssetDir ($im.file -replace '/', '\')
    if (-not (Test-Path $path)) { continue }
    $srcImg = [System.Drawing.Image]::FromFile($path)
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
}

function Foot($p) { $k = "$($p.kind)|$($p.frame)"; if ($FootPad.ContainsKey($k)) { return $FootPad[$k] } return 4 }
function Ground-Y($p) { return $App.plat.workBottom - $SPR + (Foot $p) }
function Stand-Y($p, $plat) { return $plat.top - $SPR + (Foot $p) }
function Find-Plat($id) { foreach ($w in $App.plat.windows) { if ($w.id -eq $id) { return $w } } return $null }
function Feet($p) { return $p.y + $SPR - (Foot $p) }
function Cx($p) { return $p.x + $SPR / 2 }
function Other-Pet($p) { foreach ($q in $App.pets) { if ($q.id -ne $p.id) { return $q } } return $null }

function Landing($cx, $prevFeet, $newFeet) {
  $best = $null
  foreach ($w in $App.plat.windows) {
    if (($w.left+8) -le $cx -and $cx -le ($w.right-8) -and $prevFeet -le $w.top -and $w.top -le $newFeet) {
      if ($null -eq $best -or $w.top -lt $best.top) { $best = $w }
    }
  }
  if ($null -ne $best) { return $best }
  if ($newFeet -ge $App.plat.workBottom) { return 'ground' }
  return $null
}

# ---------------------------------------------------------------- 렌더
function Render-Pet($p) {
  $bmp = $Frames["$($p.kind)|$($p.frame)|$($p.facing)"]
  if ($null -eq $bmp) { $bmp = $Frames["$($p.kind)|side_stand|$($p.facing)"] }
  if ($null -eq $bmp) { return }
  if ($script:UseULW) {
    try { [GPLayer]::Draw($p.form.Handle, $bmp, [int]$p.x, [int]$p.y); return } catch { $script:UseULW = $false }
  }
  if ($null -eq $p.pb) {
    # ULW 실패 시 크로마키 폴백을 즉석 구성
    $p.form.BackColor = $CHROMA; $p.form.TransparencyKey = $CHROMA
    $pb2 = New-Object System.Windows.Forms.PictureBox
    $pb2.Width=$SPR; $pb2.Height=$SPR; $pb2.BackColor=$CHROMA; $pb2.SizeMode='Zoom'
    $pb2.Tag = $p
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
      if (@('chase','flee','carry','ride') -contains $q.state) { $q.state = 'idle'; $q.timer = 40 }
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

function Say($p, $text, $life=95) {
  foreach ($s in $App.speeches) { if ($s.pet.id -eq $p.id) { return } }
  $bf = New-Object System.Windows.Forms.Form
  $bf.FormBorderStyle='None'; $bf.ShowInTaskbar=$false; $bf.TopMost=$true; $bf.StartPosition='Manual'
  $lbl = New-Object System.Windows.Forms.Label
  $lbl.AutoSize=$true; $lbl.Text=$text
  $lbl.Font=New-Object System.Drawing.Font('Malgun Gothic', 10)
  $lbl.BackColor=[System.Drawing.Color]::FromArgb(255,255,252,240)
  $lbl.ForeColor=[System.Drawing.Color]::FromArgb(255,60,50,45)
  $lbl.BorderStyle='FixedSingle'
  $lbl.Padding=(New-Object System.Windows.Forms.Padding(8,5,8,5))
  $bf.Controls.Add($lbl)
  $sz = $lbl.PreferredSize
  $bf.ClientSize = New-Object System.Drawing.Size($sz.Width, $sz.Height)
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
    $hf = New-Object System.Windows.Forms.Form
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

function Force-State($p,$state,$ticks) { if ($p.state -eq 'drag') { return }; Detach-Social $p; $p.state=$state; $p.timer=$ticks; $p.vx=0; $p.seq=0 }
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
  $cur = [System.Windows.Forms.Cursor]::Position
  $p.dragOff = @(($cur.X - $p.x), ($cur.Y - $p.y))
  $p.trail.Clear()
  $p.dragStage = 0; $p.dragHold = 0
}
function On-DragMove($p) {
  if ($p.state -ne 'drag') { return }
  $cur = [System.Windows.Forms.Cursor]::Position
  $nx = $cur.X - $p.dragOff[0]; $ny = $cur.Y - $p.dragOff[1]
  [void]$p.trail.Add(@(($nx - $p.x), ($ny - $p.y)))
  while ($p.trail.Count -gt 5) { $p.trail.RemoveAt(0) }
  $p.x = $nx; $p.y = $ny
}
function On-Release($p) {
  if ($p.state -ne 'drag') { return }
  if ($p.trail.Count -gt 0) {
    $sx=0.0; $sy=0.0
    foreach ($d in $p.trail) { $sx += $d[0]; $sy += $d[1] }
    $p.vx = [Math]::Max(-20, [Math]::Min(20, ($sx / $p.trail.Count) * 0.7))
    $p.vy = [Math]::Max(-18, [Math]::Min(12, ($sy / $p.trail.Count) * 0.7))
  } else { $p.vx = 0; $p.vy = 0 }
  $p.state = 'fall'
}

function Drag-Frame($p) {
  # 대롱대롱 4단계: side_hang90/hang60/hang30/front_hang0 (없으면 폴백)
  $cur = [System.Windows.Forms.Cursor]::Position
  $dx = $cur.X - (Cx $p)
  $adx = [Math]::Abs($dx)
  $R = $SPR * 1.2
  $ratio = $adx / $R
  # 단계 판정 (가이드: 0.75/0.45/0.15) — 깜빡임 방지는 3틱(90ms) 유지 조건으로
  $want = 3
  if ($ratio -ge 0.75) { $want = 0 }
  elseif ($ratio -ge 0.45) { $want = 1 }
  elseif ($ratio -ge 0.15) { $want = 2 }
  if ($want -ne $p.dragStage) {
    $p.dragHold++
    if ($p.dragHold -ge 3) { $p.dragStage = $want; $p.dragHold = 0 }
  } else { $p.dragHold = 0 }
  if ($dx -ne 0) { $p.facing = Sign1 ($dx -gt 0) }
  $stages = @('side_hang90','side_hang60','side_hang30','front_hang0')
  $f = $stages[$p.dragStage]
  if (F $p.kind $f) { return $f }
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
    $p.camframe = Pick $p.kind @('front_happy','front_curious','front_focus','front_wink','front_tongue','front_beg','front_laugh','front_stare')
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

  if ($st -eq 'drag') { $p.frame = Drag-Frame $p; return }

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
      'walk'    { $speed=$WALK_SPEED;      $frame = @('side_walk','side_trot')[([int]([Math]::Floor($p.anim/8)) % 2)] }
      'run'     { $speed=$RUN_SPEED;       $frame='side_run' }
      'chase'   { $speed=$RUN_SPEED*1.2;   $frame='side_run' }
      'flee'    { $speed=$RUN_SPEED*0.85;  $frame='side_run' }
      'carry'   { $speed=$WALK_SPEED*0.6;  $frame='side_walk' }
      'zoomies' { $speed=$RUN_SPEED*1.5;   $frame='side_run' }
      'sniff'   { $speed=$WALK_SPEED*0.4;  $frame='side_sniff' }
      'sneak'   { $speed=$WALK_SPEED*0.45; $frame='side_sneak' }
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
    # 걷기/달리기 미세 바운스
    if (@('run','chase','flee','zoomies') -contains $st) { $p.y -= [int](([Math]::Abs([Math]::Sin($p.anim*0.5))) * $SPR * 0.03) }
    $p.frame = $frame
  }
  elseif ($st -eq 'pounce') {
    $p.frame = @('side_crouch','side_pounce')[([int]($p.seq / 8)) % 2]
    $p.seq++
    if ($p.timer -le 0) { $p.state='facecam'; $p.timer=50; $p.camframe = Pick $p.kind @('front_laugh','front_happy') }
  }
  elseif ($st -eq 'caught') {
    $p.frame = 'side_startle'
    if ($p.timer -le 0) { $p.state='facecam'; $p.timer=40; $p.camframe='front_happy' }
  }
  elseif ($st -eq 'landing') {
    $p.frame = 'side_land'
    if ($p.timer -le 0) {
      if ($rng.NextDouble() -lt 0.3) { $p.state='shakeoff'; $p.timer=26 } else { $p.state='idle'; $p.timer=$rng.Next(25,70) }
    }
  }
  elseif ($st -eq 'shakeoff') {
    $p.frame = 'side_shake'
    if ($p.timer -le 0) { $p.state='idle'; $p.timer=$rng.Next(30,80) }
  }
  elseif ($st -eq 'groom') {
    $stagesG = @('side_scratch','side_lickpaw','side_licknose')
    $p.frame = $stagesG[[Math]::Min(2, [int]($p.seq / 70))]
    $p.seq++
  }
  elseif ($st -eq 'rollplay') {
    $stagesR = @('side_roll','side_belly')
    $p.frame = $stagesR[[Math]::Min(1, [int]($p.seq / 60))]
    $p.seq++
  }
  elseif ($st -eq 'stretchy') {
    $stagesS = @('side_stretch','side_yawn')
    $p.frame = $stagesS[[Math]::Min(1, [int]($p.seq / 55))]
    $p.seq++
  }
  elseif ($st -eq 'lookaround') {
    $opts = @('side_lookback','side_lookup','side_lookdown','side_stand')
    $p.frame = $opts[([int]([Math]::Floor($p.anim/22))) % $opts.Count]
    if (($p.anim % 22) -eq 0 -and $rng.NextDouble() -lt 0.4) { $p.facing = -$p.facing }
  }
  elseif ($st -eq 'facecam') {
    $p.frame = $p.camframe
  }
  elseif ($st -eq 'wallstand') {
    $p.frame = 'side_wallstand'
  }
  elseif ($st -eq 'sit') {
    $p.frame = 'side_sit'
    if ($rng.NextDouble() -lt 0.004) { $p.frame='side_yawn' }
  }
  elseif ($st -eq 'sleep') {
    $p.frame = 'side_sleep'
    $p.zseq++
    if (($p.zseq % 40) -eq 0) {
      $zt = @('z','z Z','z Z Z')[([int]($p.zseq / 40)) % 3]
      foreach ($s in $App.speeches) { if ($s.pet.id -eq $p.id) { $s.form.Controls[0].Text = $zt; $s.life = 45; Position-Speech $s; $zt=$null; break } }
      if ($zt) { Say $p $zt 45 }
    }
  }
  else { # idle — 서기 변주
    $opts = @('side_stand','side_proud','side_pawup')
    $p.frame = $opts[([int]([Math]::Floor($p.anim/45))) % $opts.Count]
  }

  if ($p.timer -le 0 -and $st -ne 'landing' -and $st -ne 'pounce' -and $st -ne 'caught' -and $st -ne 'shakeoff') {
    if ($null -ne $p.partner) { Detach-Social $p }
    if ($st -eq 'zoomies') { $p.state='exhausted'; $p.timer=70; $p.frame='side_tired'; return }
    if ($st -eq 'exhausted') { }
    Decide $p
  }
  elseif ($st -eq 'exhausted') { $p.frame='side_tired'; if ($p.timer -le 0) { Decide $p } }
}

# ---------------------------------------------------------------- 펫 생성
function New-Pet($id, $name, $kind, $x) {
  $f = New-Object System.Windows.Forms.Form
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
          dragStage=0; dragHold=0; dragStage3=0 }
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

  $handler_down = { param($s,$e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { On-Grab $s.Tag } }
  $handler_move = { param($s,$e) On-DragMove $s.Tag }
  $handler_up = { param($s,$e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { On-Release $s.Tag } }
  $handler_dbl = { param($s,$e) Pet-Head $s.Tag }
  $f.add_MouseDown($handler_down); $f.add_MouseMove($handler_move)
  $f.add_MouseUp($handler_up); $f.add_MouseDoubleClick($handler_dbl)
  if ($null -ne $pb) {
    $pb.add_MouseDown($handler_down); $pb.add_MouseMove($handler_move)
    $pb.add_MouseUp($handler_up); $pb.add_MouseDoubleClick($handler_dbl)
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
  if (-not $createdNew) { return }

  [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
  [System.Windows.Forms.Application]::add_ThreadException({
    param($s,$e)
    [System.Windows.Forms.MessageBox]::Show(("GLUCK 펫 오류:`n" + $e.Exception.Message + "`n`n" + $e.Exception.StackTrace), "GLUCK 펫", 'OK', 'Error') | Out-Null
    [System.Windows.Forms.Application]::Exit()
  })

  Build-Frames
  if ($Frames.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("assets 폴더에 이미지가 없습니다. 설치 폴더를 확인해 주세요.", "GLUCK 펫", 'OK', 'Warning') | Out-Null
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

  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = $TICK_MS
  $timer.add_Tick({
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
  $timer.Start()
  $ctx = New-Object System.Windows.Forms.ApplicationContext
  [System.Windows.Forms.Application]::Run($ctx)
}

try { Start-App } catch {
  [System.Windows.Forms.MessageBox]::Show(("GLUCK 펫 실행 오류:`n" + $_.Exception.Message + "`n`n" + $_.ScriptStackTrace), "GLUCK 펫", 'OK', 'Error') | Out-Null
}
