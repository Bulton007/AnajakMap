# Run on the hosting PC after copying the AI update sources into the repository.
$ErrorActionPreference = 'Stop'
$secret = $null
try {
    Set-Location (Split-Path $PSScriptRoot -Parent)
    if (!(Test-Path -LiteralPath '.env')) { throw 'Run this from the initialized backend project. Its existing .env is required.' }
    & docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Open Docker Desktop and wait for the Linux engine.' }
    $envPath = Join-Path (Get-Location) '.env'
    $content = [IO.File]::ReadAllText($envPath)
    $settings = @{}
    foreach ($line in ($content -split "`r?`n")) {
        if ($line -match '^([A-Z_]+)=(.*)$') { $settings[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'") }
    }
    Write-Host 'Gemini credentials stay in this hosting PC, never in Flutter.'
    Write-Host 'One short fictional setup request will be sent to Google; it may consume API quota.'
    $secret = Read-Host 'Gemini API key (hidden; Enter keeps an existing configured key)' -AsSecureString
    $entered = (New-Object System.Net.NetworkCredential('', $secret)).Password.Trim()
    $key = if ($entered) { $entered } else { $settings['GEMINI_API_KEY'] }
    if (!$key -or $key -notmatch '^[A-Za-z0-9_-]{20,200}$') { throw 'Enter a valid Gemini API key from Google AI Studio.' }
    $existingModel = $settings['GEMINI_MODEL']
    if (!$existingModel) { $existingModel = 'gemini-3.8-flash' } # Existing backend default; checked with Google below.
    $model = (Read-Host "Gemini model ID from AI Studio (Enter keeps '$existingModel')").Trim()
    if (!$model) { $model = $existingModel }
    if (!$model -or $model -notmatch '^gemini-[A-Za-z0-9.-]+$') { throw 'Enter a supported Gemini model ID from your Google AI Studio project.' }
    $payload = @{
        contents = @(@{parts=@(@{text='This is a fictional travel app setup test. Reply with READY.'})})
        generationConfig = @{maxOutputTokens=4096}
    } | ConvertTo-Json -Depth 8 -Compress
    Write-Host 'Checking the configured model with Google...'
    try {
        $test = Invoke-RestMethod -Method Post -Uri "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" `
            -Headers @{'x-goog-api-key'=$key} -ContentType 'application/json' -Body $payload -TimeoutSec 55
    } catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($status -eq 429) { throw 'Google quota/rate limit reached (429). No settings changed. Check your Google quota and retry later.' }
        throw "Google setup test failed (HTTP $status). Check key permissions, model availability and connectivity. No settings changed."
    }
    $answer = ($test.candidates[0].content.parts | ForEach-Object { if (!$_.thought) { $_.text } }) -join ''
    if ([string]::IsNullOrWhiteSpace($answer)) { throw 'Google returned no usable answer. No settings changed.' }
    foreach ($setting in @(@('AI_PROVIDER','gemini'), @('GEMINI_API_KEY',$key), @('GEMINI_MODEL',$model))) {
        $pattern = '(?m)^' + $setting[0] + '=.*$'
        $line = $setting[0] + '=' + $setting[1]
        if ([regex]::IsMatch($content, $pattern)) { $content = [regex]::Replace($content, $pattern, $line) }
        else { $content += "`r`n$line`r`n" }
    }
    [IO.File]::WriteAllText($envPath, $content, (New-Object Text.UTF8Encoding($false)))
    $key = $null; $entered = $null; $content = $null; $settings = $null
    Write-Host 'Google test passed. Building the AI backend update...'
    $source = (Get-Location).Path
    & docker run --rm --mount "type=bind,source=$source,target=/workspace" `
        --mount type=volume,source=anajak-maven-cache,target=/root/.m2 -w /workspace `
        maven:3.9.11-eclipse-temurin-21 mvn -B -ntp -pl ai-guide-service -am package -DskipTests
    if ($LASTEXITCODE -ne 0) { throw 'AI package build failed. The existing running service was not replaced.' }
    $compose = @('compose', '-f', 'compose.yml', '-f', 'compose.media-source.yml',
        '-f', 'compose.local.yml', '-f', 'compose.runtime.yml', '-f', 'compose.laptop.yml')
    & docker @compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose configuration is invalid.' }
    & docker @compose build ai-guide-service
    if ($LASTEXITCODE -ne 0) { throw 'AI image build failed. The existing running service was not replaced.' }
    & docker @compose up -d --no-deps --no-build ai-guide-service
    if ($LASTEXITCODE -ne 0) { throw 'AI service restart failed. Check Docker and run Start Backend.cmd.' }
    $id = & docker @compose ps -q ai-guide-service
    $ready = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        try {
            & docker exec $id wget -q -O /dev/null http://127.0.0.1:8083/actuator/health/readiness *> $null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        } catch { } # Windows PowerShell can treat native startup stderr as an exception.
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'AI service did not become ready. Inspect its Docker logs; do not change database credentials.' }
    Write-Host 'AI service is ready. Gmail, database and public tunnel were left running.' -ForegroundColor Green
    Write-Host 'Install app build 3 and test a fictional question and follow-up. Context sharing is off until the user enables it.'
    exit 0
} catch {
    Write-Host "AI update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    $key = $null; $entered = $null; $content = $null; $settings = $null
    if ($secret) { $secret.Dispose() }
}
