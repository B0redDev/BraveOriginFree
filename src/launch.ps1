param([string]$Target, [switch]$Gui)

. "$PSScriptRoot\update.ps1"

function Start-Brave {
    param([string]$RootDir, [string]$Target, [switch]$Gui)
    $ErrorActionPreference = 'Stop'
    if ($Target -and ($Target.StartsWith('-') -or $Target.Contains([char]0))) {
        throw 'Expected a URL or file path, not a browser option.'
    }
    $lock = Open-BraveMaintenanceLock $RootDir
    try {
        $exe = Join-Path $RootDir 'bin\brave.exe'
        $data = Join-Path $RootDir 'data'
        if (-not (Test-BraveRunning)) {
            try { Update-Brave -RootDir $RootDir }
            catch {
                if (-not (Test-Path -LiteralPath $exe)) { throw }
                $message = "Update failed; using the installed browser. Retry src\update.ps1 before browsing untrusted sites. $_"
                if ($Gui) {
                    [void](New-Object -ComObject WScript.Shell).Popup($message, 0, 'Brave Origin Free - update', 48)
                } else {
                    Write-Warning $message
                }
            }
            Assert-BraveSignature $exe
            & "$PSScriptRoot\bypass.ps1" -ProfilePath $data
            if ($LASTEXITCODE -ne 0) { throw 'Profile configuration failed; browser not started.' }
        } else {
            # Never rewrite live profile state or replace files used by a running browser.
            Assert-BraveSignature $exe
            if (-not (Test-Path -LiteralPath (Join-Path $data 'Local State'))) {
                throw 'Close all Brave processes before initializing this profile.'
            }
        }
        $arguments = @(
            "--user-data-dir=$data"
            '--no-first-run'
            '--no-default-browser-check'
            '--disable-brave-rewards'
            '--disable-brave-wallet'
            '--disable-brave-leo-ai'
            '--disable-brave-news'
            '--disable-brave-talk'
            '--disable-brave-vpn'
            '--disable-brave-tor'
            '--disable-sync'
            '--disable-features=BraveRewards,BraveWallet,BraveLeoAI,BraveNews,BraveTalk,BraveVPN,BraveTor,BraveP3A,BraveAds,Playlist,CryptoWallets,NativeBraveWallet,BraveNTPBrandedWallpaper,BraveTogether,BraveSpeedreader'
        )
        if ($Target) { $arguments += $Target }
        $commandLine = ($arguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $exe
        $start.Arguments = $commandLine
        $start.WorkingDirectory = $RootDir
        $start.UseShellExecute = $false
        $process = [Diagnostics.Process]::Start($start)
        $process.Dispose()
    } finally {
        $lock.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Start-Brave -RootDir (Split-Path -Parent $PSScriptRoot) -Target $Target -Gui:$Gui
        exit 0
    } catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    }
}
