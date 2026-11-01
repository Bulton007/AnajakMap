param([switch]$Public)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'ready-backend.ps1')
    $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    Start-AnajakReadyBackend -ProjectRoot $root -Public:$Public
    exit 0
} catch {
    Write-Host "Backend startup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'No database volumes were removed and no replacement credentials were generated.'
    exit 1
}
