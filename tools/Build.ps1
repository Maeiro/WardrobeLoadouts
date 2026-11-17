param([string]$ViewpointApiJar, [string]$JdkDir)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceMod = Join-Path $projectRoot "content\mods\WardrobeLoadouts"
$packageRoot = Join-Path $projectRoot "dist\WardrobeLoadouts"
$packageMod = Join-Path $packageRoot "Contents\mods\WardrobeLoadouts"
$packageArchive = Join-Path $projectRoot "dist\WardrobeLoadouts.zip"

if (-not (Test-Path -LiteralPath (Join-Path $sourceMod "mod.info"))) {
    throw "The mod source is missing mod.info: $sourceMod"
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceMod "42\mod.info"))) {
    throw "The Build 42 mod source is missing 42\mod.info: $sourceMod"
}

& (Join-Path $PSScriptRoot "BuildCursor.ps1") -ViewpointApiJar $ViewpointApiJar -JdkDir $JdkDir

New-Item -ItemType Directory -Path $packageMod -Force | Out-Null
Copy-Item -Path (Join-Path $sourceMod "*") -Destination $packageMod -Recurse -Force
Compress-Archive -Path $packageRoot -DestinationPath $packageArchive -Force
Write-Output "Packaged Wardrobe Loadouts at $packageMod"
Write-Output "Created install archive at $packageArchive"
