param([string]$HostingRoot, [string]$SourceRoot, [switch]$InstallOnly, [switch]$NonInteractive)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'ai-repair-install.ps1')
    if (!$SourceRoot) { $SourceRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent }
    Write-Host "AnajakMap AI Setup Repair Installer v$script:AnajakAiRepairVersion"
    Write-Host 'This installer copies reviewed AI setup sources only. It does not initialize or replace .env, database data or credentials.'
    if (!$HostingRoot) {
        $folders = @(Get-AnajakAiDockerFolders)
        $candidates = @(Get-AnajakAiRepairCandidates -SourceRoot $SourceRoot -RecordedBackendFolders $folders)
        if ($candidates.Count -eq 1) { $HostingRoot = $candidates[0] }
        elseif ($NonInteractive) { throw 'No unique initialized hosting project was found. Specify -HostingRoot with the exact existing project folder.' }
        else {
            if ($candidates.Count -gt 1) {
                Write-Host 'More than one initialized hosting project was found:'
                foreach ($candidate in $candidates) { Write-Host "  $candidate" }
            }
            Write-Host 'Enter the existing project root used to start your public backend (the folder containing Start Backend.cmd and AnajakMapBackend).'
            $HostingRoot = (Read-Host 'Existing hosting project folder').Trim().Trim('"')
            if ([string]::IsNullOrWhiteSpace($HostingRoot)) { throw 'A hosting project folder is required. No sources or credentials were changed.' }
        }
    }
    $result = Install-AnajakAiRepair -SourceRoot $SourceRoot -HostingRoot $HostingRoot
    Write-Host "Installed and hash-verified AI setup v$($result.Version)" -ForegroundColor Green
    Write-Host "Hosting project: $($result.TargetRoot)"
    Write-Host "Exact updated script: $($result.ScriptPath)"
    if ($result.BackupPath) { Write-Host "Previous setup sources backed up: $($result.BackupPath)" }
    Write-Host 'Original .env preserved. No backend services were changed by the installer.'
    if ($InstallOnly) { exit 0 }
    Write-Host 'Opening that exact updated setup script now. Enter your Gemini key only in its hidden local prompt.'
    & $result.ScriptPath
    exit $LASTEXITCODE
} catch {
    Write-Host "AI repair failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
