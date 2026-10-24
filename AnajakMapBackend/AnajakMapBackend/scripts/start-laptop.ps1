param([switch]$TemporaryPublicUrl)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
function Invoke-Docker([string[]]$Arguments) {
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed (exit $LASTEXITCODE)." }
}
if (!(Test-Path -LiteralPath '.env')) {
    throw 'Initialize and test the local backend first using scripts/start-local.ps1.'
}
Invoke-Docker -Arguments @('info', '--format', '{{.ServerVersion}}')
$compose = @('compose', '-f', 'compose.yml', '-f', 'compose.media-source.yml',
    '-f', 'compose.local.yml', '-f', 'compose.runtime.yml', '-f', 'compose.laptop.yml')
Invoke-Docker ($compose + @('config', '--quiet'))
Invoke-Docker ($compose + @('up', '-d', '--no-build'))
$port = if ($env:LAPTOP_NGINX_PORT) { $env:LAPTOP_NGINX_PORT } else { '8090' }
Write-Host "Nginx: http://127.0.0.1:$port/api/v1/"
Write-Host 'Run scripts/test-laptop.ps1 when services finish starting.'
if ($TemporaryPublicUrl) {
    # Do not expose a stopped or uninitialized identity service.
    $ready = $false
    $deadline = (Get-Date).AddMinutes(3)
    Write-Host 'Waiting for the backend before starting the public tunnel...'
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest "http://127.0.0.1:$port/api/v1/auth/config" -UseBasicParsing -TimeoutSec 4
            if ($response.StatusCode -eq 200) { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 3
    }
    if (!$ready) { throw 'Backend is not ready for testing after three minutes. Check service logs.' }
    $publicCompose = $compose + @('-f', 'compose.laptop-tunnel.yml')
    Invoke-Docker ($publicCompose + @('up', '-d', '--no-build', 'laptop-tunnel'))
    $tunnelId = & docker @publicCompose ps -q laptop-tunnel
    $tunnelStartedAt = & docker inspect --format '{{.State.StartedAt}}' $tunnelId
    if ($LASTEXITCODE -ne 0 -or !$tunnelStartedAt) { throw 'Could not determine the current tunnel session.' }
    $publicUrl = $null
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        # Windows PowerShell treats native stderr log lines as ErrorRecords.
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $tunnelLines = & docker logs --since ($tunnelStartedAt -join '').Trim() --tail 200 $tunnelId 2>&1
        } finally { $ErrorActionPreference = $previousPreference }
        $urlMatches = [regex]::Matches(($tunnelLines -join "`n"), 'https://[a-z0-9-]+\.trycloudflare\.com')
        if ($urlMatches.Count -gt 0) { $publicUrl = $urlMatches[$urlMatches.Count - 1].Value; break }
        Start-Sleep -Seconds 2
    }
    if (!$publicUrl) { throw 'Tunnel address is not available yet. Inspect laptop-tunnel logs.' }
    Write-Host "Temporary API: $publicUrl/api/v1/ (changes after restarting the tunnel)"
    $configPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../../flutter_app/config/connected.public.local.json'))
    if (Test-Path -LiteralPath (Split-Path $configPath -Parent)) {
        $clientConfig = @{ APP_MODE = 'connected'; API_BASE_URL = "$publicUrl/api/v1/"; MAP_TILE_URL = ''; MAP_ATTRIBUTION = '' } | ConvertTo-Json
        [System.IO.File]::WriteAllText($configPath, $clientConfig, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host 'Flutter public local configuration updated. Rebuild the app if the address changed.'
    }
}
