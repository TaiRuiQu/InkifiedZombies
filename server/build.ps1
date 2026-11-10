param([string]$Go = "go")
$ErrorActionPreference = "Stop"
$serverDirectory = $PSScriptRoot
$distributionDirectory = [System.IO.Path]::GetFullPath((Join-Path $serverDirectory '..\dist\server'))
New-Item -ItemType Directory -Force -Path $distributionDirectory | Out-Null
Push-Location $serverDirectory
try {
    & $Go test -count=1 ./...
    if ($LASTEXITCODE -ne 0) { throw 'Relay tests failed' }
    $originalGOOS = $env:GOOS
    $originalGOARCH = $env:GOARCH
    $originalCGO = $env:CGO_ENABLED
    try {
        $env:CGO_ENABLED = '0'
        $env:GOARCH = 'amd64'
        $env:GOOS = 'windows'
        & $Go build -trimpath '-ldflags=-s -w' -o (Join-Path $distributionDirectory 'ink-tide-relay-windows-amd64.exe') .
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
        $env:GOOS = 'linux'
        & $Go build -trimpath '-ldflags=-s -w' -o (Join-Path $distributionDirectory 'ink-tide-relay-linux-amd64') .
        if ($LASTEXITCODE -ne 0) { throw 'Linux build failed' }
    } finally {
        $env:GOOS = $originalGOOS
        $env:GOARCH = $originalGOARCH
        $env:CGO_ENABLED = $originalCGO
    }
    Copy-Item -LiteralPath (Join-Path $serverDirectory 'README.md') -Destination $distributionDirectory
    Copy-Item -LiteralPath (Join-Path $serverDirectory 'THIRD_PARTY_LICENSES.md') -Destination $distributionDirectory
    $checksums = Get-ChildItem -LiteralPath $distributionDirectory -File | Where-Object { $_.Name -match '^ink-tide-relay-' } | Get-FileHash -Algorithm SHA256 | ForEach-Object { '{0}  {1}' -f $_.Hash.ToLower(), [System.IO.Path]::GetFileName($_.Path) }
    $checksums | Set-Content -LiteralPath (Join-Path $distributionDirectory 'SHA256SUMS.txt') -Encoding ascii
    Write-Host "Built relay programs in $distributionDirectory"
} finally { Pop-Location }
