param([ValidatePattern('^[a-z0-9][a-z0-9_-]{0,62}$')][string]$ProjectName = 'anajakmap')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai-diagnostics.ps1')
try {
    & docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Open Docker Desktop on the hosting PC and wait for the Linux engine.' }
    $ids = @(& docker ps -a --filter "label=com.docker.compose.project=$ProjectName" --filter 'label=com.docker.compose.service=ai-guide-service' --format '{{.ID}}' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $ids.Count -ne 1 -or !$ids[0]) {
        throw 'One AI service container was not found. Run this checker on the PC hosting the existing AnajakMap backend.'
    }
    $raw = & docker inspect $ids[0] 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the AI service container.' }
    $snapshot = @(($raw -join "`n") | ConvertFrom-Json)[0]
    $report = Get-AnajakAiConfigurationReport $snapshot.Config.Env
    $state = [string]$snapshot.State.Status
    $report['containerState'] = $(if ($state -in @('created','running','paused','restarting','removing','exited','dead')) { $state } else { 'unknown' })
    $report['readinessUp'] = $false
    if ($state -eq 'running') {
        try {
            $healthRaw = & docker exec $ids[0] wget -q -T 3 -O - http://127.0.0.1:8083/actuator/health/readiness 2>$null
            if ($LASTEXITCODE -eq 0) {
                $health = ($healthRaw -join "`n") | ConvertFrom-Json
                $report['readinessUp'] = ($health.status -eq 'UP')
            }
        } catch { }
    }
    # Limited local log evidence, reduced to numeric counts in memory.
    $previousErrorAction = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 wraps native stderr even for a successful
        # docker logs invocation; capture it without echoing any raw lines.
        $ErrorActionPreference = 'Continue'
        $logLines = @(& docker logs --since 30m --tail 2000 $ids[0] 2>&1 | ForEach-Object { [string]$_ })
    } finally { $ErrorActionPreference = $previousErrorAction }
    $report['recentFailures'] = Get-AnajakAiFailureSummary $logLines
    $report['logWindow'] = 'last_30_minutes_max_2000_lines'
    $report | ConvertTo-Json -Depth 5
    Write-Host 'Configured means settings are present; it does not confirm that Google accepted the key or model.'
    Write-Host 'This check made no AI requests and changed no settings. Recent failure counts may predate your latest attempt.'
    exit 0
} catch {
    # Only controlled errors above are shown; unexpected errors can include command details.
    $message = $_.Exception.Message
    if ($message -notmatch '^(Open Docker Desktop|One AI service container|Could not inspect)') {
        $message = 'AI diagnostics could not finish. Check Docker on the hosting PC; no configuration was changed.'
    }
    Write-Host $message -ForegroundColor Red
    exit 1
} finally {
    $raw = $null; $snapshot = $null; $logLines = $null
}
