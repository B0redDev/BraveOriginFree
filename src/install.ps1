# Install/update the portable browser and create a per-user desktop shortcut.
. "$PSScriptRoot\update.ps1"
$ErrorActionPreference = 'Stop'
$lock = $null
try {
    $root = Split-Path -Parent $PSScriptRoot
    $lock = Open-BraveMaintenanceLock $root
    Update-Brave -RootDir $root
    & "$PSScriptRoot\bypass.ps1" -ProfilePath (Join-Path $root 'data')
    if ($LASTEXITCODE -ne 0) { throw 'Profile configuration failed.' }

    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $desktop 'Brave Origin (Free).lnk'))
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $shortcut.Arguments = '//nologo ' + (ConvertTo-WindowsArgument (Join-Path $root 'Launch.vbs'))
    $shortcut.IconLocation = (Join-Path $root 'bin\brave.exe') + ',0'
    $shortcut.WorkingDirectory = $root
    $shortcut.Description = 'Brave Origin Free'
    $shortcut.Save()
    Write-Host 'Installation complete. Desktop shortcut created; use Launch.vbs to start without a console.'
    exit 0
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($lock) { $lock.Dispose() }
}
