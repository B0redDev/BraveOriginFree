# Shared Windows PowerShell 5.1 helpers. No side effects when dot-sourced.
function Open-BraveMaintenanceLock {
    param([string]$RootDir)
    try {
        return [IO.File]::Open((Join-Path $RootDir '.maintenance.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch {
        throw "Cannot lock this installation. Another launcher/update may be active, or the folder is not writable: $_"
    }
}

function Test-BraveRunning {
    # ponytail: conservatively defer maintenance for any Brave process; narrow by profile if needed.
    return @((Get-Process -Name brave -ErrorAction SilentlyContinue)).Count -gt 0
}

function Assert-BraveSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'Brave Software, Inc.') {
        throw "Invalid or unexpected Brave Authenticode signature: $Path"
    }
}

function Get-BraveVersion {
    param([string]$Path)
    $productVersion = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo.ProductVersion
    # Windows builds may prefix Brave's version with the Chromium major version.
    if ($productVersion -notmatch '^(?:\d+\.)?(\d+\.\d+\.\d+)$') {
        throw "Unrecognized Brave product version: $productVersion"
    }
    return $Matches[1]
}

function ConvertTo-WindowsArgument {
    param([AllowEmptyString()][string]$Value)
    # CommandLineToArgvW/CRT quoting: escape quotes and backslashes before quotes/end.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
