# Verified installation/update; the profile is never changed here.
param(
    [switch]$CheckOnly,
    [ValidatePattern('^(latest|\d+\.\d+\.\d+)$')][string]$Version = 'latest'
)

. "$PSScriptRoot\runtime.ps1"

function Save-BraveArchive {
    param([string]$Url, [string]$Path)
    # PowerShell 5.1 Invoke-WebRequest -OutFile interprets brackets in paths as wildcards.
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.Timeout = 600000
    $request.ReadWriteTimeout = 600000
    $response = $null
    $file = $null
    try {
        $response = $request.GetResponse()
        $file = [IO.File]::Create($Path)
        $response.GetResponseStream().CopyTo($file)
    } finally {
        if ($file) { $file.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Update-Brave {
    param(
        [string]$RootDir,
        [switch]$CheckOnly,
        [ValidatePattern('^(latest|\d+\.\d+\.\d+)$')][string]$Version = 'latest'
    )
    # Caller holds the maintenance lock through any subsequent browser launch.
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $bin = Join-Path $RootDir 'bin'
    $exe = Join-Path $bin 'brave.exe'
    $current = $null
    if (Test-Path -LiteralPath $exe) {
        Assert-BraveSignature $exe
        $current = Get-BraveVersion $exe
    }
    if (-not $CheckOnly -and (Test-BraveRunning)) {
        throw 'Close all Brave windows/background processes before installing or updating.'
    }
    $headers = @{ 'User-Agent' = 'BraveOriginFree' }
    if ($env:GH_TOKEN) { $headers.Authorization = "Bearer $env:GH_TOKEN" }
    $endpoint = if ($Version -eq 'latest') { 'latest' } else { "tags/v$Version" }
    $release = Invoke-RestMethod "https://api.github.com/repos/brave/brave-browser/releases/$endpoint" -Headers $headers -TimeoutSec 15
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$') {
        throw 'GitHub did not return a stable Brave release.'
    }
    $latest = $Matches[1]
    if ($Version -ne 'latest' -and $Version -ne $latest) { throw 'Release version mismatch.' }
    Write-Host "Installed: $current; available: $latest"
    if ($current -and [version]$current -ge [version]$latest) {
        Write-Host 'Already up to date; downgrades are not performed.'
        return
    }
    $name = "brave-origin-v$latest-win32-x64.zip"
    $assets = @($release.assets | Where-Object { $_.name -eq $name })
    if ($assets.Count -ne 1) { throw "Release does not contain $name." }
    $asset = $assets[0]
    $url = "https://github.com/brave/brave-browser/releases/download/v$latest/$name"
    if ($asset.browser_download_url -cne $url -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
        throw 'Missing SHA256 digest or unexpected download URL; refusing an unverified download.'
    }
    $expectedHash = $Matches[1]
    if ($CheckOnly) { Write-Host "Update available: $latest"; return }

    $stage = Join-Path $RootDir ('.update-' + [guid]::NewGuid())
    $archive = Join-Path $stage 'browser.zip'
    $candidate = Join-Path $stage 'new'
    $backup = Join-Path $stage 'previous'
    $keepRecovery = $false
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        Write-Host "Downloading and verifying Brave Origin $latest..."
        Save-BraveArchive -Url $url -Path $archive
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'Archive SHA256 mismatch. The installed browser has not been changed.'
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $candidate
        $candidateExe = Join-Path $candidate 'brave.exe'
        Assert-BraveSignature $candidateExe
        if ((Get-BraveVersion $candidateExe) -ne $latest) { throw 'Downloaded browser version mismatch.' }
        if (Test-BraveRunning) { throw 'Brave started during download; close it and retry.' }

        $movedOld = $false
        try {
            if (Test-Path -LiteralPath $bin) {
                [IO.Directory]::Move($bin, $backup)
                $movedOld = $true
            }
            [IO.Directory]::Move($candidate, $bin)
        } catch {
            if ($movedOld) {
                try { [IO.Directory]::Move($backup, $bin) }
                catch {
                    $keepRecovery = $true
                    throw "Update rollback failed. Previous browser is preserved at ${backup}: $_"
                }
            }
            throw
        }
        Write-Host "Installed verified Brave Origin $latest."
    } finally {
        if (-not $keepRecovery) {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Continue
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $lock = $null
    try {
        $root = Split-Path -Parent $PSScriptRoot
        $lock = Open-BraveMaintenanceLock $root
        Update-Brave -RootDir $root -CheckOnly:$CheckOnly -Version $Version
        exit 0
    } catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    } finally {
        if ($lock) { $lock.Dispose() }
    }
}
