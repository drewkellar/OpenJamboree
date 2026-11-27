[CmdletBinding(DefaultParameterSetName='Replay')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Replay')]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*-[0-9]{8}-[0-9]{9}$')]
    [string[]]$Replay,
    [Parameter(Mandatory=$true, ParameterSetName='GameDir')]
    [string[]]$GameDir,
    [switch]$Binaries,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$work = Get-Item -LiteralPath $PSScriptRoot
$prefix = $work.FullName + [IO.Path]::DirectorySeparatorChar
if ($Replay) {
    $runs = Join-Path $PSScriptRoot 'save-library/runs'
    $GameDir = @($Replay | ForEach-Object { Join-Path $runs $_ })
}

function Get-ReplayArtifactFiles($Item, [bool]$IncludeBinaries) {
    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Replay artifact contains a link at $($Item.FullName)"
    }
    if ($Item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Item.FullName -Force) {
            Get-ReplayArtifactFiles $child $false
        }
    }
    elseif ($IncludeBinaries -or $Item.Extension -in '.png', '.ppm', '.bmp', '.bin', '.glsl', '.f32', '.mp4', '.wav') {
        $Item
    }
}

$running = @(Get-Process Recomp -ErrorAction SilentlyContinue | ForEach-Object { $_.Path })
$names = @('captures', 'shader_cache')
if ($Binaries) { $names += 'Recomp.exe', 'Recomp_code.dll' }
$artifacts = @(foreach ($path in $GameDir | Select-Object -Unique) {
    $run = Get-Item -LiteralPath $path
    if (-not $run.PSIsContainer -or -not $run.FullName.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Expected an isolated game directory inside $PSScriptRoot"
    }
    for ($dir = $run; $dir; $dir = $dir.Parent) {
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Replay path contains a link at $($dir.FullName)" }
        if ($dir.FullName -eq $work.FullName) { break }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $run.FullName 'Recomp.ini') -PathType Leaf)) {
        throw "Could not find a replay config in $($run.FullName)"
    }
    if ((Join-Path $run.FullName 'Recomp.exe') -in $running) {
        throw "Replay $($run.FullName) is still running"
    }
    foreach ($leaf in $names) {
        $path = Join-Path $run.FullName $leaf
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -ne ($leaf -in 'captures', 'shader_cache')) {
            throw "Unexpected artifact type at $path"
        }
        $files = @(Get-ReplayArtifactFiles $item ($leaf -in 'Recomp.exe', 'Recomp_code.dll'))
        [pscustomobject]@{ Path = $item.FullName; Files = $files; Bytes = ($files | Measure-Object -Property Length -Sum).Sum }
    }
})

foreach ($artifact in $artifacts) {
    Write-Output ('{0} files, {1} bytes  {2}' -f $artifact.Files.Count, $artifact.Bytes, $artifact.Path)
    if ($Apply -and $artifact.Files.Count) {
        Remove-Item -LiteralPath @($artifact.Files.FullName) -Force
    }
}
$total = ($artifacts | Measure-Object -Property Bytes -Sum).Sum
if ($Apply) { Write-Output "Removed $total bytes of generated files." }
else { Write-Output "Preview: $total bytes of generated files. Use -Apply to remove them." }
