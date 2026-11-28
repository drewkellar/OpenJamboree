param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$Checkpoint,
    [string]$RuntimeDir = (Join-Path $PSScriptRoot 'playthrough'),
    [switch]$ShareBinaries
)
$ErrorActionPreference = 'Stop'
$source = Join-Path (Join-Path $PSScriptRoot 'checkpoints') $Checkpoint
$metadata = Get-Content -LiteralPath (Join-Path $source 'meta.json') -Raw | ConvertFrom-Json
$runtime = (Resolve-Path -LiteralPath $RuntimeDir).Path
$saveNames = @('bqSaveData', 'bqSaveData2')
foreach ($file in $saveNames) {
    $path = Join-Path $source $file
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $metadata.sha256.$file) {
        throw "Checkpoint checksum failed for $file"
    }
}
$config = Get-Content -LiteralPath (Join-Path $runtime 'Recomp.ini')
$dumpSetting = @($config | Where-Object { $_ -match '^\s*game_dump\s*=' })
if ($dumpSetting.Count -ne 1) { throw 'The selected runtime must have one game_dump setting' }
$dumpPath = ($dumpSetting[0] -split '=', 2)[1].Trim()
if (-not [IO.Path]::IsPathRooted($dumpPath)) {
    $dumpPath = (Resolve-Path -LiteralPath (Join-Path $runtime $dumpPath)).Path
}
$config = $config | ForEach-Object { if ($_ -match '^\s*game_dump\s*=') { "game_dump=$dumpPath" } else { $_ } }

$runs = Join-Path $PSScriptRoot 'runs'
$leaf = "$Checkpoint-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
$target = Join-Path $runs $leaf
if (Test-Path -LiteralPath $target) { throw "Replay folder already exists at $target" }
$targetSave = Join-Path $target 'Recomp_data/save/user'
New-Item -ItemType Directory -Path $targetSave -Force | Out-Null
foreach ($file in @('Recomp.exe', 'Recomp_code.dll', 'Recomp.hints')) {
    $path = Join-Path $runtime $file
    if ($file -eq 'Recomp.hints' -and -not (Test-Path -LiteralPath $path)) { continue }
    $destination = Join-Path $target $file
    if ($ShareBinaries -and $file -ne 'Recomp.hints') {
        New-Item -ItemType HardLink -Path $destination -Target $path | Out-Null
    } else {
        Copy-Item -LiteralPath $path -Destination $destination
    }
}
$config | Set-Content -LiteralPath (Join-Path $target 'Recomp.ini') -Encoding UTF8
foreach ($file in $saveNames) {
    Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $targetSave $file)
}
Write-Output $target
