# Actuator readiness, not a Docker HEALTHCHECK field, confirms service startup.
function Wait-BackendServiceReady {
    param(
        [Parameter(Mandatory=$true)][string]$ContainerId,
        [Parameter(Mandatory=$true)][string]$Service,
        [Parameter(Mandatory=$true)][ValidateRange(1,65535)][int]$Port,
        [ValidateRange(0,1800)][int]$TimeoutSeconds = 180,
        [ValidateRange(0,30)][int]$PollSeconds = 2
    )
    if ([string]::IsNullOrWhiteSpace($ContainerId)) { throw "$Service has no running container. Start the existing backend before retrying." }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $uri = "http://127.0.0.1:$Port/actuator/health/readiness"
    do {
        $state = $null
        try {
            $raw = & docker inspect --format '{{json .State}}' $ContainerId 2>$null
            if ($LASTEXITCODE -eq 0) { $state = ($raw -join "`n") | ConvertFrom-Json }
        } catch { } # Native startup stderr is an exception in Windows PowerShell 5.1.
        if ($state -and $state.Status -in @('exited', 'dead', 'paused', 'removing')) {
            throw "$Service is $($state.Status). Check its local Docker logs and existing database/dependencies; no credentials were changed."
        }
        if ($state -and $state.Status -eq 'running' -and !$state.Restarting) {
            try {
                $body = & docker exec $ContainerId wget -q -T 3 -O - $uri 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $health = ($body -join "`n") | ConvertFrom-Json
                    if ($health.status -eq 'UP') { return }
                }
            } catch { } # Incomplete startup, HTTP failures and invalid responses are not success.
        }
        if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
        if ($PollSeconds -gt 0) { Start-Sleep -Seconds $PollSeconds }
    } while ($true)
    throw "$Service did not report readiness UP within $TimeoutSeconds seconds. Check Oracle, Redis, RabbitMQ and this service's local logs."
}
