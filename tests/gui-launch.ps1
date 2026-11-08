# Exercise the real WSH/PowerShell failure path without downloading or starting a browser.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\src\runtime.ps1"
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DialogButton {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
'@
$desktop = [Windows.Automation.AutomationElement]::RootElement
$scope = [Windows.Automation.TreeScope]::Children
$all = [Windows.Automation.Condition]::TrueCondition
function Get-VisibleConsoles {
    @($desktop.FindAll($scope, $all) | Where-Object {
        -not $_.Current.IsOffscreen -and $_.Current.ClassName -in @('ConsoleWindowClass', 'CASCADIA_HOSTING_WINDOW_CLASS')
    } | ForEach-Object { $_.Current.NativeWindowHandle })
}
$baseline = @(Get-VisibleConsoles)
$temp = Join-Path ([IO.Path]::GetTempPath()) ("brave GUI ' ! [path] " + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$process = $null
try {
    $root = Split-Path -Parent $PSScriptRoot
    Copy-Item -LiteralPath (Join-Path $root 'Launch.vbs'), (Join-Path $root 'src') -Destination $temp -Recurse
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $env:SystemRoot 'System32\wscript.exe'
    # An option masquerading as a URL must be rejected before any update/profile access.
    $start.Arguments = '//nologo ' + (ConvertTo-WindowsArgument (Join-Path $temp 'Launch.vbs')) + ' --invalid-browser-option'
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    $condition = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $dialog = $null
    $newConsole = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if (@(Get-VisibleConsoles | Where-Object { $_ -notin $baseline }).Count) { $newConsole = $true }
        $dialog = $desktop.FindFirst($scope, $condition)
        if ($dialog) { break }
        if ($process.HasExited) { break }
        Start-Sleep -Milliseconds 20
    }
    if (-not $dialog) { throw 'Launch failure did not produce a visible error dialog.' }
    $text = ($dialog.FindAll([Windows.Automation.TreeScope]::Descendants, $all) | ForEach-Object { $_.Current.Name }) -join ' '
    $button = $dialog.FindAll([Windows.Automation.TreeScope]::Descendants, $all) |
        Where-Object { $_.Current.Name -eq 'OK' } | Select-Object -First 1
    if (-not $button) { throw "Error dialog has no acknowledgement button: $text" }
    [void][DialogButton]::PostMessage([IntPtr]$button.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    if ($newConsole) { throw 'Launching through WSH displayed a new console window.' }
    if ($text -notmatch 'could not start \(exit 1\)') { throw "Unexpected error dialog: $text" }
    if (-not $process.WaitForExit(5000)) { throw 'Launcher did not exit after dismissing its error.' }
    if ($process.ExitCode -ne 1) { throw "Failure exit code was not preserved: $($process.ExitCode)" }
    Write-Host 'PASS: hidden PowerShell launch, visible failure dialog and nonzero exit; no browser/profile accessed.'
} finally {
    if ($process) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
    Remove-Item -LiteralPath $temp -Recurse -Force
}
