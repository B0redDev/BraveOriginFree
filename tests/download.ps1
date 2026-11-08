# Real loopback HTTP download; no external service or browser required.
$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ("brave download ' ! [literal] " + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$job = $null
$client = $null
try {
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $target = Join-Path $temp 'browser.zip'
    $source = (Resolve-Path -LiteralPath "$PSScriptRoot\..\src\update.ps1").ProviderPath
    $job = Start-Job -ArgumentList $source, $target, $port -ScriptBlock {
        param($source, $target, $port)
        $ErrorActionPreference = 'Stop'
        . $source
        Save-BraveArchive -Url "http://127.0.0.1:$port/browser.zip" -Path $target
    }
    $accept = $listener.AcceptTcpClientAsync()
    if (-not $accept.Wait(15000)) { throw 'Download did not connect to the local HTTP server.' }
    $client = $accept.Result
    $stream = $client.GetStream()
    $stream.ReadTimeout = 15000
    $reader = New-Object IO.StreamReader($stream)
    while ($reader.ReadLine()) { }
    $payload = [byte[]](0..255)
    $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 256`r`nConnection: close`r`n`r`n")
    $stream.Write($header, 0, $header.Length)
    $stream.Write($payload, 0, $payload.Length)
    $client.Dispose(); $client = $null
    if (-not (Wait-Job $job -Timeout 15)) { throw 'Download timed out.' }
    Receive-Job $job -ErrorAction Stop | Out-Null
    if ($job.State -ne 'Completed') { throw 'Download failed.' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -cne [Convert]::ToBase64String($payload)) {
        throw 'Download bytes changed or literal destination was not honored.'
    }
    Write-Host 'PASS: real HTTP streaming to a path containing spaces, apostrophe, exclamation and brackets.'
} finally {
    if ($client) { $client.Dispose() }
    $listener.Stop()
    if ($job) { Stop-Job $job; Remove-Job $job }
    Remove-Item -LiteralPath $temp -Recurse -Force
}
