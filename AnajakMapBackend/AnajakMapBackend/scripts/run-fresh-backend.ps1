param([switch]$Public)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'fresh-backend.ps1')
    $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    Start-AnajakFreshBackend -ProjectRoot $root -Public:$Public
    exit 0
} catch {
    Write-Host "Version 12 startup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'No old backend containers or volumes were removed, and no credentials were generated or replaced.'
    exit 1
}
