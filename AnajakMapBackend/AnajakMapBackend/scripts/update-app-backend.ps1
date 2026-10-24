# Run after extracting the source update into the EXISTING hosting-PC checkout.
param([switch]$CheckOnly, [string]$HostingRoot)
$ErrorActionPreference = 'Stop'
try {
    $backendFolder = Split-Path $PSScriptRoot -Parent
    Set-Location -LiteralPath $backendFolder
    $envFile = Join-Path $backendFolder '.env'
    if ($HostingRoot -and (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        . (Join-Path $PSScriptRoot 'backend-update-install.ps1')
        $currentRoot = Split-Path (Split-Path $backendFolder -Parent) -Parent
        $explicitRoot = Get-BackendUpdateTarget -SourceRoot $currentRoot -HostingRoot $HostingRoot
        if ([IO.Path]::GetFullPath($currentRoot).TrimEnd('\', '/') -ne $explicitRoot) {
            throw 'This initialized checkout differs from -HostingRoot. Run the updater from the intended checkout or from the complete extracted patch. No services were changed.'
        }
    }
    if (!(Test-Path -LiteralPath $envFile -PathType Leaf)) {
        $folders = @()
        Write-Host "Current update source: $backendFolder"
        Write-Host "Missing private configuration: $envFile"
        Write-Host 'GitHub downloads and the source patch intentionally do not contain .env.'
        try {
            if (Get-Command docker -ErrorAction SilentlyContinue) {
                $ids = @(& docker ps -aq --filter 'label=com.docker.compose.project=anajakmap' --filter 'label=com.docker.compose.service=gateway-service' 2>$null)
                if ($LASTEXITCODE -eq 0 -and $ids.Count -gt 0) {
                    foreach ($containerId in $ids) {
                        # Inspect labels only. Full inspect output includes credentials.
                        $labelsText = & docker inspect --format '{{json .Config.Labels}}' $containerId 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            $labels = ($labelsText -join "`n") | ConvertFrom-Json
                            $folder = $labels.'com.docker.compose.project.working_dir'
                            if ($folder -and $folders -notcontains $folder) { $folders += $folder }
                        }
                    }
                    foreach ($folder in $folders) {
                        Write-Host "Docker recorded hosting backend folder: $folder"
                    }
                }
            }
        } catch { Write-Host 'Could not locate the old hosting folder from Docker. Open the folder used by your working Start Backend.cmd.' }
        . (Join-Path $PSScriptRoot 'backend-update-install.ps1')
        $sourceRoot = Split-Path (Split-Path $backendFolder -Parent) -Parent
        $targetRoot = Get-BackendUpdateTarget -SourceRoot $sourceRoot -HostingRoot $HostingRoot -RecordedBackendFolders $folders
        $sourceManifest = Join-Path $sourceRoot 'backend-update-files.txt'
        if (!(Test-Path -LiteralPath $sourceManifest -PathType Leaf)) { throw 'Complete patch source manifest is required. Download the current update ZIP.' }
        $manifestEntries = [IO.File]::ReadAllLines($sourceManifest)
        foreach ($required in @('Update App Backend.cmd', 'backend-update-files.txt',
            'AnajakMapBackend/AnajakMapBackend/scripts/update-app-backend.ps1',
            'AnajakMapBackend/AnajakMapBackend/scripts/backend-update-install.ps1')) {
            if ($manifestEntries -notcontains $required) { throw 'The patch manifest is incomplete. No source files or services were changed.' }
        }
        $overlay = Install-BackendUpdateSources -SourceRoot $sourceRoot -TargetRoot $targetRoot -CheckOnly:$CheckOnly
        if ($CheckOnly) {
            Write-Host "Patch check passed. Would apply $($overlay.FileCount) source files to $($overlay.TargetRoot). No files or services were changed."
            exit 0
        }
        Write-Host "Applied $($overlay.FileCount) update files to $($overlay.TargetRoot). Existing .env was retained."
        Write-Host "Original source backup: $($overlay.BackupPath)"
        $updatedScript = Join-Path $overlay.TargetRoot 'AnajakMapBackend/AnajakMapBackend/scripts/update-app-backend.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updatedScript
        exit $LASTEXITCODE
    }
    if ($CheckOnly) {
        Write-Host "Hosting folder check passed: $backendFolder"
        Write-Host 'Existing .env was found without reading or displaying its contents. No services were changed.'
        exit 0
    }
    & docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Open Docker Desktop and wait for its Linux engine.' }
    $compose = @('compose', '-f', 'compose.yml', '-f', 'compose.media-source.yml',
        '-f', 'compose.local.yml', '-f', 'compose.runtime.yml', '-f', 'compose.laptop.yml')
    & docker @compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose configuration is invalid. No running service was replaced.' }
    $source = (Get-Location).Path
    & docker run --rm --mount "type=bind,source=$source,target=/workspace" `
        --mount type=volume,source=anajak-maven-cache,target=/root/.m2 -w /workspace `
        maven:3.9.11-eclipse-temurin-21 mvn -B -ntp -pl ai-guide-service,discovery-service,expense-service -am package -DskipTests
    if ($LASTEXITCODE -ne 0) { throw 'Package build failed. Existing running services were not replaced.' }
    $services = @('ai-guide-service', 'discovery-service', 'expense-service')
    & docker @compose build @services
    if ($LASTEXITCODE -ne 0) { throw 'Image build failed. Existing running services were not replaced.' }
    & docker @compose up -d --no-deps --no-build @services
    if ($LASTEXITCODE -ne 0) { throw 'Service restart failed. Check Docker logs locally.' }
    foreach ($service in $services) {
        $id = & docker @compose ps -q $service
        $ready = $false
        for ($attempt = 0; $attempt -lt 45; $attempt++) {
            $health = & docker inspect --format '{{.State.Health.Status}}' $id 2>$null
            if ($health -eq 'healthy') { $ready = $true; break }
            if ($health -eq 'unhealthy') { break }
            Start-Sleep -Seconds 2
        }
        if (!$ready) { throw "$service did not become healthy. Check its local Docker logs before testing the app." }
        Write-Host "$service is healthy."
    }
    Write-Host 'Backend update complete. Existing Gmail settings, database volumes and tunnel were retained.'
    Write-Host 'Photo recognition remains disabled unless GEMINI_VISION_ENABLED=true is explicitly configured after model verification.'
} catch {
    Write-Host ("Update failed: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
