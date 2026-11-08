# Register the shared launcher; Windows Settings still controls the user's defaults.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\src\runtime.ps1"

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $AppDir "bin"
$Launcher = Join-Path $AppDir 'Launch.vbs'
$OriginExe = Join-Path $BinDir "brave.exe"
$AppName = "BraveOriginFree"
$Command = (ConvertTo-WindowsArgument (Join-Path $env:SystemRoot 'System32\wscript.exe')) +
    ' //nologo ' + (ConvertTo-WindowsArgument $Launcher)

if (-not (Test-Path $OriginExe)) {
    Write-Host "[!] Brave Origin not found. Run install.bat first." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Set Brave Origin as Default Browser" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will register Brave Origin as handler for:" -ForegroundColor Gray
Write-Host "  - HTTP and HTTPS protocols" -ForegroundColor Gray
Write-Host "  - .html, .htm files" -ForegroundColor Gray
Write-Host ""
Write-Host "[~] Registering..." -ForegroundColor Yellow

# Create ProgID
$progId = "BraveOriginFreeHTML"
$regPath = "HKCU:\Software\Classes\$progId"
New-Item -Path $regPath -Force | Out-Null
New-ItemProperty -Path $regPath -Name "(Default)" -Value "Brave Origin Free" -PropertyType String -Force | Out-Null
New-Item -Path "$regPath\DefaultIcon" -Force | Out-Null
New-ItemProperty -Path "$regPath\DefaultIcon" -Name "(Default)" -Value "`"$OriginExe`",0" -PropertyType String -Force | Out-Null
New-Item -Path "$regPath\shell\open\command" -Force | Out-Null
New-ItemProperty -Path "$regPath\shell\open\command" -Name "(Default)" -Value "$Command `"%1`"" -PropertyType String -Force | Out-Null


# Register in RegisteredApplications
$regApps = "HKCU:\Software\RegisteredApplications"
New-Item -Path $regApps -Force | Out-Null
New-ItemProperty -Path $regApps -Name $AppName -Value "Software\Clients\StartMenuInternet\$AppName\Capabilities" -PropertyType String -Force | Out-Null

# Capabilities
$caps = "HKCU:\Software\Clients\StartMenuInternet\$AppName\Capabilities"
New-Item -Path $caps -Force | Out-Null
New-ItemProperty -Path $caps -Name "ApplicationDescription" -Value "Brave Origin - Free for Windows" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $caps -Name "ApplicationName" -Value "Brave Origin Free" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $caps -Name "ApplicationIcon" -Value "`"$OriginExe`",0" -PropertyType String -Force | Out-Null

New-Item -Path "$caps\URLAssociations" -Force | Out-Null
New-ItemProperty -Path "$caps\URLAssociations" -Name "http" -Value $progId -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$caps\URLAssociations" -Name "https" -Value $progId -PropertyType String -Force | Out-Null

New-Item -Path "$caps\FileAssociations" -Force | Out-Null
New-ItemProperty -Path "$caps\FileAssociations" -Name ".html" -Value $progId -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$caps\FileAssociations" -Name ".htm" -Value $progId -PropertyType String -Force | Out-Null

# Register app
$appReg = "HKCU:\Software\Clients\StartMenuInternet\$AppName"
New-Item -Path $appReg -Force | Out-Null
New-ItemProperty -Path $appReg -Name "(Default)" -Value "Brave Origin Free" -PropertyType String -Force | Out-Null
New-Item -Path "$appReg\DefaultIcon" -Force | Out-Null
New-ItemProperty -Path "$appReg\DefaultIcon" -Name "(Default)" -Value "`"$OriginExe`",0" -PropertyType String -Force | Out-Null
New-Item -Path "$appReg\shell\open\command" -Force | Out-Null
New-ItemProperty -Path "$appReg\shell\open\command" -Name "(Default)" -Value $Command -PropertyType String -Force | Out-Null

Write-Host "[O] Registration complete. Now choose Brave Origin Free in Windows Settings > Apps > Default apps." -ForegroundColor Green
Write-Host "Moving this folder requires running MakeDefault.bat again." -ForegroundColor Yellow
Read-Host "Press Enter to exit"
