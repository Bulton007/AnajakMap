$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ngrok-command.ps1')
try {
    $agent = Get-AnajakNgrokCommand
    & $agent config check *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Run Configure Ngrok.cmd first to save your account authtoken locally.' }
    $backend = Split-Path $PSScriptRoot -Parent
    if (!(Test-Path -LiteralPath (Join-Path $backend '.env'))) {
        throw 'Use the existing initialized backend checkout with its original .env. This launcher does not create or replace credentials.'
    }
    if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
        $env:PATH = "$(Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin');$env:PATH"
    }
    function Test-AnajakDockerReady {
        try { & docker info --format '{{.ServerVersion}}' *> $null; return ($LASTEXITCODE -eq 0) }
        catch { return $false }
    }
    if (!(Test-AnajakDockerReady)) {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (!(Test-Path -LiteralPath $desktop)) { throw 'Install Docker Desktop and enable its Linux engine first.' }
        Start-Process -FilePath $desktop -WindowStyle Hidden
        $deadline = (Get-Date).AddMinutes(4)
        Write-Host 'Waiting for Docker Desktop Linux engine...'
        while (!(Test-AnajakDockerReady)) {
            if ((Get-Date) -ge $deadline) { throw 'Docker did not become ready. Open Docker Desktop, resolve its startup prompt, then retry.' }
            Start-Sleep -Seconds 3
        }
    }
    # Preserve the current database, volumes and credentials. No random
    # Cloudflare tunnel is started by this entrypoint.
    & (Join-Path $PSScriptRoot 'start-laptop.ps1')
    $port = if ($env:LAPTOP_NGINX_PORT) { $env:LAPTOP_NGINX_PORT } else { '8090' }
    $origin = "http://127.0.0.1:$port"
    $deadline = (Get-Date).AddMinutes(3)
    Write-Host 'Waiting for the API behind Nginx...'
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest "$origin/api/v1/auth/config" -UseBasicParsing -TimeoutSec 4
            if ($response.StatusCode -eq 200) { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 3
    }
    if (!$ready) { throw 'The backend did not become ready. Check Docker service logs before exposing it.' }
    & (Join-Path $PSScriptRoot 'test-laptop.ps1') -BaseUrl $origin
    $existing = $null
    try { $existing = Invoke-RestMethod 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 2 } catch { }
    if ($existing) {
        $matching = @($existing.tunnels | Where-Object {
            $_.proto -eq 'https' -and ([string]$_.config.addr).TrimEnd('/') -eq $origin
        })
        if ($matching.Count -eq 1) {
            $public = [Uri]$matching[0].public_url
            if ($public.Scheme -ne 'https' -or $public.UserInfo) { throw 'Unexpected existing tunnel URL.' }
            Write-Host "Already running: $($public.AbsoluteUri.TrimEnd('/'))/api/v1/" -ForegroundColor Green
            Write-Host 'Keep the existing ngrok window open. No duplicate agent was started.'
            exit 0
        }
        throw 'An ngrok agent is already running for a different origin. Keep that instance or close it before starting this backend tunnel.'
    }
    Write-Host ''
    Write-Host 'Starting the account-assigned ngrok HTTPS endpoint.' -ForegroundColor Green
    Write-Host 'Copy its HTTPS Forwarding address and append /api/v1/ for Flutter.'
    Write-Host 'Keep this window, Docker and your PC running. Closing ngrok disconnects the public URL.'
    # Authentication traffic must not be retained in the local request inspector.
    & $agent http $origin --inspect=false
    if ($LASTEXITCODE -ne 0) { throw 'ngrok could not connect. Check its message above, account token, usage quota and internet connection.' }
    exit 0
} catch {
    Write-Host "Startup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
