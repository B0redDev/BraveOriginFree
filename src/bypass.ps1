# BraveOriginFree - Source files
#
# Writes the activation keys into a Brave profile's "Local State" file.
#   bypass.ps1 [-ProfilePath <dir>]           apply (refuses while Brave is running)
#   bypass.ps1 [-ProfilePath <dir>] -Status   read-only; exit 0 only if the keys are present
# Exit codes: 0 success, 1 not activated (-Status) or any error. Errors never modify an existing file.
#

param(
    [string]$ProfilePath,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\runtime.ps1"

$SkusKey = '67'
$SkusValue = '{"credentials":{"items":{"6":"7"}}}'
$JsonDepth = 100

function Set-Prop($Object, [string]$Name, $Value) {
    Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Test-JsonObject($Value) {
    # -is [pscustomobject] is also true for strings/numbers, so compare the exact type.
    return ($null -ne $Value) -and ($Value.GetType() -eq [Management.Automation.PSCustomObject])
}

# Returns the existing child object, or creates an empty one. Any other existing type is an error.
function Get-ChildObject($Parent, [string]$Name, [string]$Path) {
    $prop = $Parent.PSObject.Properties[$Name]
    if (-not $prop) {
        $child = [pscustomobject]@{}
        Set-Prop $Parent $Name $child
        return $child
    }
    if (-not (Test-JsonObject $prop.Value)) {
        throw "Unexpected JSON type at '$Path' in Local State (expected an object); refusing to modify."
    }
    return $prop.Value
}

# Sets a leaf value; returns $true when something changed.
function Set-Leaf($Parent, [string]$Name, $Value) {
    $prop = $Parent.PSObject.Properties[$Name]
    if ($prop -and $prop.Value -ceq $Value -and $prop.Value.GetType() -eq $Value.GetType()) { return $false }
    Set-Prop $Parent $Name $Value
    return $true
}

function Read-LocalState([string]$Path) {
    $text = [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false, $true)))
    try {
        $state = ConvertFrom-Json -InputObject $text
    } catch {
        throw "Local State is not valid JSON: $($_.Exception.Message)"
    }
    if (-not (Test-JsonObject $state)) { throw "Local State top level is not a JSON object; refusing to modify." }
    return $state
}

function Test-Activated($State) {
    return ($State.brave.origin.purchase_validated -eq $true) -and ($State.skus.state.$SkusKey -ceq $SkusValue)
}

function Invoke-Main {
    Write-Host "BraveOriginFree - Standalone Patcher" -ForegroundColor Cyan
    Write-Host ""

    $detectedPaths = @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Origin\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Origin-Beta\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Origin-Nightly\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Beta\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Nightly\User Data"
    )

    # An explicit -ProfilePath without Local State is a new profile; auto-detect only finds existing ones.
    $dir = $ProfilePath
    if (-not $dir) {
        foreach ($p in $detectedPaths) {
            if (Test-Path -LiteralPath (Join-Path $p "Local State") -PathType Leaf) { $dir = $p; break }
        }
    }
    if (-not $dir) {
        Write-Host "Could not find a Brave profile." -ForegroundColor Yellow
        Write-Host "Usage:" -ForegroundColor Gray
        Write-Host "  .\src\bypass.ps1                          # Auto-detect"
        Write-Host "  .\src\bypass.ps1 -Status                   # Check status"
        Write-Host "  .\src\bypass.ps1 -ProfilePath `"C:\path\`" # Manual path"
        Write-Host ""
        return 1
    }

    $dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($dir)
    $localState = Join-Path $dir "Local State"
    $exists = Test-Path -LiteralPath $localState -PathType Leaf
    if (-not $exists -and (Test-Path -LiteralPath $localState)) { throw "'$localState' exists but is not a file." }

    if ($Status) {
        if (-not $exists) { throw "Local State not found: $localState" }
        if (Test-Activated (Read-LocalState $localState)) {
            Write-Host "Status: ACTIVATED (activation keys present in Local State)" -ForegroundColor Green
            return 0
        }
        Write-Host "Status: NOT ACTIVATED" -ForegroundColor Red
        return 1
    }

    Write-Host "Profile: $dir" -ForegroundColor Gray

    if (Test-BraveRunning) {
        throw "Brave is running. Close Brave completely and retry; nothing was changed."
    }

    [void](New-Item -ItemType Directory -Path $dir -Force)

    $lock = $null
    $tmp = Join-Path $dir ("Local State." + [guid]::NewGuid().ToString('N') + ".tmp")
    try {
        try {
            $lock = New-Object IO.FileStream((Join-Path $dir "Local State.bypass.lock"), [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
        } catch {
            throw "Could not lock the profile (another BraveOriginFree process may be modifying it): $($_.Exception.Message)"
        }
        $exists = Test-Path -LiteralPath $localState -PathType Leaf

        Write-Host "Applying activation..." -ForegroundColor Yellow

        if ($exists) { $state = Read-LocalState $localState } else { $state = [pscustomobject]@{} }

        $brave = Get-ChildObject $state 'brave' 'brave'
        $origin = Get-ChildObject $brave 'origin' 'brave.origin'
        $changed = Set-Leaf $origin 'purchase_validated' $true
        $skus = Get-ChildObject $state 'skus' 'skus'
        $skusState = Get-ChildObject $skus 'state' 'skus.state'
        if (Set-Leaf $skusState $SkusKey $SkusValue) { $changed = $true }

        if ($exists -and -not $changed) {
            Write-Host "Already configured; Local State left untouched." -ForegroundColor Green
            return 0
        }

        # Truncation beyond -Depth only emits a warning; promote it to an error so we never write cut-off data.
        $json = ConvertTo-Json -InputObject $state -Depth $JsonDepth -Compress -WarningAction Stop
        [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))

        if ($exists) {
            [IO.File]::Replace($tmp, $localState, (Join-Path $dir "Local State.braveoriginfree.bak"))
        } else {
            [IO.File]::Move($tmp, $localState)
        }
        Write-Host "Activation keys written to Local State." -ForegroundColor Green
        Write-Host "This only changes the profile config; the script does not verify Brave's behavior." -ForegroundColor Cyan
        return 0
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        if ($lock) { $lock.Dispose() }
    }
}

try {
    $code = Invoke-Main
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $code = 1
}
exit $code
