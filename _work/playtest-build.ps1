# SwitchRecomp - Copyright 2026 MZ Labs
# Licensed under the GNU Affero General Public License v3.0, see LICENSE.txt and NOTICE.txt.
# Forks and derived works have to keep the credit to SwitchRecomp by MZ Labs and the startup screen.
[CmdletBinding()]
param(
    [string]$GameDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'games'),
    [switch]$ApplyPending
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$game = (Resolve-Path -LiteralPath $GameDir).Path
$runtime = (Resolve-Path -LiteralPath (Join-Path $game 'Recomp.exe')).Path
$state = Join-Path $game '.playtest'
$pending = Join-Path $state 'Recomp.pending.exe'
$rollback = Join-Path $state 'Recomp.rollback.exe'
New-Item -ItemType Directory -Path $state -Force | Out-Null

function Test-RuntimeRunning {
    Get-Process -Name Recomp -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $runtime } | Select-Object -First 1
}

# Keep the candidate, pending build, and rollback on the game's volume. The lock
# prevents another invocation from replacing the pending build during installation.
$lock = [IO.File]::Open((Join-Path $state 'update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$candidate = $null
try {
    if (!$ApplyPending) {
        $candidate = Join-Path $state ([guid]::NewGuid().ToString() + '.exe')
        & (Join-Path $root 'python/python.exe') (Join-Path $PSScriptRoot 'build.py') $candidate
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw 'Runtime build failed. The installed runtime and any pending update are intact.'
        }
        if ([IO.File]::Exists($pending)) {
            [IO.File]::Replace($candidate, $pending, [NullString]::Value)
        } else {
            [IO.File]::Move($candidate, $pending)
        }
    }
    if (![IO.File]::Exists($pending)) {
        Write-Output 'There is no pending playtest runtime.'
        return
    }
    if (Test-RuntimeRunning) {
        Write-Output 'Recomp is running. The update is staged. Close the game and rerun with -ApplyPending.'
        return
    }
    try {
        [IO.File]::Replace($pending, $runtime, $rollback)
    } catch {
        $code = $_.Exception.GetBaseException().HResult -band 0xffff
        if ($code -in 32,33 -or (Test-RuntimeRunning)) {
            Write-Output 'Recomp.exe is in use. The update is staged. Rerun with -ApplyPending when it is available.'
            return
        }
        throw
    }
    Write-Output "Updated $runtime"
    Write-Output "Rollback runtime: $rollback"
} finally {
    if ($candidate -and [IO.File]::Exists($candidate)) {
        Remove-Item -LiteralPath $candidate -ErrorAction Continue
    }
    $lock.Dispose()
}
