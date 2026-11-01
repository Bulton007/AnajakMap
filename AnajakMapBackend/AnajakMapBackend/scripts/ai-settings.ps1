# Opaque server credentials. Never print values or interpolate them into commands.
function Test-AnajakAiKey([string]$Value) {
    return $null -ne $Value -and $Value.Length -ge 16 -and $Value.Length -le 4096 -and $Value -cmatch '\A[\x21-\x7E]+\z'
}

function ConvertTo-AnajakAiDotEnvLiteral([string]$Value) {
    if ($Value -cnotmatch '\A[\x21-\x7E]*\z') { throw 'AI settings must be single-line visible ASCII without spaces or control characters.' }
    # Compose double-quoted values support backslash escapes. Escape dollars
    # too, so a later restart cannot interpolate part of an opaque credential.
    return '"' + $Value.Replace('\','\\').Replace('"','\"').Replace('$','\$') + '"'
}

function ConvertFrom-AnajakAiDotEnvValue([string]$Raw) {
    $value = $Raw.Trim()
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length-1] -eq "'") {
        return $value.Substring(1,$value.Length-2).Replace("\'", "'")
    }
    if ($value.Length -lt 2 -or $value[0] -ne '"' -or $value[$value.Length-1] -ne '"') { return $value }
    $inner = $value.Substring(1,$value.Length-2)
    $decoded = New-Object Text.StringBuilder
    for ($i=0; $i -lt $inner.Length; $i++) {
        $character = $inner[$i]
        if ($character -eq '\' -and $i+1 -lt $inner.Length) {
            $next = $inner[$i+1]
            if ($next -in @('\','"','$')) { [void]$decoded.Append($next); $i++; continue }
            if ($next -in @('n','r','t')) {
                [void]$decoded.Append($(switch($next){'n'{[char]10};'r'{[char]13};'t'{[char]9}})); $i++; continue
            }
        }
        if ($character -eq '$' -and $i+1 -lt $inner.Length -and $inner[$i+1] -eq '$') { [void]$decoded.Append('$'); $i++; continue }
        [void]$decoded.Append($character)
    }
    return $decoded.ToString()
}

function Set-AnajakAiDotEnvValue([string]$Content, [string]$Name, [string]$Value) {
    if ($Name -notin @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) { throw 'Only the three AI settings may be updated by this helper.' }
    $line = $Name + '=' + (ConvertTo-AnajakAiDotEnvLiteral $Value)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=[^\r\n]*'
    if ([regex]::IsMatch($Content,$pattern)) {
        $replaceLiteral = { param($matched) $line }.GetNewClosure()
        return [regex]::Replace($Content,$pattern,[Text.RegularExpressions.MatchEvaluator]$replaceLiteral)
    }
    return $Content + "`r`n" + $line + "`r`n"
}

function Get-AnajakAiHttpStatus($Failure) {
    try {
        if ($Failure.Exception.Response) { return [int]$Failure.Exception.Response.StatusCode }
    } catch { }
    return 0
}

function Get-AnajakAiRetryAfter($Failure) {
    $raw = $null
    try { $headers = $Failure.Exception.Response.Headers; $raw = $headers['Retry-After'] } catch { }
    if (!$raw) {
        try { $raw = @($Failure.Exception.Response.Headers.GetValues('Retry-After'))[0] } catch { }
    }
    if (!$raw) { return $null }
    $value = [string]@($raw)[0]
    if ($value -match '\A[0-9]{1,12}\z') { return [long]$value }
    $deadline = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$deadline)) {
        return [long][Math]::Max(0, [Math]::Ceiling(($deadline - [DateTimeOffset]::UtcNow).TotalSeconds))
    }
    return $null
}

function Invoke-AnajakAiSetupTest {
    param(
        [Parameter(Mandatory=$true)][string]$ApiKey,
        [Parameter(Mandatory=$true)][ValidatePattern('^gemini-[A-Za-z0-9.-]+$')][string]$Model,
        [ValidateRange(1,3)][int]$MaximumAttempts = 3,
        [ValidateRange(1,30)][int]$MaximumAutomaticDelaySeconds = 30
    )
    $payload = @{
        contents = @(@{parts=@(@{text='This is a fictional travel app setup test. Reply with READY.'})})
        generationConfig = @{maxOutputTokens=4096}
    } | ConvertTo-Json -Depth 8 -Compress
    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $result = Invoke-RestMethod -Method Post -Uri "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent" `
                -Headers @{'x-goog-api-key'=$ApiKey} -ContentType 'application/json' -Body $payload -TimeoutSec 40
        } catch {
            $status = Get-AnajakAiHttpStatus $_
            $retryAfter = Get-AnajakAiRetryAfter $_
            if ($status -in @(500,502,503,504) -and $attempt -lt $MaximumAttempts) {
                $delay = [long][Math]::Max((5 * [Math]::Pow(2, $attempt - 1)), [double]$retryAfter)
                if ($delay -gt $MaximumAutomaticDelaySeconds) {
                    throw "Google is temporarily unavailable (HTTP $status) and requests a retry after $delay seconds. Automatic waiting is limited to $MaximumAutomaticDelaySeconds seconds. Retry later. No settings changed."
                }
                Write-Host "Google temporary error (HTTP $status), attempt $attempt/$MaximumAttempts. Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
                continue
            }
            $message = switch ($status) {
                0 { 'Could not contact Google. Check the hosting PC network, DNS, proxy and TLS connection.' }
                400 { 'Google rejected the setup request (HTTP 400). Check the selected model and key configuration.' }
                401 { 'Google authentication failed (HTTP 401). Check the key in Google AI Studio.' }
                403 { 'Google denied access (HTTP 403). Check project permissions and Gemini API restrictions.' }
                404 { 'Google could not find the selected model for this request (HTTP 404). Choose a model available to your project.' }
                429 {
                    if ($null -ne $retryAfter -and $retryAfter -gt 0) {
                        "Google quota/rate limit reached (HTTP 429). Retry after $retryAfter seconds or check the project quota. No automatic retry was made."
                    } else { 'Google quota/rate limit reached (HTTP 429). Check the project quota and retry timing. No automatic retry was made.' }
                }
                { $_ -in @(500,502,503,504) } {
                    "Google is temporarily unavailable for the selected model (HTTP $status) after $attempt attempt(s). Key validity is not confirmed by this error. Retry later, or explicitly select another supported model such as gemini-3.5-flash-lite."
                }
                default { "Google setup test failed (HTTP $status). Check the provider status and model configuration." }
            }
            throw ($message + ' No settings changed.')
        }
        $candidate = @($result.candidates)[0]
        $finish = [string]$candidate.finishReason
        $answer = (@($candidate.content.parts) | ForEach-Object { if (!$_.thought) { [string]$_.text } }) -join ''
        if ([string]::IsNullOrWhiteSpace($answer) -or ($finish -and $finish -ne 'STOP')) {
            throw 'Google returned no complete usable answer. The AI service was not activated. No settings changed.'
        }
        return $result
    }
}
