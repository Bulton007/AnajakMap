$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai-diagnostics.ps1')
$passed = 0
function Assert-AiDiagnostic([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "AI diagnostic regression failed: $Name" }
    $script:passed++
}
$secret = 'synthetic-private-key-that-must-never-appear'
$settings = Get-AnajakAiConfigurationReport @('AI_PROVIDER=gemini','GEMINI_MODEL=gemini-synthetic',"GEMINI_API_KEY=$secret",'GEMINI_VISION_ENABLED=true','GEMINI_VOICE_ENABLED=false',"DB_PASSWORD=$secret")
Assert-AiDiagnostic ($settings.configured -and $settings.visionEnabled -and !$settings.voiceEnabled) 'flags require configured Gemini'
Assert-AiDiagnostic (!(($settings | ConvertTo-Json -Compress).Contains($secret))) 'all secret values omitted'
Assert-AiDiagnostic ($settings.providerVerification -eq 'not_tested') 'configuration does not claim live verification'
$missing = Get-AnajakAiConfigurationReport @('AI_PROVIDER=gemini','GEMINI_VISION_ENABLED=true','GEMINI_VOICE_ENABLED=true')
Assert-AiDiagnostic (!$missing.configured -and !$missing.visionEnabled -and !$missing.voiceEnabled) 'missing key disables media'
$fixture = Get-AnajakAiConfigurationReport @()
Assert-AiDiagnostic ($fixture.demo -and !$fixture.configured -and $fixture.provider -eq 'fixture') 'default fixture clearly labeled'
$invalid = Get-AnajakAiConfigurationReport @("AI_PROVIDER=$secret","GEMINI_MODEL=$secret")
Assert-AiDiagnostic (!(($invalid | ConvertTo-Json -Compress).Contains($secret))) 'untrusted setting values are not echoed'
$adapter = Get-AnajakAiConfigurationReport @('AI_PROVIDER=adapter','PROVIDER_URL=https://provider.invalid',"PROVIDER_KEY=$secret")
Assert-AiDiagnostic ($adapter.configured -and !(($adapter | ConvertTo-Json -Compress).Contains('provider.invalid'))) 'adapter URL and credential omitted'
$summary = Get-AnajakAiFailureSummary @("private payload $secret gemini_http_failure status=429",'gemini_http_failure status=503','gemini_http_failure status=503','gemini_transport_failure type=ConnectException','ai_job_failed id=private-id type=ResponseStatusException',"unrelated $secret")
Assert-AiDiagnostic ($summary.upstreamHttpFailures['429'] -eq 1 -and $summary.upstreamHttpFailures['503'] -eq 2 -and $summary.transportFailures -eq 1 -and $summary.failedJobAttempts -eq 1) 'only whitelisted numeric failure evidence'
Assert-AiDiagnostic (!(($summary | ConvertTo-Json -Compress).Contains($secret)) -and !(($summary | ConvertTo-Json -Compress).Contains('private-id'))) 'raw logs and job identifiers omitted'
Write-Host "$passed AI diagnostic regression checks passed. Only synthetic inputs were used."
