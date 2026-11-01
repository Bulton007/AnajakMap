$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fresh-backend.ps1')
$before = (Get-Location).Path
try {
    $backend = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
    $null = Read-AnajakFreshConfiguration $backend
    Set-Location -LiteralPath $backend
    $compose = @(Get-AnajakFreshComposeArguments -Backend $backend -Runtime)
    Invoke-AnajakFreshDocker ($compose + @('stop'))
    Write-Host 'Stopped only anajakmap-v12 services. Its configuration and data volumes are retained.'
} catch {
    Write-Host 'The fresh backend could not be stopped. No volumes or credentials were removed.' -ForegroundColor Red
    exit 1
} finally { Set-Location -LiteralPath $before }
