# Run with Windows PowerShell 5.1; no network, real browser or user profile is used.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\src\update.ps1"
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }

$temp = Join-Path ([IO.Path]::GetTempPath()) ('brave-runtime-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    # Validate native argument round trips, not the text of our quoting helper.
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeArguments {
    [DllImport("shell32.dll", SetLastError=true)]
    public static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string command, out int count);
    [DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr memory);
}
'@
    $values = @('', 'C:\folder with spaces\', 'https://example.test/?a=1&b=%22x%22', 'a"b', 'a\"b', "apostrophe's ! path")
    foreach ($value in $values) {
        $count = 0
        $pointer = [NativeArguments]::CommandLineToArgvW(('browser.exe ' + (ConvertTo-WindowsArgument $value)), [ref]$count)
        try {
            Assert ($count -eq 2) 'Argument split or lost.'
            $actual = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::ReadIntPtr($pointer, [IntPtr]::Size))
            Assert ($actual -ceq $value) "Argument changed: $value"
        } finally { [void][NativeArguments]::LocalFree($pointer) }
    }
    $unsigned = Join-Path $temp 'unsigned.exe'
    [IO.File]::WriteAllText($unsigned, 'not signed')
    $rejected = $false
    try { Assert-BraveSignature $unsigned } catch { $rejected = $true }
    Assert $rejected 'Unsigned executables must be rejected.'

    $lock = Open-BraveMaintenanceLock $temp
    try {
        $second = $null
        $rejected = $false
        try { $second = Open-BraveMaintenanceLock $temp } catch { $rejected = $true }
        finally { if ($second) { $second.Dispose() } }
        Assert $rejected 'Concurrent maintenance was allowed.'
    } finally { $lock.Dispose() }

    $payload = Join-Path $temp 'payload'
    New-Item -ItemType Directory -Path $payload | Out-Null
    [IO.File]::WriteAllText((Join-Path $payload 'brave.exe'), '1.0.1')
    [IO.File]::WriteAllText((Join-Path $payload 'resource.pak'), 'new resources')
    $script:Archive = Join-Path $temp 'release.zip'
    Compress-Archive -Path "$payload\*" -DestinationPath $script:Archive
    $hash = (Get-FileHash -LiteralPath $script:Archive -Algorithm SHA256).Hash
    $script:Release = [pscustomobject]@{
        tag_name = 'v1.0.1'; draft = $false; prerelease = $false
        assets = @([pscustomobject]@{
            name = 'brave-origin-v1.0.1-win32-x64.zip'
            browser_download_url = 'https://github.com/brave/brave-browser/releases/download/v1.0.1/brave-origin-v1.0.1-win32-x64.zip'
            digest = "sha256:$hash"
        })
    }
    # Replace only external service/OS observations. Hashing, extraction and replacement are real.
    function Invoke-RestMethod { if ($script:Fault -eq 'network') { throw 'offline' }; return $script:Release }
    function Save-BraveArchive { param($Url, $Path); Copy-Item -LiteralPath $script:Archive -Destination $Path }
    function Get-BraveVersion { param($Path); return [IO.File]::ReadAllText($Path) }
    function Assert-BraveSignature {
        param($Path)
        if ($script:Fault -eq 'signature' -and $Path -like '*\new\brave.exe') { throw 'bad signature' }
    }
    function Test-BraveRunning {
        if ($script:Fault -eq 'running') { return $true }
        if ($script:Fault -eq 'swap') {
            # Simulate a filesystem failure after validation; the real rename must roll back.
            Get-ChildItem -LiteralPath $script:Install -Directory -Filter '.update-*' | ForEach-Object {
                $candidate = Join-Path $_.FullName 'new'
                if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force }
            }
        }
        return $false
    }
    foreach ($fault in @('network', 'hash', 'signature', 'swap', 'running', 'check', 'success')) {
        $script:Fault = $fault
        $script:Install = Join-Path $temp $fault
        $bin = Join-Path $script:Install 'bin'
        New-Item -ItemType Directory -Path $bin | Out-Null
        [IO.File]::WriteAllText((Join-Path $bin 'brave.exe'), '1.0.0')
        [IO.File]::WriteAllText((Join-Path $bin 'old.pak'), 'old resources')
        $data = Join-Path $script:Install 'data'
        New-Item -ItemType Directory -Path $data | Out-Null
        [IO.File]::WriteAllText((Join-Path $data 'Local State'), '{"keep":"profile"}')
        $script:Release.assets[0].digest = if ($fault -eq 'hash') { 'sha256:' + ('0' * 64) } else { "sha256:$hash" }
        $failed = $false
        try { Update-Brave -RootDir $script:Install -CheckOnly:($fault -eq 'check') } catch { $failed = $true }
        Assert ($failed -eq ($fault -notin @('success', 'check'))) "Unexpected outcome: $fault"
        $expected = if ($fault -eq 'success') { '1.0.1' } else { '1.0.0' }
        Assert ([IO.File]::ReadAllText((Join-Path $bin 'brave.exe')) -eq $expected) "Installed browser damaged: $fault"
        Assert ([IO.File]::ReadAllText((Join-Path $data 'Local State')) -ceq '{"keep":"profile"}') "Profile changed: $fault"
        Assert ((Test-Path -LiteralPath (Join-Path $bin 'old.pak')) -eq ($fault -ne 'success')) "Mixed browser versions: $fault"
    }
    Write-Host 'PASS: native quoting, unsigned rejection, locking, update failure preservation, rollback, check-only and replacement.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
