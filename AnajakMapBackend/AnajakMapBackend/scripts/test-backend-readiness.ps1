# Offline regression checks. The docker function below never invokes Docker.
# Compatible with Windows PowerShell 5.1; no credentials or fixture files are used.
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'backend-readiness.ps1'
if (!(Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'Backend readiness helper is missing.' }
. $helper

$script:passed = 0
$script:failures = @()
$script:container = 'test-container-id'
$script:privateSentinel = 'PRIVATE_TEST_BODY_MUST_NOT_BE_PRINTED'

function New-Reply([string]$Output, [int]$ExitCode = 0, [switch]$Throw) {
    return [pscustomobject]@{ Output = $Output; ExitCode = $ExitCode; Throw = [bool]$Throw }
}

function Set-DockerReplies([object[]]$Inspect, [object[]]$Probe) {
    $script:inspectReplies = @($Inspect)
    $script:probeReplies = @($Probe)
    $script:inspectCount = 0
    $script:probeCount = 0
    $script:dockerCalls = New-Object 'System.Collections.Generic.List[object]'
    $global:LASTEXITCODE = 0
}

function Get-NextReply([object[]]$Replies, [int]$Index) {
    if ($Replies.Count -eq 0) { throw 'No mock response configured; a real Docker call is forbidden.' }
    return $Replies[[Math]::Min($Index, $Replies.Count - 1)]
}

function docker {
    $arguments = @($args | ForEach-Object { [string]$_ })
    $script:dockerCalls.Add($arguments)
    if ($arguments[0] -eq 'inspect') {
        $reply = Get-NextReply $script:inspectReplies $script:inspectCount
        $script:inspectCount++
    } elseif ($arguments[0] -eq 'exec') {
        $reply = Get-NextReply $script:probeReplies $script:probeCount
        $script:probeCount++
    } else {
        throw 'Unexpected mocked Docker operation.'
    }
    $global:LASTEXITCODE = $reply.ExitCode
    if ($reply.Throw) { throw $reply.Output }
    if ($null -ne $reply.Output) { Write-Output $reply.Output }
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw $Message }
}

function Invoke-Ready([int]$TimeoutSeconds = 0) {
    Wait-BackendServiceReady -ContainerId $script:container -Service 'test-service' -Port 8093 -TimeoutSeconds $TimeoutSeconds -PollSeconds 0
}

function Expect-ReadinessFailure([scriptblock]$Action = { Invoke-Ready }) {
    $captured = New-Object 'System.Collections.Generic.List[string]'
    $failed = $false
    $failureMessage = ''
    try {
        & $Action *>&1 | ForEach-Object { $captured.Add([string]$_) }
    } catch {
        $failed = $true
        $failureMessage = $_.Exception.Message
    }
    Assert-True $failed 'Expected readiness to fail instead of reporting success.'
    $visible = ($captured -join "`n") + "`n" + $failureMessage
    Assert-True (!$visible.Contains($script:privateSentinel)) 'Readiness disclosed a raw Docker response or error.'
    return $failureMessage
}

function Invoke-ReadinessTest([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
        Write-Host "PASS $Name" -ForegroundColor Green
    } catch {
        $script:failures += $Name + ': ' + $_.Exception.Message
        Write-Host ("FAIL $Name - " + $_.Exception.Message) -ForegroundColor Red
    }
}

$running = '{"Status":"running","Restarting":false}'
$up = '{"status":"UP"}'
$down = '{"status":"DOWN","details":"' + $script:privateSentinel + '"}'

Invoke-ReadinessTest 'No Docker Health property is required when readiness is UP' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply $up)
    Invoke-Ready > $null
    Assert-Equal 1 $script:inspectCount 'Expected one container inspection.'
    Assert-Equal 1 $script:probeCount 'Expected one HTTP readiness probe.'
}

Invoke-ReadinessTest 'Docker Health starting does not override an UP readiness endpoint' {
    Set-DockerReplies @(New-Reply '{"Status":"running","Restarting":false,"Health":{"Status":"starting"}}') @(New-Reply $up)
    Invoke-Ready > $null
    Assert-Equal 1 $script:probeCount 'Expected readiness to be probed during startup.'
}

Invoke-ReadinessTest 'Starting application is retried until HTTP readiness is UP' {
    Set-DockerReplies @(New-Reply $running) @((New-Reply $down), (New-Reply $up))
    Invoke-Ready -TimeoutSeconds 1 > $null
    Assert-Equal 2 $script:probeCount 'Expected a failed startup probe followed by success.'
}

Invoke-ReadinessTest 'HTTP exit zero with JSON DOWN cannot report success' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply $down)
    Expect-ReadinessFailure > $null
    Assert-Equal 1 $script:probeCount 'A zero timeout must still attempt readiness once.'
}

Invoke-ReadinessTest 'Malformed HTTP response cannot report success' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply ('{invalid:' + $script:privateSentinel))
    Expect-ReadinessFailure > $null
}

Invoke-ReadinessTest 'HTML error page cannot report success' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply ('<html>' + $script:privateSentinel + '</html>'))
    Expect-ReadinessFailure > $null
}

Invoke-ReadinessTest 'JSON without an UP status cannot report success' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply '{"components":{}}')
    Expect-ReadinessFailure > $null
}

Invoke-ReadinessTest 'Nonzero wget exit rejects even an UP response body' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply $up -ExitCode 1)
    Expect-ReadinessFailure > $null
}

Invoke-ReadinessTest 'Transient HTTP command failure is retried' {
    Set-DockerReplies @(New-Reply $running) @((New-Reply $script:privateSentinel -ExitCode 1), (New-Reply $up))
    Invoke-Ready -TimeoutSeconds 1 > $null
    Assert-Equal 2 $script:probeCount 'Expected transient HTTP failure to be retried.'
}

Invoke-ReadinessTest 'Thrown HTTP error is bounded and does not disclose raw output' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply $script:privateSentinel -Throw)
    Expect-ReadinessFailure > $null
}

Invoke-ReadinessTest 'Nonzero inspection exit cannot report success' {
    Set-DockerReplies @(New-Reply $running -ExitCode 1) @(New-Reply $up)
    Expect-ReadinessFailure > $null
    Assert-Equal 0 $script:probeCount 'Do not probe a container whose state was not inspected.'
}

Invoke-ReadinessTest 'Transient inspection failure is retried' {
    Set-DockerReplies @((New-Reply $script:privateSentinel -ExitCode 1), (New-Reply $running)) @(New-Reply $up)
    Invoke-Ready -TimeoutSeconds 1 > $null
    Assert-Equal 2 $script:inspectCount 'Expected inspection failure to be retried.'
    Assert-Equal 1 $script:probeCount 'Only the successful inspection should lead to HTTP readiness.'
}

Invoke-ReadinessTest 'Thrown inspection error is bounded and does not disclose raw output' {
    Set-DockerReplies @(New-Reply $script:privateSentinel -Throw) @(New-Reply $up)
    Expect-ReadinessFailure > $null
    Assert-Equal 0 $script:probeCount 'A failed inspection must not lead to an HTTP success.'
}

Invoke-ReadinessTest 'Malformed inspection state cannot report success' {
    Set-DockerReplies @(New-Reply ('invalid-state-' + $script:privateSentinel)) @(New-Reply $up)
    Expect-ReadinessFailure > $null
    Assert-Equal 0 $script:probeCount 'Invalid inspection state must not produce a successful probe.'
}

Invoke-ReadinessTest 'Healthy Docker health does not replace the HTTP readiness check' {
    Set-DockerReplies @(New-Reply '{"Status":"running","Restarting":false,"Health":{"Status":"healthy"}}') @(New-Reply $down)
    Expect-ReadinessFailure > $null
    Assert-Equal 1 $script:probeCount 'Expected a real application readiness probe.'
}

foreach ($terminalStatus in @('exited', 'dead', 'paused')) {
    Invoke-ReadinessTest ("Container state $terminalStatus fails without HTTP success") {
        Set-DockerReplies @(New-Reply ('{"Status":"' + $terminalStatus + '","Restarting":false}')) @(New-Reply $up)
        Expect-ReadinessFailure { Invoke-Ready -TimeoutSeconds 1 } > $null
        Assert-Equal 0 $script:probeCount 'A stopped, dead or paused container must not be accepted.'
    }
}

Invoke-ReadinessTest 'Restarting container is retried until running and UP' {
    Set-DockerReplies @((New-Reply '{"Status":"restarting","Restarting":true}'), (New-Reply $running)) @(New-Reply $up)
    Invoke-Ready -TimeoutSeconds 1 > $null
    Assert-Equal 2 $script:inspectCount 'Expected a restart to be retried.'
    Assert-Equal 1 $script:probeCount 'Only the running container should be probed.'
}

Invoke-ReadinessTest 'Readiness probes only the selected container local endpoint' {
    Set-DockerReplies @(New-Reply $running) @(New-Reply $up)
    Invoke-Ready > $null
    $inspectCall = @($script:dockerCalls[0])
    $probeCall = @($script:dockerCalls[1])
    Assert-Equal '{{json .State}}' $inspectCall[2] 'Inspection must parse the optional Health property from state JSON.'
    Assert-True ($inspectCall -contains $script:container) 'Inspection used the wrong container.'
    Assert-Equal 'exec' $probeCall[0] 'Expected docker exec.'
    Assert-Equal $script:container $probeCall[1] 'Probe used the wrong container.'
    Assert-True ($probeCall -contains 'wget') 'Expected an in-container wget readiness probe.'
    Assert-True ($probeCall -contains 'http://127.0.0.1:8093/actuator/health/readiness') 'Probe used the wrong readiness URL.'
    Assert-True ($probeCall -contains '3') 'Probe must have a bounded HTTP timeout.'
}

Write-Host ("`nBackend readiness tests: {0} passed, {1} failed." -f $script:passed, $script:failures.Count)
if ($script:failures.Count -gt 0) { throw ($script:failures -join "`n") }
