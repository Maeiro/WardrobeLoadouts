param(
    [string]$ViewpointApiJar,
    [string]$JdkDir
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $JdkDir) {
    $localJdks = Join-Path $env:USERPROFILE "Documents\ChatGPT\PZ - Performance\build\jdk25"
    if (Test-Path -LiteralPath $localJdks) {
        $JdkDir = (Get-ChildItem -LiteralPath $localJdks -Directory | Select-Object -First 1).FullName
    } else {
        $JdkDir = $env:JAVA_HOME
    }
}
if (-not $JdkDir -or -not (Test-Path -LiteralPath (Join-Path $JdkDir "bin\javac.exe"))) {
    throw "Pass -JdkDir with a JDK 25 installation."
}
if (-not $ViewpointApiJar) {
    $ViewpointApiJar = "D:\SteamLibrary\steamapps\workshop\content\108600\3809306528\mods\Viewpoint\42\media\java\client\Viewpoint.jar"
}
$apiSource = (Resolve-Path -LiteralPath $ViewpointApiJar).Path
$buildFolder = Join-Path $projectRoot ("build\cursor\" + [Guid]::NewGuid().ToString("N"))
$classFolder = Join-Path $buildFolder "classes"
$apiReference = Join-Path $buildFolder "viewpoint-api.jar"
$outputJar = Join-Path $projectRoot "content\mods\WardrobeLoadouts\42\media\viewpoint\addons\maeiro.wardrobe-cursor\wardrobe-cursor.jar"
New-Item -ItemType Directory -Path $classFolder -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceArchive = [System.IO.Compression.ZipFile]::OpenRead($apiSource)
$referenceArchive = [System.IO.Compression.ZipFile]::Open($apiReference, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($entry in $sourceArchive.Entries) {
        if (-not $entry.FullName.StartsWith("viewpoint/api/") -or -not $entry.FullName.EndsWith(".class")) { continue }
        $copy = $referenceArchive.CreateEntry($entry.FullName)
        $inputStream = $entry.Open()
        $outputStream = $copy.Open()
        try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
    }
} finally {
    $referenceArchive.Dispose()
    $sourceArchive.Dispose()
}
$sources = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "src\main\java") -Filter *.java -Recurse -File)
& (Join-Path $JdkDir "bin\javac.exe") --release 17 -encoding UTF-8 -g:none -classpath $apiReference -d $classFolder @($sources.FullName)
if ($LASTEXITCODE -ne 0) { throw "Cursor addon compilation failed." }
& (Join-Path $JdkDir "bin\jar.exe") --create --file $outputJar --date=2026-01-01T00:00:00Z -C $classFolder .
if ($LASTEXITCODE -ne 0) { throw "Cursor addon packaging failed." }
$entries = & (Join-Path $JdkDir "bin\jar.exe") tf $outputJar
if ($entries | Where-Object { $_ -like "viewpoint/api/*" }) { throw "The addon must not bundle the Viewpoint API." }
Write-Output "Built cursor addon: $outputJar"
