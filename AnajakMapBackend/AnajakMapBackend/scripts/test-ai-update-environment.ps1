# Synthetic regression only: mocked Docker/Google; no real credentials or provider requests.
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture = Join-Path $workspace ('.local/ai-update-environment-' + [guid]::NewGuid().ToString('N'))
$fixtureScripts = Join-Path $fixture 'scripts'
[IO.Directory]::CreateDirectory($fixtureScripts) > $null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'update-ai.ps1') -Destination (Join-Path $fixtureScripts 'update-ai.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ai-settings.ps1') -Destination (Join-Path $fixtureScripts 'ai-settings.ps1')
$envFile = Join-Path $fixture '.env'
$syntheticKey = 'synthetic.header.' + ('a' * 256) + '.signature$1#with"quotes'
$syntheticModel = 'gemini-test-model'
$originalContent = "GMAIL_USERNAME=unchanged@example.invalid`r`nGMAIL_APP_PASSWORD=synthetic-unchanged`r`nPRESERVE=synthetic-original`r`n"
$originalLocation = (Get-Location).Path
$originalEnvironment = @{}
foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL','ANAJAK_AI_TEST_UNRELATED')) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$global:AnajakAiEnvironmentTest = @{failureStage='';composeCalls=0;providerCalls=0;sleepCalls=0;waitSeconds=0;passed=0}
if (!('AnajakSyntheticEnvironmentResponse' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Net;
public sealed class AnajakSyntheticEnvironmentResponse : WebResponse {
    private readonly WebHeaderCollection headers = new WebHeaderCollection();
    public HttpStatusCode StatusCode { get; set; }
    public override WebHeaderCollection Headers { get { return headers; } }
}
'@
}
function Assert-AiEnvironment([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "AI environment regression failed: $Name" }
    $global:AnajakAiEnvironmentTest.passed++
}
function Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    if ($AsSecureString) { return ConvertTo-SecureString $syntheticKey -AsPlainText -Force }
    return $syntheticModel
}
function Invoke-RestMethod {
    $global:AnajakAiEnvironmentTest.providerCalls++
    if ($global:AnajakAiEnvironmentTest.failureStage -eq 'google') { throw 'synthetic provider outage' }
    if ($global:AnajakAiEnvironmentTest.failureStage -eq 'google503') {
        $response=New-Object AnajakSyntheticEnvironmentResponse
        $response.StatusCode=[Net.HttpStatusCode]503
        throw (New-Object Net.WebException('synthetic provider outage',$null,[Net.WebExceptionStatus]::ProtocolError,$response))
    }
    return @{candidates=@(@{content=@{parts=@(@{text='READY'})}})}
}
function Start-Sleep {
    param([double]$Seconds)
    $global:AnajakAiEnvironmentTest.sleepCalls++
    $global:AnajakAiEnvironmentTest.waitSeconds+=$Seconds
}
function docker {
    $global:LASTEXITCODE = 0
    $arguments = $args -join ' '
    if ($args[0] -eq 'compose') {
        $global:AnajakAiEnvironmentTest.composeCalls++
        Assert-AiEnvironment ($env:AI_PROVIDER -ceq 'gemini' -and $env:GEMINI_MODEL -ceq $syntheticModel -and $env:GEMINI_API_KEY -ceq $syntheticKey) 'Compose receives exactly the verified settings'
        Assert-AiEnvironment (!$arguments.Contains($syntheticKey)) 'credential never appears in Docker arguments'
        Assert-AiEnvironment ($env:ANAJAK_AI_TEST_UNRELATED -ceq 'keep-unrelated') 'unrelated environment preserved during Compose'
        if ($global:AnajakAiEnvironmentTest.failureStage -eq 'compose' -and $arguments -match 'config --quiet') { $global:LASTEXITCODE=1; return }
    }
    if ($global:AnajakAiEnvironmentTest.failureStage -eq 'package' -and $args[0] -eq 'run') { $global:LASTEXITCODE=1; return }
    if ($arguments -match 'ps -q ai-guide-service') { return 'synthetic-container' }
}
try {
    foreach ($case in @('success_stale','success_absent','google','google503','package','compose')) {
        [IO.File]::WriteAllText($envFile,$originalContent)
        $global:AnajakAiEnvironmentTest.failureStage = $case
        $global:AnajakAiEnvironmentTest.composeCalls = 0
        $global:AnajakAiEnvironmentTest.providerCalls = 0
        $global:AnajakAiEnvironmentTest.sleepCalls = 0
        $global:AnajakAiEnvironmentTest.waitSeconds = 0
        $before = @{}
        foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) {
            $value = if ($case -eq 'success_absent') { $null } else { 'synthetic-stale-' + $name }
            if ($name -eq 'AI_PROVIDER' -and $value) { $value = 'fixture' }
            [Environment]::SetEnvironmentVariable($name,$value,'Process')
            $before[$name] = $value
        }
        [Environment]::SetEnvironmentVariable('ANAJAK_AI_TEST_UNRELATED','keep-unrelated','Process')
        & (Join-Path $fixtureScripts 'update-ai.ps1')
        $status = $LASTEXITCODE
        foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) {
            Assert-AiEnvironment ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $before[$name]) 'original process environment restored after success/failure'
        }
        Assert-AiEnvironment ($env:ANAJAK_AI_TEST_UNRELATED -ceq 'keep-unrelated') 'unrelated environment unchanged after return'
        if ($case -like 'success_*') {
            Assert-AiEnvironment ($status -eq 0 -and $global:AnajakAiEnvironmentTest.composeCalls -gt 0) 'successful update uses verified Compose settings'
            $saved = [IO.File]::ReadAllText($envFile)
            Assert-AiEnvironment ($saved.Contains('AI_PROVIDER="gemini"') -and $saved.Contains('GMAIL_APP_PASSWORD=synthetic-unchanged')) 'only AI settings updated in local fixture'
        } else {
            Assert-AiEnvironment ($status -eq 1) 'failed setup returns nonzero'
            if ($case -in @('google','google503')) {
                Assert-AiEnvironment ([IO.File]::ReadAllText($envFile) -ceq $originalContent -and $global:AnajakAiEnvironmentTest.composeCalls -eq 0) 'failed provider test preserves file and does not run Compose'
            }
            if ($case -eq 'google503') {
                Assert-AiEnvironment ($global:AnajakAiEnvironmentTest.providerCalls -eq 3 -and $global:AnajakAiEnvironmentTest.sleepCalls -eq 2 -and $global:AnajakAiEnvironmentTest.waitSeconds -eq 15) 'persistent 503 exhausts only the bounded retry budget before preserving services and settings'
            }
        }
    }
    Write-Host "$($global:AnajakAiEnvironmentTest.passed) synthetic AI environment checks passed. No Google calls or real Docker mutations occurred."
} finally {
    foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL','ANAJAK_AI_TEST_UNRELATED')) {
        [Environment]::SetEnvironmentVariable($name,$originalEnvironment[$name],'Process')
    }
    Set-Location -LiteralPath $originalLocation
    $originalEnvironment = $null
    $global:AnajakAiEnvironmentTest = $null
}
