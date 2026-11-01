param([switch]$CheckOnly, [string]$ProjectName = 'anajakmap')
$ErrorActionPreference = 'Stop'
$temporary = $null
. (Join-Path $PSScriptRoot 'env-recovery.ps1')
try {
    if ($ProjectName -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Invalid Compose project name.' }
    $backend = Split-Path $PSScriptRoot -Parent
    $destination = Join-Path $backend '.env'
    if (Test-Path -LiteralPath $destination) { throw 'This backend already has .env. Recovery refuses to overwrite it.' }
    foreach ($marker in @('compose.yml','pom.xml')) {
        if (!(Test-Path -LiteralPath (Join-Path $backend $marker))) { throw 'Extract the recovery files into the existing project root before running them.' }
    }
    function Read-RecoveryDockerJson {
        param([string[]]$Arguments)
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = & docker @Arguments 2>$null
            $status = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previous }
        if ($status -ne 0) { throw 'Docker metadata is unavailable. Open Docker Desktop and keep the existing containers.' }
        try { return (($raw -join "`n") | ConvertFrom-Json) }
        catch { throw 'Docker metadata could not be parsed safely. Nothing was written.' }
    }
    $snapshots = @()
    $oracleFound = $false
    foreach ($service in @('oracle','redis','rabbitmq','minio','object-init','identity-service',
        'trip-service','ai-guide-service','discovery-service','expense-service',
        'reservation-service','journal-service','notification-service','gateway-service')) {
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $ids = @(& docker ps -aq --filter "label=com.docker.compose.project=$ProjectName" --filter "label=com.docker.compose.service=$service" 2>$null)
            $status = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previous }
        if ($status -ne 0) { throw 'Docker is not ready. Open Docker Desktop first.' }
        $ids = @($ids | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
        if ($ids.Count -gt 1) { throw "Multiple recorded $service containers exist. Recovery cannot choose one safely." }
        if (!$ids.Count) { continue }
        if ($service -eq 'oracle') {
            $mounts = @(Read-RecoveryDockerJson -Arguments @('inspect','--format','{{json .Mounts}}',$ids[0]))
            Assert-AnajakRecoveryOracleVolume -Mounts $mounts -ExpectedVolume "${ProjectName}_oracle-data"
            $oracleFound = $true
        }
        $environment = @(Read-RecoveryDockerJson -Arguments @('inspect','--format','{{json .Config.Env}}',$ids[0]))
        $snapshots += [pscustomobject]@{Service=$service;Environment=$environment}
    }
    if (!$oracleFound) { throw 'No original Oracle container remains. A data volume alone does not provide all application keys; restore the matching backup.' }
    $settings = Get-AnajakRecoveredSettings -Snapshots $snapshots
    $settings['COMPOSE_PROJECT_NAME'] = $ProjectName
    $text = ConvertTo-AnajakRecoveredEnv -Settings $settings
    if ($CheckOnly) {
        Write-Host "Recovery is available from $($snapshots.Count) recorded containers. No file or service was changed." -ForegroundColor Green
        exit 0
    }
    # CreateNew prevents races and accidental replacement. No Docker mutation,
    # password reset, schema change, or database deletion occurs in this tool.
    $temporary = Join-Path $backend ('.env.recovery-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($text)
        $stream.Write($bytes,0,$bytes.Length)
    } finally { $stream.Dispose() }
    [IO.File]::Move($temporary,$destination)
    Write-Host 'Recovered the recorded configuration into this backend .env. No secret values were displayed.' -ForegroundColor Green
    Write-Host 'Database data and credentials were not changed. Run Start Public Backend.cmd next to verify service startup.'
    exit 0
} catch {
    Write-Host "Recovery stopped: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($temporary -and [IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    $text=$null; $bytes=$null; $settings=$null; $snapshots=$null; $environment=$null; $raw=$null
}
