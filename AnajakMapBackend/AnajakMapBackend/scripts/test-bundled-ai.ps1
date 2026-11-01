# Synthetic integration tests only: no real private file, Google call or Docker mutation.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai-settings.ps1')
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixtures = Join-Path $workspace ('.local/bundled-ai-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtures) > $null
$originalLocation = (Get-Location).Path
$originalEnvironment = @{}
$environmentNames = @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL','ANAJAK_BUNDLED_TEST_UNRELATED')
foreach ($name in $environmentNames) { $originalEnvironment[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$global:AnajakBundledTestKey = 'synthetic.bundled.header.' + ('a' * 220) + '.signature$1#with"quotes'
$global:AnajakBundledHostKey = 'synthetic.existing.host.key-' + ('b' * 40)
$global:AnajakBundledModel = 'gemini-bundled-test-model'
$script:hostModel = 'gemini-existing-host-model'
$script:hostOther = "# Existing synthetic host settings`r`nORACLE_PASSWORD='synthetic-host-database-secret'`r`nGMAIL_USERNAME=host@example.invalid`r`nGMAIL_APP_PASSWORD='synthetic-host-mail-secret'`r`nJWT_PRIVATE_KEY=synthetic-host-jwt-secret`r`nGEMINI_VISION_ENABLED=false`r`nGEMINI_VOICE_ENABLED=false`r`nPRESERVE=unchanged`r`n"
$script:hostOriginal = $script:hostOther + "AI_PROVIDER=fixture`r`nGEMINI_API_KEY=$global:AnajakBundledHostKey`r`nGEMINI_MODEL=$script:hostModel`r`n"
$script:bundledOther = "AI_PROVIDER=fixture`r`nORACLE_PASSWORD=synthetic-bundled-database-must-not-copy`r`nGMAIL_APP_PASSWORD=synthetic-bundled-mail-must-not-copy`r`nGEMINI_VISION_ENABLED=true`r`nGEMINI_VOICE_ENABLED=true`r`nBUNDLED_ONLY=must-not-copy`r`n"
$global:AnajakBundledPassed = 0
$global:AnajakBundledState = $null
if (!('AnajakSyntheticBundledResponse' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Net;
public sealed class AnajakSyntheticBundledResponse : WebResponse {
    private readonly WebHeaderCollection headers = new WebHeaderCollection();
    public int StatusCode { get; set; }
    public override WebHeaderCollection Headers { get { return headers; } }
}
'@
}
function Assert-BundledAi([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "Bundled AI regression failed: $Name" }
    $global:AnajakBundledPassed++
}
function Non-AiContent([string]$Content) {
    return [regex]::Replace($Content,'(?m)^(AI_PROVIDER|GEMINI_API_KEY|GEMINI_MODEL)=[^\r\n]*(?:\r?\n|$)','')
}
function Read-Host {
    $global:AnajakBundledState.promptCalls++
    throw 'The bundled configuration flow must not prompt for credentials or a model.'
}
function Start-Sleep {
    param([double]$Seconds)
    $global:AnajakBundledState.waits += $Seconds
}
function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Method,[string]$Uri,[hashtable]$Headers,[string]$ContentType,[string]$Body,[int]$TimeoutSec)
    $global:AnajakBundledState.providerCalls++
    Assert-BundledAi ($Headers['x-goog-api-key'] -ceq $global:AnajakBundledTestKey) 'provider receives only the bundled key'
    Assert-BundledAi ($Uri -ceq "https://generativelanguage.googleapis.com/v1beta/models/$($global:AnajakBundledModel):generateContent") 'provider receives the bundled model on the official endpoint'
    Assert-BundledAi (!$Uri.Contains($global:AnajakBundledTestKey) -and !$Body.Contains($global:AnajakBundledTestKey) -and !$Body.Contains('synthetic-host-database-secret') -and !$Body.Contains('synthetic-host-mail-secret')) 'credential and unrelated private settings are excluded from URL and request body'
    Assert-BundledAi ((Get-FileHash -LiteralPath $global:AnajakBundledState.hostEnv -Algorithm SHA256).Hash -ceq $global:AnajakBundledState.hostBefore) 'provider verification happens before any target configuration write'
    if ($global:AnajakBundledState.name -eq 'google_transport') { throw (New-Object Net.WebException('synthetic network failure',[Net.WebExceptionStatus]::ConnectFailure)) }
    if ($global:AnajakBundledState.name -eq 'google503') {
        $response=New-Object AnajakSyntheticBundledResponse
        $response.StatusCode=503
        throw (New-Object Net.WebException('synthetic transient failure',$null,[Net.WebExceptionStatus]::ProtocolError,$response))
    }
    if ($global:AnajakBundledState.name -eq 'empty_answer') { return @{candidates=@(@{finishReason='STOP';content=@{parts=@(@{text=' '})}})} }
    return @{candidates=@(@{finishReason='STOP';content=@{parts=@(@{text='READY'})}})}
}
function docker {
    $global:LASTEXITCODE=0
    $global:AnajakBundledState.dockerCalls++
    $arguments=$args -join ' '
    Assert-BundledAi (!$arguments.Contains($global:AnajakBundledTestKey) -and !$arguments.Contains($global:AnajakBundledHostKey)) 'credentials never become Docker arguments'
    Assert-BundledAi ($arguments -notmatch '\bdown\b|--remove-orphans|\bprune\b|\bvolume rm\b|identity-service') 'updater does not remove data or replace identity services'
    if ($args[0] -eq 'compose') {
        $global:AnajakBundledState.composeCalls++
        Assert-BundledAi ($env:AI_PROVIDER -ceq 'gemini' -and $env:GEMINI_API_KEY -ceq $global:AnajakBundledTestKey -and $env:GEMINI_MODEL -ceq $global:AnajakBundledModel) 'Compose uses only the verified bundled AI values'
        Assert-BundledAi ($env:ANAJAK_BUNDLED_TEST_UNRELATED -ceq 'keep-process-setting') 'unrelated process environment is preserved'
        if ($global:AnajakBundledState.name -eq 'compose_failure' -and $arguments -match 'config --quiet') { $global:LASTEXITCODE=1; return }
        if ($arguments -match 'up -d') { $global:AnajakBundledState.serviceReplacements++ }
        if ($arguments -match 'ps -q ai-guide-service') { return 'synthetic-ai-container' }
    }
    if ($args[0] -eq 'run' -and $global:AnajakBundledState.name -eq 'package_failure') { $global:LASTEXITCODE=1; return }
}
try {
    foreach ($case in @('success_stale','success_absent','missing_file','missing_key','missing_model','invalid_model','invalid_key','google_transport','google503','empty_answer','package_failure','compose_failure','missing_host_env')) {
        $project=Join-Path $fixtures $case
        $backend=Join-Path $project 'AnajakMapBackend/AnajakMapBackend'
        $scripts=Join-Path $backend 'scripts'
        $private=Join-Path $project 'private-config'
        [IO.Directory]::CreateDirectory($scripts) > $null
        [IO.Directory]::CreateDirectory($private) > $null
        foreach ($file in @('update-ai.ps1','ai-settings.ps1')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $scripts $file)
        }
        $hostEnv=Join-Path $backend '.env'
        if ($case -ne 'missing_host_env') { [IO.File]::WriteAllText($hostEnv,$script:hostOriginal,(New-Object Text.UTF8Encoding($false))) }
        $bundleEnv=Join-Path $private '.env'
        if ($case -ne 'missing_file') {
            $bundleContent=$script:bundledOther
            if ($case -ne 'missing_key') {
                $key=if ($case -eq 'invalid_key') {'short'} else {$global:AnajakBundledTestKey}
                $bundleContent=Set-AnajakAiDotEnvValue $bundleContent 'GEMINI_API_KEY' $key
            }
            if ($case -ne 'missing_model') {
                $model=if ($case -eq 'invalid_model') {'../not-a-model'} else {$global:AnajakBundledModel}
                $bundleContent=Set-AnajakAiDotEnvValue $bundleContent 'GEMINI_MODEL' $model
            }
            [IO.File]::WriteAllText($bundleEnv,$bundleContent,(New-Object Text.UTF8Encoding($false)))
        }
        $beforeEnvironment=@{}
        foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) {
            $value=if ($case -eq 'success_absent') {$null} elseif ($name -eq 'AI_PROVIDER') {'fixture'} else {'synthetic-stale-process-' + $name}
            [Environment]::SetEnvironmentVariable($name,$value,'Process')
            $beforeEnvironment[$name]=$value
        }
        [Environment]::SetEnvironmentVariable('ANAJAK_BUNDLED_TEST_UNRELATED','keep-process-setting','Process')
        $hostBefore=if (Test-Path -LiteralPath $hostEnv) {(Get-FileHash -LiteralPath $hostEnv -Algorithm SHA256).Hash} else {$null}
        $bundleBefore=if (Test-Path -LiteralPath $bundleEnv) {(Get-FileHash -LiteralPath $bundleEnv -Algorithm SHA256).Hash} else {$null}
        $global:AnajakBundledState=@{name=$case;hostEnv=$hostEnv;hostBefore=$hostBefore;promptCalls=0;dockerCalls=0;providerCalls=0;composeCalls=0;serviceReplacements=0;waits=@()}
        $log=Join-Path $project 'result.log'
        & (Join-Path $scripts 'update-ai.ps1') -UseBundledConfiguration *> $log
        $status=$LASTEXITCODE
        $output=[IO.File]::ReadAllText($log)
        Assert-BundledAi ($global:AnajakBundledState.promptCalls -eq 0) 'bundled flow never requests key or model interactively'
        Assert-BundledAi (!$output.Contains($global:AnajakBundledTestKey) -and !$output.Contains($global:AnajakBundledHostKey) -and !$output.Contains('synthetic-host-database-secret') -and !$output.Contains('synthetic-host-mail-secret') -and !$output.Contains('synthetic-bundled-mail-must-not-copy')) 'console output never reveals credentials or unrelated configuration'
        foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) {
            Assert-BundledAi ([Environment]::GetEnvironmentVariable($name,'Process') -ceq $beforeEnvironment[$name]) 'original process AI environment restored on every path'
        }
        Assert-BundledAi ($env:ANAJAK_BUNDLED_TEST_UNRELATED -ceq 'keep-process-setting') 'unrelated process setting unchanged'
        if ($bundleBefore) {
            Assert-BundledAi ((Get-FileHash -LiteralPath $bundleEnv -Algorithm SHA256).Hash -ceq $bundleBefore) 'bundled private configuration remains byte-identical'
        } else {
            Assert-BundledAi (!(Test-Path -LiteralPath $bundleEnv)) 'missing bundled configuration is not created'
        }
        $verifiedCase=$case -in @('success_stale','success_absent','package_failure','compose_failure')
        if ($verifiedCase) {
            $saved=[IO.File]::ReadAllText($hostEnv)
            Assert-BundledAi ((Non-AiContent $saved) -ceq (Non-AiContent $script:hostOriginal)) 'non-AI host configuration retains exact bytes'
            $savedAi=@{}
            foreach ($line in ($saved -split "`r?`n")) {
                if ($line -match '^(AI_PROVIDER|GEMINI_API_KEY|GEMINI_MODEL)=(.*)$') { $savedAi[$matches[1]]=ConvertFrom-AnajakAiDotEnvValue $matches[2] }
            }
            Assert-BundledAi ($savedAi.AI_PROVIDER -ceq 'gemini' -and $savedAi.GEMINI_API_KEY -ceq $global:AnajakBundledTestKey -and $savedAi.GEMINI_MODEL -ceq $global:AnajakBundledModel) 'only the verified bundled key/model and Gemini activation are saved'
            Assert-BundledAi (!$saved.Contains('synthetic-bundled-database-must-not-copy') -and !$saved.Contains('synthetic-bundled-mail-must-not-copy') -and !$saved.Contains('BUNDLED_ONLY=must-not-copy')) 'bundled database mail and unrelated fields are ignored'
        } elseif ($hostBefore) {
            Assert-BundledAi ((Get-FileHash -LiteralPath $hostEnv -Algorithm SHA256).Hash -ceq $hostBefore) 'failed preflight or provider validation keeps host configuration byte-identical'
        } else {
            Assert-BundledAi (!(Test-Path -LiteralPath $hostEnv)) 'missing host configuration is not initialized'
        }
        if ($case -like 'success_*') {
            Assert-BundledAi ($status -eq 0 -and $global:AnajakBundledState.serviceReplacements -eq 1) 'verified bundled setup activates only the AI service'
        } else {
            Assert-BundledAi ($status -eq 1) 'failed bundled setup returns nonzero'
            Assert-BundledAi ($global:AnajakBundledState.serviceReplacements -eq 0) 'failed setup never replaces a running service'
        }
        if ($case -in @('missing_file','missing_key','missing_model','invalid_model','invalid_key','missing_host_env')) {
            Assert-BundledAi ($global:AnajakBundledState.providerCalls -eq 0 -and $global:AnajakBundledState.composeCalls -eq 0) 'missing or invalid bundled fields cannot fall back to host credentials or call providers'
        }
        if ($case -in @('google_transport','google503','empty_answer','package_failure')) {
            Assert-BundledAi ($global:AnajakBundledState.composeCalls -eq 0) 'provider or package failure prevents Compose operations'
        }
        if ($case -eq 'google503') {
            Assert-BundledAi ($global:AnajakBundledState.providerCalls -eq 3 -and ($global:AnajakBundledState.waits -join ',') -eq '5,10') 'bundled setup preserves bounded provider retry behavior'
        }
    }
    Write-Host "$global:AnajakBundledPassed bundled AI checks passed with synthetic private files, mocked Google and mocked Docker. No real credentials or services were accessed."
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name,$originalEnvironment[$name],'Process') }
    Set-Location -LiteralPath $originalLocation
    $global:AnajakBundledState=$null
    $originalEnvironment=$null
}
