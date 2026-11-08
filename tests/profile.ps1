# Regression tests for src/bypass.ps1. Framework-free: runs the real script in child processes.
# Exit 0 = all passed, 1 = first failure (message printed).
$ErrorActionPreference = 'Stop'

$bypass = Join-Path $PSScriptRoot '..\src\bypass.ps1'
$psExe = (Get-Process -Id $PID).Path
$utf8 = New-Object Text.UTF8Encoding($false)
$root = Join-Path ([IO.Path]::GetTempPath()) ("braveoriginfree-profile-" + [guid]::NewGuid().ToString('N'))
$script:BraveRunning = $false
$skusExpected = '{"credentials":{"items":{"6":"7"}}}'
$n = 0

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# Runs bypass.ps1 in a child powershell; returns @{ Code; Output }.
function Invoke-Bypass([string[]]$ScriptArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # native stderr must not turn into exceptions while capturing
    try {
        $path = $ScriptArgs[1].Replace("'", "''")
        $status = if ($ScriptArgs -contains '-Status') { ' -Status' } else { '' }
        # Isolate the OS process observation, not profile parsing/writing or subprocess behavior.
        $running = if ($script:BraveRunning) { '$true' } else { '$false' }
        $command = "function Get-Process { param(`$Name, `$ErrorAction); if ($running) { [pscustomobject]@{ProcessName='brave'} } }; " +
            "& '" + $bypass.Replace("'", "''") + "' -ProfilePath '$path'$status; exit `$LASTEXITCODE"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $out = & $psExe -NoProfile -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $encoded 2>&1 | Out-String
        return @{ Code = $LASTEXITCODE; Output = $out }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function New-Profile($Json) {
    $script:n++
    $dir = Join-Path $root "p$script:n"
    [void](New-Item -ItemType Directory -Path $dir)
    if ($null -ne $Json) { [IO.File]::WriteAllText((Join-Path $dir 'Local State'), $Json, $utf8) }
    return $dir
}

function Get-Bytes($Dir) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Dir 'Local State'))) }
function Get-Files($Dir) { return (@(Get-ChildItem -LiteralPath $Dir -Force | ForEach-Object { $_.Name } | Sort-Object) -join '|') }

# A failing run must exit 1, mention an error, and leave the original bytes and directory untouched.
function Assert-FailsUntouched([string]$Name, [string]$Json) {
    $dir = New-Profile $Json
    $before = Get-Bytes $dir
    $r = Invoke-Bypass @('-ProfilePath', $dir)
    Assert ($r.Code -eq 1) "${Name}: expected exit 1, got $($r.Code). $($r.Output)"
    Assert ($r.Output -match 'Error:') "${Name}: no error message. $($r.Output)"
    Assert ((Get-Bytes $dir) -eq $before) "${Name}: Local State bytes changed"
    Assert ((Get-Files $dir) -eq 'Local State') "${Name}: stray files: $(Get-Files $dir)"
    return $dir
}

try {
    [void](New-Item -ItemType Directory -Path $root)

    # --- Existing origin = {} (missing purchase_validated), unrelated nested data preserved ---
    $fixture = '{"browser":{"labs":["a@1","b@2"],"deep":{"x":{"list":[{"k":1},{"k":2}],"s":"h\u00e9llo <t> & ''q''"}}},' +
        '"empty":[],"num":1.5,"flag":false,"brave":{"origin":{},"other":"keep"},"skus":{"state":{"1":"keep"}}}'
    $dir = New-Profile $fixture
    $orig = Get-Bytes $dir
    $before = [IO.File]::ReadAllText((Join-Path $dir 'Local State')) | ConvertFrom-Json
    $beforeBrowser = ConvertTo-Json -InputObject $before.browser -Depth 100 -Compress

    $r = Invoke-Bypass @('-ProfilePath', $dir)
    Assert ($r.Code -eq 0) "existing origin={}: expected exit 0, got $($r.Code). $($r.Output)"
    $path = Join-Path $dir 'Local State'
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'output has a UTF-8 BOM'
    $text = $utf8.GetString($bytes)
    $after = $text | ConvertFrom-Json
    Assert ($after.brave.origin.purchase_validated -eq $true) 'purchase_validated not set'
    Assert ($after.skus.state.'67' -ceq $skusExpected) 'skus.state.67 not set'
    Assert ($after.brave.other -eq 'keep') 'brave.other lost'
    Assert ($after.skus.state.'1' -eq 'keep') 'skus.state.1 lost'
    Assert ((ConvertTo-Json -InputObject $after.browser -Depth 100 -Compress) -eq $beforeBrowser) 'nested browser data changed'
    Assert ($after.browser.deep.x.s -ceq "h$([char]0xe9)llo <t> & 'q'") 'unicode/special string changed'
    Assert ($text -match '"empty":\[\]') 'empty array not preserved'
    Assert ($after.num -eq 1.5 -and $after.flag -eq $false) 'scalars not preserved'
    $bak = Join-Path $dir 'Local State.braveoriginfree.bak'
    Assert ((Test-Path -LiteralPath $bak) -and ([Convert]::ToBase64String([IO.File]::ReadAllBytes($bak)) -eq $orig)) 'backup missing or differs from original'
    Assert ((Get-Files $dir) -eq 'Local State|Local State.braveoriginfree.bak') "unexpected files: $(Get-Files $dir)"

    # --- Status ---
    Assert ((Invoke-Bypass @('-ProfilePath', $dir, '-Status')).Code -eq 0) '-Status on activated profile should exit 0'

    # --- Repeat: idempotent, file untouched ---
    $done = Get-Bytes $dir
    $r = Invoke-Bypass @('-ProfilePath', $dir)
    Assert ($r.Code -eq 0) "repeat: expected exit 0, got $($r.Code). $($r.Output)"
    Assert ((Get-Bytes $dir) -eq $done) 'repeat run changed Local State'
    Assert ((Get-Files $dir) -eq 'Local State|Local State.braveoriginfree.bak') 'repeat run left stray files'

    # --- Status is read-only and exits 1 when not activated / on error ---
    $dir = New-Profile '{"brave":{"origin":{}}}'
    $before = Get-Bytes $dir
    Assert ((Invoke-Bypass @('-ProfilePath', $dir, '-Status')).Code -eq 1) '-Status on non-activated profile should exit 1'
    Assert ((Get-Bytes $dir) -eq $before -and (Get-Files $dir) -eq 'Local State') '-Status modified the profile'
    $dir = New-Profile $null
    Assert ((Invoke-Bypass @('-ProfilePath', $dir, '-Status')).Code -eq 1) '-Status with no Local State should exit 1'
    Assert ((Get-Files $dir) -eq '') '-Status created files'
    $dir = New-Profile '{broken'
    Assert ((Invoke-Bypass @('-ProfilePath', $dir, '-Status')).Code -eq 1) '-Status on malformed JSON should exit 1'

    # --- Other absent-key shapes ---
    foreach ($json in '{}', '{"brave":{}}', '{"skus":{}}', '{"brave":{"origin":{"purchase_validated":false,"x":1}}}') {
        $dir = New-Profile $json
        $r = Invoke-Bypass @('-ProfilePath', $dir)
        Assert ($r.Code -eq 0) "absent keys ($json): exit $($r.Code). $($r.Output)"
        Assert ((Invoke-Bypass @('-ProfilePath', $dir, '-Status')).Code -eq 0) "absent keys ($json): not activated after apply"
    }
    $dir = New-Profile '{"brave":{"origin":{"purchase_validated":false,"x":1}}}'
    [void](Invoke-Bypass @('-ProfilePath', $dir))
    Assert ((([IO.File]::ReadAllText((Join-Path $dir 'Local State'))) | ConvertFrom-Json).brave.origin.x -eq 1) 'sibling of purchase_validated lost'

    # --- New profile: absent Local State, absent directory ---
    $dir = Join-Path $root 'new\nested\User Data'
    $r = Invoke-Bypass @('-ProfilePath', $dir)
    Assert ($r.Code -eq 0) "new profile: exit $($r.Code). $($r.Output)"
    Assert ((Get-Files $dir) -eq 'Local State') "new profile: unexpected files: $(Get-Files $dir)"
    Assert ((Invoke-Bypass @('-ProfilePath', $dir, '-Status')).Code -eq 0) 'new profile not activated'
    $new = [IO.File]::ReadAllText((Join-Path $dir 'Local State')) | ConvertFrom-Json
    Assert ($new.brave.origin.purchase_validated -eq $true -and $new.skus.state.'67' -ceq $skusExpected) 'new profile content wrong'

    # --- Failures must retain exact bytes and leave no stray files ---
    [void](Assert-FailsUntouched 'malformed JSON' '{"brave": {"origin": ')
    [void](Assert-FailsUntouched 'truncated/garbage' "{`"a`":1} trailing")
    [void](Assert-FailsUntouched 'empty file' '')
    [void](Assert-FailsUntouched 'top-level array' '[1,2,3]')
    [void](Assert-FailsUntouched 'top-level scalar' '"text"')
    [void](Assert-FailsUntouched 'top-level null' 'null')
    [void](Assert-FailsUntouched 'brave is a string' '{"brave":"x","keep":1}')
    [void](Assert-FailsUntouched 'brave.origin is an array' '{"brave":{"origin":[1]}}')
    [void](Assert-FailsUntouched 'brave.origin is null' '{"brave":{"origin":null}}')
    [void](Assert-FailsUntouched 'skus is a number' '{"skus":5}')
    [void](Assert-FailsUntouched 'skus.state is a string' '{"skus":{"state":"s"}}')
    [void](Assert-FailsUntouched 'nesting deeper than 100' (('{"a":' * 105) + '1' + ('}' * 105)))

    # --- Brave running: refuse and do not modify ---
    $dir = New-Profile '{"keep":1}'
    $before = Get-Bytes $dir
    $script:BraveRunning = $true
    $r = Invoke-Bypass @('-ProfilePath', $dir)
    $script:BraveRunning = $false
    Assert ($r.Code -eq 1 -and $r.Output -match 'running') "running Brave: expected refusal, got $($r.Code). $($r.Output)"
    Assert ((Get-Bytes $dir) -eq $before -and (Get-Files $dir) -eq 'Local State') 'running Brave: profile modified'

    # --- Concurrent writer: held lock makes a second writer fail ---
    $dir = New-Profile '{"keep":1}'
    $before = Get-Bytes $dir
    $lock = New-Object IO.FileStream((Join-Path $dir 'Local State.bypass.lock'), [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $r = Invoke-Bypass @('-ProfilePath', $dir)
    } finally {
        $lock.Dispose()
    }
    Assert ($r.Code -eq 1 -and $r.Output -match 'lock') "locked profile: expected failure, got $($r.Code). $($r.Output)"
    Assert ((Get-Bytes $dir) -eq $before) 'locked profile: Local State modified'
    Remove-Item -LiteralPath (Join-Path $dir 'Local State.bypass.lock') -Force
    Assert ((Invoke-Bypass @('-ProfilePath', $dir)).Code -eq 0) 'apply after lock release should succeed'

    Write-Host "profile.ps1: all tests passed" -ForegroundColor Green
    $code = 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    $code = 1
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
exit $code
