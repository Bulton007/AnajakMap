# Pure projections only: never return raw environment, log lines, prompts or provider responses.
function Get-AnajakAiConfigurationReport {
    param([object[]]$Environment)
    $settings = @{}
    foreach ($entry in $Environment) {
        $value = [string]$entry
        $separator = $value.IndexOf('=')
        if ($separator -gt 0) { $settings[$value.Substring(0,$separator)] = $value.Substring($separator+1) }
    }
    $provider = [string]$settings['AI_PROVIDER']
    if ([string]::IsNullOrWhiteSpace($provider)) { $provider = 'fixture' }
    if ($provider -notin @('gemini','fixture','adapter')) { $provider = 'invalid_configuration' }
    $model = [string]$settings['GEMINI_MODEL']
    if ($model -and $model -notmatch '^gemini-[A-Za-z0-9.-]{1,80}$') { $model = 'invalid_configuration' }
    $hasKey = ![string]::IsNullOrWhiteSpace([string]$settings['GEMINI_API_KEY'])
    $configured = if ($provider -eq 'gemini') { $hasKey } elseif ($provider -eq 'adapter') {
        ![string]::IsNullOrWhiteSpace([string]$settings['PROVIDER_URL']) -and ![string]::IsNullOrWhiteSpace([string]$settings['PROVIDER_KEY'])
    } else { $false }
    return [ordered]@{
        provider = $provider
        configured = [bool]$configured
        demo = ($provider -eq 'fixture')
        model = $(if ($provider -eq 'gemini' -and $model) { $model } else { $null })
        hasGeminiKey = $hasKey
        visionEnabled = ($provider -eq 'gemini' -and $hasKey -and [string]$settings['GEMINI_VISION_ENABLED'] -ieq 'true')
        voiceEnabled = ($provider -eq 'gemini' -and $hasKey -and [string]$settings['GEMINI_VOICE_ENABLED'] -ieq 'true')
        providerVerification = 'not_tested'
    }
}

function Get-AnajakAiFailureSummary {
    param([string[]]$Lines)
    $statuses = @{}
    $transport = 0
    $jobs = 0
    foreach ($line in $Lines) {
        # Match only application-owned markers. Never echo the surrounding line.
        if ($line -match 'gemini_http_failure status=([1-5][0-9]{2})(?:[^0-9]|$)') {
            $status = $matches[1]
            if (!$statuses.ContainsKey($status)) { $statuses[$status] = 0 }
            $statuses[$status]++
        }
        if ($line -match 'gemini_transport_failure type=[A-Za-z][A-Za-z0-9]{0,100}(?:[^A-Za-z0-9]|$)') { $transport++ }
        if ($line -match 'ai_job_failed id=') { $jobs++ }
    }
    return [ordered]@{upstreamHttpFailures=$statuses;transportFailures=$transport;failedJobAttempts=$jobs}
}
