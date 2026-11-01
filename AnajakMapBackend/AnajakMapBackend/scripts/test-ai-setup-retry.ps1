# Synthetic provider responses only. Never contact Google or read real credentials.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai-settings.ps1')
if (!('AnajakSyntheticSetupResponse' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Net;
public sealed class AnajakSyntheticSetupResponse : WebResponse {
    private readonly WebHeaderCollection headers = new WebHeaderCollection();
    public int StatusCode { get; set; }
    public override WebHeaderCollection Headers { get { return headers; } }
}
'@
}
$script:passed = 0
$script:syntheticKey = 'synthetic.header.' + ('a' * 256) + '.signature$1#private'
$script:privateMarker = 'synthetic-provider-body-must-never-be-printed'
$script:state = $null
function Assert-SetupRetry([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "AI setup retry regression failed: $Name" }
    $script:passed++
}
function Ready-SetupResult {
    return @{candidates=@(@{finishReason='STOP';content=@{parts=@(@{text='READY'})}})}
}
function Reset-SetupRetry([object[]]$Steps) {
    $script:state = @{steps=$Steps;calls=0;waits=@();messages=@()}
}
function Write-Host {
    param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Object,
          [object]$ForegroundColor, [object]$BackgroundColor, [switch]$NoNewline)
    $script:state.messages += ($Object -join ' ')
}
function Start-Sleep {
    param([double]$Seconds, [int]$Milliseconds)
    if ($Milliseconds) { $Seconds=$Milliseconds/1000.0 }
    $script:state.waits += $Seconds
}
function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Method,[string]$Uri,[hashtable]$Headers,[string]$ContentType,
          [string]$Body,[int]$TimeoutSec)
    Assert-SetupRetry ($Method -ceq 'Post' -or $Method -ceq 'POST') 'uses POST for setup generation'
    Assert-SetupRetry ($Uri -ceq 'https://generativelanguage.googleapis.com/v1beta/models/gemini-test-model:generateContent') 'only the selected official generation endpoint is called'
    Assert-SetupRetry ($Headers['x-goog-api-key'] -ceq $script:syntheticKey -and !$Uri.Contains($script:syntheticKey)) 'key travels only in its authentication header'
    $index=$script:state.calls
    $script:state.calls++
    if ($index -ge $script:state.steps.Count) { throw 'Synthetic request exceeded the planned request budget' }
    $step=$script:state.steps[$index]
    if ($step.kind -eq 'network') { throw (New-Object Net.WebException($script:privateMarker,[Net.WebExceptionStatus]::ConnectFailure)) }
    if ($step.kind -eq 'http') {
        $response=New-Object AnajakSyntheticSetupResponse
        $response.StatusCode=[int]$step.status
        if ($step.retryAfter) { $response.Headers['Retry-After']=[string]$step.retryAfter }
        throw (New-Object Net.WebException($script:privateMarker,$null,[Net.WebExceptionStatus]::ProtocolError,$response))
    }
    if ($step.kind -eq 'raw') { return $step.value }
    return Ready-SetupResult
}
function Invoke-SyntheticSetupFailure {
    param([int]$MaximumAttempts=3,[int]$MaximumAutomaticDelaySeconds=30)
    $message=$null
    try {
        $null=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model' -MaximumAttempts $MaximumAttempts -MaximumAutomaticDelaySeconds $MaximumAutomaticDelaySeconds
    } catch { $message=$_.Exception.Message }
    Assert-SetupRetry (![string]::IsNullOrWhiteSpace($message)) 'failure has a safe actionable message'
    Assert-SetupRetry (!$message.Contains($script:syntheticKey) -and !$message.Contains($script:privateMarker)) 'failure omits credential and raw provider detail'
    Assert-SetupRetry (!(($script:state.messages -join "`n").Contains($script:syntheticKey)) -and !(($script:state.messages -join "`n").Contains($script:privateMarker))) 'progress output omits credentials and raw provider detail'
    return $message
}

Reset-SetupRetry @(@{kind='ready'})
$result=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
Assert-SetupRetry ($script:state.calls -eq 1 -and $script:state.waits.Count -eq 0 -and $result.candidates[0].content.parts[0].text -ceq 'READY') 'first successful answer returns immediately'

Reset-SetupRetry @(@{kind='http';status=503},@{kind='http';status=503},@{kind='ready'})
$result=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
Assert-SetupRetry ($script:state.calls -eq 3 -and ($script:state.waits -join ',') -eq '5,10') '503 retries use bounded exponential waits then succeed'

Reset-SetupRetry @(@{kind='http';status=503},@{kind='http';status=503},@{kind='http';status=503})
$message=Invoke-SyntheticSetupFailure
Assert-SetupRetry ($script:state.calls -eq 3 -and ($script:state.waits -join ',') -eq '5,10') 'persistent 503 stops after three attempts'
Assert-SetupRetry ($message -match '503' -and $message -match '(?i)no settings changed') 'persistent 503 describes service failure and unchanged settings'

foreach ($status in @(500,502,504)) {
    Reset-SetupRetry @(@{kind='http';status=$status},@{kind='ready'})
    $null=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
    Assert-SetupRetry ($script:state.calls -eq 2 -and ($script:state.waits -join ',') -eq '5') 'transient server failures retry once before success'
}
foreach ($status in @(400,401,403,404,429)) {
    Reset-SetupRetry @(@{kind='http';status=$status})
    $message=Invoke-SyntheticSetupFailure
    Assert-SetupRetry ($script:state.calls -eq 1 -and $script:state.waits.Count -eq 0) 'client permission model and quota failures are not retried'
    Assert-SetupRetry ($message.Contains([string]$status)) "HTTP failure retains only its safe status ($status)"
}
Reset-SetupRetry @(@{kind='network'})
$null=Invoke-SyntheticSetupFailure
Assert-SetupRetry ($script:state.calls -eq 1 -and $script:state.waits.Count -eq 0) 'transport errors do not cause hidden retries'

Reset-SetupRetry @(@{kind='http';status=503;retryAfter='8'},@{kind='ready'})
$null=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
Assert-SetupRetry (($script:state.waits -join ',') -eq '8') 'numeric provider Retry-After is respected'
Reset-SetupRetry @(@{kind='http';status=503;retryAfter='2'},@{kind='ready'})
$null=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
Assert-SetupRetry (($script:state.waits -join ',') -eq '5') 'short provider Retry-After does not remove exponential backoff'
Reset-SetupRetry @(@{kind='http';status=503;retryAfter=([DateTime]::UtcNow.AddSeconds(14).ToString('r'))},@{kind='ready'})
$null=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
Assert-SetupRetry ($script:state.waits.Count -eq 1 -and $script:state.waits[0] -ge 10 -and $script:state.waits[0] -le 15) 'HTTP date Retry-After is respected'
foreach ($delay in @('31','3600')) {
    Reset-SetupRetry @(@{kind='http';status=503;retryAfter=$delay})
    $message=Invoke-SyntheticSetupFailure
    Assert-SetupRetry ($script:state.calls -eq 1 -and $script:state.waits.Count -eq 0) 'long provider waits stop without sleeping or retrying early'
}
Reset-SetupRetry @(@{kind='http';status=503;retryAfter='invalid'},@{kind='ready'})
$null=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
Assert-SetupRetry (($script:state.waits -join ',') -eq '5') 'invalid Retry-After uses bounded backoff'
Reset-SetupRetry @(@{kind='http';status=503;retryAfter='8'})
$null=Invoke-SyntheticSetupFailure -MaximumAutomaticDelaySeconds 6
Assert-SetupRetry ($script:state.calls -eq 1 -and $script:state.waits.Count -eq 0) 'configured automatic wait cap is honored'
foreach ($attempts in @(1,2)) {
    Reset-SetupRetry @(@{kind='http';status=503},@{kind='http';status=503})
    $null=Invoke-SyntheticSetupFailure -MaximumAttempts $attempts
    Assert-SetupRetry ($script:state.calls -eq $attempts -and $script:state.waits.Count -eq ($attempts-1)) 'requested lower attempt budget is honored'
}

foreach ($badResult in @(
    @{candidates=@()},
    @{candidates=@(@{finishReason='STOP';content=@{parts=@(@{text='   '})}})},
    @{candidates=@(@{finishReason='STOP';content=@{parts=@(@{text=$script:privateMarker;thought=$true})}})},
    @{candidates=@(@{finishReason='MAX_TOKENS';content=@{parts=@(@{text='partial'})}})},
    @{candidates=@(@{finishReason='SAFETY';content=@{parts=@(@{text='blocked'})}})}
)) {
    Reset-SetupRetry @(@{kind='raw';value=$badResult})
    $null=Invoke-SyntheticSetupFailure
    Assert-SetupRetry ($script:state.calls -eq 1 -and $script:state.waits.Count -eq 0) 'unusable successful HTTP response cannot activate setup or trigger retries'
}
Reset-SetupRetry @(@{kind='raw';value=@{candidates=@(@{finishReason='STOP';content=@{parts=@(@{text=$script:privateMarker;thought=$true},@{text='READY'})}})}})
$null=Invoke-AnajakAiSetupTest -ApiKey $script:syntheticKey -Model 'gemini-test-model'
Assert-SetupRetry ($script:state.calls -eq 1 -and !(($script:state.messages -join "`n").Contains($script:privateMarker))) 'usable visible answer can coexist with unprinted thought parts'

foreach ($attempts in @(0,4)) {
    Reset-SetupRetry @()
    $null=Invoke-SyntheticSetupFailure -MaximumAttempts $attempts
    Assert-SetupRetry ($script:state.calls -eq 0) 'invalid retry budget is rejected before network'
}
foreach ($maximumDelay in @(0,31)) {
    Reset-SetupRetry @()
    $null=Invoke-SyntheticSetupFailure -MaximumAutomaticDelaySeconds $maximumDelay
    Assert-SetupRetry ($script:state.calls -eq 0) 'invalid automatic wait cap is rejected before network'
}
Microsoft.PowerShell.Utility\Write-Host "$script:passed AI setup retry checks passed with synthetic HTTP responses and mocked waits only. Google was not contacted."
