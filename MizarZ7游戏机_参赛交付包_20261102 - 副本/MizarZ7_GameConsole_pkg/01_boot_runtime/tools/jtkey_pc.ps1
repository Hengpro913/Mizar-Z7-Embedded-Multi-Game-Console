#=============================================================================
# jtkey_pc.ps1 - PC keyboard -> jtkey_daemon.tcl -> board K4/K5/K6/K7
#
#   Left  / A  -> K4            Right / D -> K5
#   Up    / W  -> K6            Down  / S -> K7
#   Enter / Space : K5 held 0.9 s = ok_p  (menu confirm / tetris drop / flap)
#   Q     / Esc   : K7 held 0.9 s = back_p(return to menu / flappy restart)
#   F12           : quit
#
#   DIRECTION KEYS ARE LEVEL BASED.
#   The board key stays pressed for exactly as long as the PC key is physically
#   down, so BREAKOUT moves the paddle continuously (4 px per video frame)
#   instead of stepping by fixed 160 ms taps.  Releasing the PC key releases
#   the board key, so repeated taps are also immediate (no throttle).
#
#   Run  : double-click jtkey_pc.cmd   (this window must keep the focus)
#   Quit : F12
#
#   NOTE: ASCII-only on purpose. Windows PowerShell 5.1 decodes BOM-less
#         UTF-8 as ANSI and would break the string literals.
#=============================================================================
$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$cmdFile = Join-Path $here 'jtkey.cmd'
$logFile = Join-Path $here 'jtkey_daemon.log'

Add-Type -Namespace Win32 -Name Kbd -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Auto, ExactSpelling = true)]
public static extern short GetAsyncKeyState(int vKey);
'@

function IsDown([int]$vk) {
    # 0x8000 = key currently down (level, unaffected by key auto-repeat)
    return ((([int][Win32.Kbd]::GetAsyncKeyState($vk)) -band 0x8000) -ne 0)
}

# The daemon polls this file every 20 ms and briefly holds an exclusive handle,
# so a plain write can collide with it: retry instead of aborting.
function Put-Key([int]$code) {
    for ($i = 0; $i -lt 40; $i++) {
        try {
            [System.IO.File]::WriteAllText($cmdFile, [string]$code)
            return $true
        } catch {
            Start-Sleep -Milliseconds 5
        }
    }
    Write-Host '[!] mailbox write failed - is the daemon running?' -ForegroundColor Red
    return $false
}

if (-not (Test-Path $logFile)) {
    Write-Host '[!] daemon log not found:' $logFile -ForegroundColor Red
    Write-Host '    run jtkey_daemon_run.cmd first' -ForegroundColor Yellow
    exit 1
}
if (-not ((Get-Content $logFile -Raw) -match 'JTKEY_READY')) {
    Write-Host '[!] daemon not ready, log tail:' -ForegroundColor Red
    Get-Content $logFile -Tail 3 | ForEach-Object { Write-Host '    ' $_ }
    exit 1
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  PC keyboard -> Mizar Z7 key injection        (F12 quit)' -ForegroundColor Cyan
Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host '  Arrows / WASD : Left=K4  Right=K5  Up=K6  Down=K7  (HOLD)' -ForegroundColor Gray
Write-Host '                  hold to move the breakout paddle, tap to step' -ForegroundColor Gray
Write-Host '  Enter / Space : K5 long  = confirm / drop / flap' -ForegroundColor Gray
Write-Host '  Q     / Esc   : K7 long  = back to menu' -ForegroundColor Gray
Write-Host '  THIS WINDOW MUST KEEP FOCUS' -ForegroundColor Yellow
Write-Host '============================================================' -ForegroundColor Cyan

$names = @{ 1 = 'K4 LEFT'; 2 = 'K5 RIGHT'; 4 = 'K6 UP'; 8 = 'K7 DOWN' }

$cur        = -1      # last value handed to the daemon
$longCode   = 0       # non-zero while a scripted long press is running
$longUntil  = 0
$prevEnter  = $false
$prevBack   = $false
$prevQuit   = $false
$prevText   = ''

Put-Key 0
$cur = 0

while ($true) {
    $now = [Environment]::TickCount

    # ---------------- quit ----------------
    $q = IsDown 0x7B                      # F12
    if ($q -and -not $prevQuit) {
        Write-Host ''
        Write-Host '[quit]' -ForegroundColor Yellow
        Put-Key 0
        exit 0
    }
    $prevQuit = $q

    # ---------------- scripted long press ----------------
    if ($longUntil -ne 0) {
        if ($now -lt $longUntil) {
            if ($cur -ne $longCode) { Put-Key $longCode; $cur = $longCode }
            Start-Sleep -Milliseconds 10
            continue
        }
        $longUntil = 0
        Put-Key 0
        $cur = 0
        Start-Sleep -Milliseconds 130   # let the debounce / key_ctrl settle
        continue
    }

    # ---------------- one-shot long presses (edge triggered) ----------------
    $okKey = (IsDown 0x0D) -or (IsDown 0x20)          # Enter / Space -> K5
    $bkKey = (IsDown 0x1B) -or (IsDown 0x51)          # Esc   / Q     -> K7
    if ($okKey -and -not $prevEnter) {
        $prevEnter = $true
        $prevBack  = $bkKey
        Put-Key 0
        $cur = 0
        $longCode  = 2
        $longUntil = $now + 900
        Write-Host 'LONG  K5 RIGHT  (ok)' -ForegroundColor Magenta
        continue
    }
    if ($bkKey -and -not $prevBack) {
        $prevEnter = $okKey
        $prevBack  = $true
        Put-Key 0
        $cur = 0
        $longCode  = 8
        $longUntil = $now + 900
        Write-Host 'LONG  K7 DOWN   (back)' -ForegroundColor Magenta
        continue
    }
    $prevEnter = $okKey
    $prevBack  = $bkKey

    # ---------------- held direction keys ----------------
    $want = 0
    if ((IsDown 0x25) -or (IsDown 0x41)) { $want = $want -bor 1 }   # Left / A
    if ((IsDown 0x27) -or (IsDown 0x44)) { $want = $want -bor 2 }   # Right/ D
    if ((IsDown 0x26) -or (IsDown 0x57)) { $want = $want -bor 4 }   # Up   / W
    if ((IsDown 0x28) -or (IsDown 0x53)) { $want = $want -bor 8 }   # Down / S

    if ($want -ne $cur) {
        Put-Key $want
        $cur = $want
        if ($want -eq 0) {
            if ($prevText -ne '') { Write-Host '        release' -ForegroundColor DarkGray }
            $prevText = ''
        } else {
            $t = ''
            if ($want -band 1) { $t = 'K4' }
            if ($want -band 2) { if ($t -ne '') { $t = $t + ' ' }; $t = $t + 'K5' }
            if ($want -band 4) { if ($t -ne '') { $t = $t + ' ' }; $t = $t + 'K6' }
            if ($want -band 8) { if ($t -ne '') { $t = $t + ' ' }; $t = $t + 'K7' }
            $prevText = $t
            Write-Host ('HOLD  {0}' -f $t.Trim()) -ForegroundColor Green
        }
    }

    Start-Sleep -Milliseconds 8
}
