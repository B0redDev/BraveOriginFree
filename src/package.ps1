# Builds BraveOriginFree-vX.Y.Z.zip from the repo root and verifies its contents.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File src\package.ps1 [-Version X.Y.Z] [-OutDir path]
# Writes the zip path to the output stream; exits 1 on any failure.
param(
    [string]$Version,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
. "$PSScriptRoot\runtime.ps1"

# Entrypoints that must be present before and inside the archive.
$RequiredFiles = @(
    'Launch.vbs', 'install.bat', 'MakeDefault.bat', 'make-default.ps1',
    'README.md', 'LICENSE', 'bin/brave.exe',
    'src/launch.ps1', 'src/update.ps1', 'src/install.ps1', 'src/bypass.ps1', 'src/runtime.ps1'
)
$TopFiles = @('Launch.vbs', 'install.bat', 'MakeDefault.bat', 'make-default.ps1', 'README.md', 'LICENSE')
$TopDirs = @('src', 'bin')

$tmp = $null
try {
    foreach ($f in $RequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $f) -PathType Leaf)) { throw "Missing required file: $f" }
    }

    if (-not $Version) {
        $Version = Get-BraveVersion (Join-Path $Root 'bin\brave.exe')
    }
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must be X.Y.Z, got '$Version'" }

    if (-not $OutDir) { $OutDir = Join-Path $Root 'dist' }
    $OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $zipPath = Join-Path $OutDir "BraveOriginFree-v$Version.zip"
    $tmp = "$zipPath.tmp"
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Collect (fullPath, entryName) pairs; never include the output being written.
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($f in $TopFiles) { $files.Add(@{ Path = Join-Path $Root $f; Name = $f }) }
    foreach ($d in $TopDirs) {
        $base = (Join-Path $Root $d)
        Get-ChildItem -LiteralPath $base -Recurse -File -Force | ForEach-Object {
            if ($_.FullName -ne $tmp -and $_.FullName -ne $zipPath) {
                $files.Add(@{ Path = $_.FullName; Name = $_.FullName.Substring($Root.Length + 1).Replace('\', '/') })
            }
        }
    }

    $zip = [System.IO.Compression.ZipFile]::Open($tmp, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $f.Path, $f.Name, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }

    # Verify the archive before publishing the final name.
    $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
    } finally { $zip.Dispose() }
    if ($names.Count -ne $files.Count) { throw "Archive has $($names.Count) entries, expected $($files.Count)" }
    foreach ($f in $RequiredFiles) {
        if ($names -cnotcontains $f) { throw "Archive is missing $f" }
    }
    if (@($names | Where-Object { $_ -like 'dist/*' -or $_.Contains('\') }).Count) {
        throw 'Archive contains unexpected entries (dist output or backslash paths)'
    }

    Move-Item -LiteralPath $tmp -Destination $zipPath -Force
    Write-Host "Packaged $($names.Count) files -> $zipPath"
    Write-Output $zipPath
} catch {
    if ($tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    [Console]::Error.WriteLine("package.ps1: $($_.Exception.Message)")
    exit 1
}
