param(
    [string]$Godot = 'G:\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [ValidateSet('direct','relay')][string]$Transport = 'direct',
    [int]$Port = 0,
    [switch]$ExistingRelay
)
$ErrorActionPreference = 'Stop'
$projectDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logDirectory = Join-Path $projectDirectory 'dev_shots'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
if ($Port -eq 0) { $Port = if ($Transport -eq 'direct') { 18777 } else { 18778 } }
$roomCode = 'COOP' + (Get-Random -Minimum 1000 -Maximum 9999)
$startedProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
try {
    if ($Transport -eq 'relay' -and -not $ExistingRelay) {
        $relayBinary = Join-Path $projectDirectory 'dist\server\ink-tide-relay-windows-amd64.exe'
        $relayProcess = Start-Process -FilePath $relayBinary -ArgumentList @('-addr', "127.0.0.1:$Port") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDirectory 'coop-test-server.log') -RedirectStandardError (Join-Path $logDirectory 'coop-test-server.err.log')
        $startedProcesses.Add($relayProcess)
        Start-Sleep -Milliseconds 400
        if ($relayProcess.HasExited) { throw 'Test relay failed to start; check port and server logs' }
    }
    $hostLog = Join-Path $logDirectory "coop-$Transport-host.log"
    $hostErrorLog = Join-Path $logDirectory "coop-$Transport-host.err.log"
    $clientLog = Join-Path $logDirectory "coop-$Transport-client.log"
    $clientErrorLog = Join-Path $logDirectory "coop-$Transport-client.err.log"
    $common = @('--headless','--path',$projectDirectory,'--script','res://tests/coop_integration.gd','--',"--transport=$Transport","--port=$Port","--room=$roomCode")
    $hostProcess = Start-Process -FilePath $Godot -ArgumentList ($common + '--role=host') -WindowStyle Hidden -PassThru -RedirectStandardOutput $hostLog -RedirectStandardError $hostErrorLog
    $startedProcesses.Add($hostProcess)
    Start-Sleep -Milliseconds 700
    $clientProcess = Start-Process -FilePath $Godot -ArgumentList ($common + '--role=client') -WindowStyle Hidden -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError $clientErrorLog
    $startedProcesses.Add($clientProcess)
    if (-not $clientProcess.WaitForExit(40000)) { throw 'Client exceeded 40-second audit deadline' }
    if (-not $hostProcess.WaitForExit(3000)) { throw 'Host did not finish after client' }
    $hostOutput = Get-Content -LiteralPath $hostLog -Raw
    $clientOutput = Get-Content -LiteralPath $clientLog -Raw
    $errorOutput = (Get-Content -LiteralPath $hostErrorLog -Raw) + (Get-Content -LiteralPath $clientErrorLog -Raw)
    Write-Output $hostOutput
    Write-Output $clientOutput
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0 -or $errorOutput -match '(?m)^(SCRIPT ERROR|ERROR):' -or $hostOutput -notmatch 'PASS complete' -or $clientOutput -notmatch 'PASS complete') {
        Write-Output $errorOutput
        throw "Coop audit failed: host=$($hostProcess.ExitCode) client=$($clientProcess.ExitCode)"
    }
    Write-Output "PASS transport=$Transport host_exit=0 client_exit=0; logs: $logDirectory"
} finally {
    foreach ($startedProcess in $startedProcesses) {
        if (-not $startedProcess.HasExited) { Stop-Process -Id $startedProcess.Id }
    }
}
