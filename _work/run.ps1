param([int]$Seconds=40, [string]$ShotList="10,20,30,40", [string]$Tag="run", [string]$Keys="", [switch]$Foreground, [string]$GameDir)
# Launches a test instance, takes screenshots at the given times, then closes that instance.
# By default the game runs in background mode (SWR_BACKGROUND=1): off-screen, never focused, muted, the real pad
# and keyboard ignored, so a test does not disturb someone using the PC. -Foreground shows the window as usual.
$ErrorActionPreference = "Stop"
$Shots = @($ShotList.Split(",") | ForEach-Object { [int]$_ })
$root = Split-Path -Parent $PSScriptRoot   # the Switch2Recomp folder
$game = if ($GameDir) { (Resolve-Path -LiteralPath $GameDir).Path } else { Join-Path $root "games" }
$exe = Join-Path $game "Recomp.exe"
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Test executable not found at $exe" }
$out  = Join-Path $PSScriptRoot "shots"
New-Item -ItemType Directory -Force $out | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
}
"@
[W]::SetProcessDPIAware() | Out-Null
# Keys: "time:vk,time:vk" e.g. "25:0x0D,27:0x58"  (vk codes)
$keyEvents = @()
if($Keys){ foreach($k in $Keys.Split(',')){ $a=$k.Split(':'); $keyEvents += ,@([double]$a[0], $a[1]) } }
$shotIdx = 0; $keyIdx = 0
$env:SWR_INPUT_UNFOCUSED = "1"   # keys count even if Windows keeps another window in front
$env:SWR_BACKGROUND = if($Foreground){ "" } else { "1" }
if (Get-Process Recomp -ErrorAction SilentlyContinue) {
  throw "Recomp is already running. Close it before starting a test."
}
$p = Start-Process -FilePath $exe -WorkingDirectory $game -PassThru
$t0 = Get-Date
try {
  while(((Get-Date)-$t0).TotalSeconds -lt $Seconds){
    Start-Sleep -Milliseconds 250
    $el = ((Get-Date)-$t0).TotalSeconds
    if($p.HasExited){ Write-Output "exited at $([int]$el)s code $($p.ExitCode)"; break }
    $p.Refresh(); $h = $p.MainWindowHandle
    while($keyIdx -lt $keyEvents.Count -and $el -ge $keyEvents[$keyIdx][0]){
      # "vk+vk@ms": keys pressed together, held for ms (default 200)
      $spec=$keyEvents[$keyIdx][1].Split('@'); $hold= if($spec.Count -gt 1){ [int]$spec[1] } else { 200 }
      $vks=@($spec[0].Split('+') | ForEach-Object { [Convert]::ToInt32($_,16) }); $vk=$keyEvents[$keyIdx][1]
      if($h -ne 0){ if($Foreground){ [W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 100 }
        foreach($v in $vks){ $sc=[W]::MapVirtualKey($v,0); [W]::PostMessage($h,0x100,[IntPtr]$v,[IntPtr](1 -bor ($sc -shl 16))) | Out-Null }
        Start-Sleep -Milliseconds $hold
        foreach($v in $vks){ $sc=[W]::MapVirtualKey($v,0); [W]::PostMessage($h,0x101,[IntPtr]$v,[IntPtr]([int64]0xC0000001 -bor ($sc -shl 16))) | Out-Null } }
      Write-Output "key $vk at $([int]$el)s"; $keyIdx++
    }
    if($shotIdx -lt $Shots.Count -and $el -ge $Shots[$shotIdx]){
      if($h -ne 0){
        # the runtime's own F7 screenshot (a desktop capture of the GL window comes out black)
        $cap="$game\captures"; $before=@(Get-ChildItem "$cap\F7_*.png" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $sc=[W]::MapVirtualKey(0x76,0); [W]::PostMessage($h,0x100,[IntPtr]0x76,[IntPtr](1 -bor ($sc -shl 16))) | Out-Null
        Start-Sleep -Milliseconds 100; [W]::PostMessage($h,0x101,[IntPtr]0x76,[IntPtr]([int64]0xC0000001 -bor ($sc -shl 16))) | Out-Null
        $f="$out\$Tag`_$($Shots[$shotIdx])s.png"; $got=$null
        for($i=0;$i -lt 30 -and -not $got;$i++){ Start-Sleep -Milliseconds 100
          $got=Get-ChildItem "$cap\F7_*.png" -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.FullName } | Select-Object -First 1 }
        if($got){ Start-Sleep -Milliseconds 300; Move-Item $got.FullName $f -Force; Write-Output "shot $f" } else { Write-Output "no F7 shot at $([int]$el)s" }
      }
      else { Write-Output "no hwnd at $([int]$el)s" }
      $shotIdx++
    }
  }
} finally {
  if (-not $p.HasExited) {
    $p.Refresh()
    $h = $p.MainWindowHandle
    if ($h -ne [IntPtr]::Zero -and [W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) -and $p.WaitForExit(5000)) {
      Write-Output "test closed with exit code $($p.ExitCode)"
    } elseif (-not $p.HasExited) {
      $p.Kill()
      $p.WaitForExit()
      Write-Output "test process stopped after it did not close normally"
    }
  }
}
