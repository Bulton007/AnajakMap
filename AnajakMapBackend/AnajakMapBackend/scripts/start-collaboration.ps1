[CmdletBinding()]
param(
    [string]$Backend = 'C:\AnajakMap-Backend-Fresh-v12-PRIVATE\AnajakMapBackend\AnajakMapBackend'
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backendRoot = (Resolve-Path -LiteralPath $Backend).Path
$configuration = @('compose.yml', 'compose.media-source.yml', 'compose.local.yml',
    'compose.runtime.yml', 'compose.laptop.yml', 'compose.fresh.yml')
foreach ($file in $configuration + @('.env')) {
    if (!(Test-Path -LiteralPath (Join-Path $backendRoot $file) -PathType Leaf)) {
        throw "The configured local backend is missing $file."
    }
}
$images = @('anajakmap/identity-service:collaboration-v2',
    'anajakmap/discovery-service:journey-v1',
    'anajakmap/trip-service:collaboration-v4',
    'anajakmap/notification-service:collaboration-v2',
    'anajakmap/gateway-service:collaboration-v4')
foreach ($image in $images) {
    & docker image inspect $image --format '{{.Id}}' *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "The tested image $image is missing. Build the collaboration services before starting."
    }
}
$compose = @('compose', '--project-directory', $backendRoot, '--env-file',
    (Join-Path $backendRoot '.env'), '-p', 'anajakmap-v12')
foreach ($file in $configuration) {
    $compose += @('-f', (Join-Path $backendRoot $file))
}
$compose += @('-f', (Join-Path $sourceRoot 'compose.collaboration.yml'))
$priorRoot = $env:ANAJAK_COLLABORATION_ROOT
try {
    $env:ANAJAK_COLLABORATION_ROOT = $sourceRoot.Replace('\', '/')
    & docker @compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'The collaboration configuration is invalid.' }
    & docker @compose up -d --no-deps --no-build identity-service trip-service notification-service gateway-service discovery-service nginx
    if ($LASTEXITCODE -ne 0) { throw 'The collaboration services did not start.' }
    Write-Host 'Collaboration services started. The local app API is http://127.0.0.1:18090/api/v1/.'
}
finally {
    $env:ANAJAK_COLLABORATION_ROOT = $priorRoot
}
