# Run on the hosting PC after copying the AI update sources into the repository.
param([switch]$UseBundledConfiguration)
$ErrorActionPreference = 'Stop'
$secret = $null
$verifiedAiSettings = $null
$previousAiEnvironment = $null
$bundledAi = $null
$script:AnajakAiSetupVersion = '2026.10.28.1'
try {
    Write-Host "AnajakMap AI Setup v$script:AnajakAiSetupVersion" -ForegroundColor Cyan
    Write-Host "Script: $PSCommandPath"
    Write-Host ('Backend: ' + (Split-Path $PSScriptRoot -Parent))
    . (Join-Path $PSScriptRoot 'ai-settings.ps1')
    if (!(Test-AnajakAiKey ('synthetic.' + ('x' * 256)))) {
        throw 'The AI key helper is outdated. Run Install AI Repair.cmd from the current repair package before entering credentials.'
    }
    Set-Location (Split-Path $PSScriptRoot -Parent)
    if (!(Test-Path -LiteralPath '.env')) { throw 'Run this from the initialized backend project. Its existing .env is required.' }
    & docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Open Docker Desktop and wait for the Linux engine.' }
    $envPath = Join-Path (Get-Location) '.env'
    $content = [IO.File]::ReadAllText($envPath)
    $settings = @{}
    foreach ($line in ($content -split "`r?`n")) {
        if ($line -match '^(AI_PROVIDER|GEMINI_API_KEY|GEMINI_MODEL)=(.*)$') { $settings[$matches[1]] = ConvertFrom-AnajakAiDotEnvValue $matches[2] }
    }
    Write-Host 'Gemini credentials stay in this hosting PC, never in Flutter.'
    Write-Host 'Up to three short fictional setup requests may be sent to Google for temporary server errors; they may consume API quota.'
    if ($UseBundledConfiguration) {
        $projectRoot = Split-Path (Split-Path (Get-Location).Path -Parent) -Parent
        $bundledPath = Join-Path $projectRoot 'private-config/.env'
        if (!(Test-Path -LiteralPath $bundledPath -PathType Leaf)) {
            throw 'Bundled private configuration is missing. Extract the complete private backend ZIP before using Use Bundled AI.cmd. Existing settings were not changed.'
        }
        $bundledAi = @{}
        foreach ($line in ([IO.File]::ReadAllText($bundledPath) -split "`r?`n")) {
            if ($line -match '^(GEMINI_API_KEY|GEMINI_MODEL)=(.*)$') { $bundledAi[$matches[1]] = ConvertFrom-AnajakAiDotEnvValue $matches[2] }
        }
        $entered = $bundledAi['GEMINI_API_KEY']
        Write-Host 'Using the bundled Gemini key and model. Database, Gmail and other existing settings are retained.'
    } else {
        $secret = Read-Host 'Gemini API key (hidden; Enter keeps an existing configured key)' -AsSecureString
        $entered = (New-Object System.Net.NetworkCredential('', $secret)).Password
    }
    $key = if ($UseBundledConfiguration) { $entered } elseif ($entered) { $entered } else { $settings['GEMINI_API_KEY'] }
    if (!(Test-AnajakAiKey $key)) { throw 'Enter the complete Gemini key: 16-4096 visible characters on one line, without spaces or control characters. Google verifies whether the credential is valid.' }
    $existingModel = $settings['GEMINI_MODEL']
    if (!$existingModel) { $existingModel = 'gemini-3.8-flash' } # Existing backend default; checked with Google below.
    if ($UseBundledConfiguration) {
        $model = [string]$bundledAi['GEMINI_MODEL']
        $bundledAi = $null
    } else {
        $model = (Read-Host "Gemini model ID from AI Studio (Enter keeps '$existingModel')").Trim()
        if (!$model) { $model = $existingModel }
    }
    if (!$model -or $model -notmatch '^gemini-[A-Za-z0-9.-]+$') { throw 'Enter a supported Gemini model ID from your Google AI Studio project.' }
    Write-Host 'Checking the configured model with Google...'
    $test = Invoke-AnajakAiSetupTest -ApiKey $key -Model $model
    $test = $null
    foreach ($setting in @(@('AI_PROVIDER','gemini'), @('GEMINI_API_KEY',$key), @('GEMINI_MODEL',$model))) {
        $content = Set-AnajakAiDotEnvValue $content $setting[0] $setting[1]
    }
    [IO.File]::WriteAllText($envPath, $content, (New-Object Text.UTF8Encoding($false)))
    $verifiedAiSettings = @{ AI_PROVIDER='gemini'; GEMINI_API_KEY=$key; GEMINI_MODEL=$model }
    $key = $null; $entered = $null; $content = $null; $settings = $null
    Write-Host 'Google test passed. Building the AI backend update...'
    $source = (Get-Location).Path
    & docker run --rm --mount "type=bind,source=$source,target=/workspace" `
        --mount type=volume,source=anajak-maven-cache,target=/root/.m2 -w /workspace `
        maven:3.9.11-eclipse-temurin-21 mvn -B -ntp -pl ai-guide-service -am package -DskipTests
    if ($LASTEXITCODE -ne 0) { throw 'AI package build failed. The existing running service was not replaced.' }
    $compose = @('compose', '-f', 'compose.yml', '-f', 'compose.media-source.yml',
        '-f', 'compose.local.yml', '-f', 'compose.runtime.yml', '-f', 'compose.laptop.yml')
    # Compose gives process variables precedence over .env. Pin only the three
    # settings verified above so a stale shell AI_PROVIDER=fixture cannot win.
    # Credentials stay in process memory and never become command arguments.
    $previousAiEnvironment = @{}
    foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) {
        $previousAiEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) {
        [Environment]::SetEnvironmentVariable($name, $verifiedAiSettings[$name], 'Process')
    }
    $verifiedAiSettings = $null
    $bundledAi = $null
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
    Write-Host 'Run Check AI.cmd on this hosting PC, then test a fictional question in the current app using its existing public URL.'
    Write-Host 'This setup test verifies text only. Photo and voice stay unavailable until their model support and feature flags are configured.'
    Write-Host 'Conversation context sharing is off until the user enables it.'
    exit 0
} catch {
    Write-Host "AI update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    $key = $null; $entered = $null; $content = $null; $settings = $null
    $verifiedAiSettings = $null
    $bundledAi = $null
    if ($previousAiEnvironment) {
        foreach ($name in @('AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL')) {
            [Environment]::SetEnvironmentVariable($name, $previousAiEnvironment[$name], 'Process')
        }
        $previousAiEnvironment = $null
    }
    if ($secret) { $secret.Dispose() }
}
