$ErrorActionPreference = 'Stop'

try {
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if (!$dockerCommand) {
        $dockerFolder = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
        if (!(Test-Path -LiteralPath (Join-Path $dockerFolder 'docker.exe'))) {
            throw 'Docker Desktop is not installed. Install it before starting the backend.'
        }
        $env:PATH = "$dockerFolder;$env:PATH"
    }
    function Test-DockerReady {
        try {
            & docker info --format '{{.ServerVersion}}' *> $null
            return ($LASTEXITCODE -eq 0)
        } catch { return $false }
    }

    if (!(Test-DockerReady)) {
        $desktopPath = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (!(Test-Path -LiteralPath $desktopPath)) { throw 'Docker Desktop application was not found.' }
        Write-Host 'Starting Docker Desktop. The engine may take a few minutes...'
        Start-Process -FilePath $desktopPath -WindowStyle Hidden
        $deadline = (Get-Date).AddMinutes(4)
        $nextMessage = Get-Date
        while (!(Test-DockerReady)) {
            if ((Get-Date) -ge $deadline) {
                throw 'Docker did not become ready. Open Docker Desktop, resolve any startup prompt, then double-click Start Backend.cmd again.'
            }
            if ((Get-Date) -ge $nextMessage) {
                Write-Host 'Waiting for the Docker Linux engine...'
                $nextMessage = (Get-Date).AddSeconds(15)
            }
            Start-Sleep -Seconds 3
        }
    }

    $backendPath = Split-Path $PSScriptRoot -Parent
    $needsSetup = !(Test-Path -LiteralPath (Join-Path $backendPath '.env'))
    if (!$needsSetup) {
        try {
            & docker image inspect anajakmap-gateway-service:latest *> $null
            $needsSetup = ($LASTEXITCODE -ne 0)
        } catch { $needsSetup = $true }
    }
    if ($needsSetup) {
        Write-Host 'First-time setup: generating missing local credentials, building images and initializing the database.'
        Write-Host 'The first run can take a while. Existing .env credentials will be preserved.'
        & (Join-Path $PSScriptRoot 'start-local.ps1')
    }
    & (Join-Path $PSScriptRoot 'start-laptop.ps1') -TemporaryPublicUrl
    & (Join-Path $PSScriptRoot 'test-laptop.ps1')
    Write-Host ''
    Write-Host 'AnajakMap backend is ready.' -ForegroundColor Green
    Write-Host 'Keep this laptop awake, connected to the internet, and Docker running.'
    Write-Host 'The temporary public URL shown above can change after a tunnel restart.'
    exit 0
} catch {
    Write-Host ''
    Write-Host "Startup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
