$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (Test-Path -LiteralPath '.env') { throw '.env already exists; refusing to overwrite.' }
$projectName = if ($env:COMPOSE_PROJECT_NAME) { $env:COMPOSE_PROJECT_NAME } else { 'anajakmap' }
$existingData = $false
try {
    & docker volume inspect "${projectName}_oracle-data" *> $null
    $existingData = ($LASTEXITCODE -eq 0)
} catch { }
if ($existingData) {
    throw 'An Oracle data volume already exists but .env is missing. Restore its original .env before starting; new credentials cannot unlock existing data.'
}
# The existing JDK build container supports Windows PowerShell 5.1 too.
# Credentials stay inside the ignored output file, never in tool output.
$source = (Get-Location).Path
& docker run --rm --network none --mount "type=bind,source=$source,target=/workspace" `
    -w /workspace maven:3.9.11-eclipse-temurin-21 java scripts/InitDev.java
if ($LASTEXITCODE -ne 0) { throw 'Credential initialization failed. Check that Docker Desktop is running.' }
