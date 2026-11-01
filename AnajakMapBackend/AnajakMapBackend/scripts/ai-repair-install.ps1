# Source repair only. No service, database, credential or provider mutation.
$script:AnajakAiRepairVersion = '2026.10.28.1'

function Get-AnajakAiRepairFiles {
    return @(
        'Update AI.cmd', 'Check AI.cmd', 'AI_SETUP_REPAIR.md',
        'AnajakMapBackend/AnajakMapBackend/scripts/update-ai.ps1',
        'AnajakMapBackend/AnajakMapBackend/scripts/ai-settings.ps1',
        'AnajakMapBackend/AnajakMapBackend/scripts/ai-diagnostics.ps1',
        'AnajakMapBackend/AnajakMapBackend/scripts/check-ai.ps1',
        'AnajakMapBackend/AnajakMapBackend/scripts/test-ai-settings.ps1',
        'AnajakMapBackend/AnajakMapBackend/scripts/test-ai-update-environment.ps1'
    )
}

function Assert-AnajakAiRepairPath([string]$Root, [string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (!$full.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'AI repair path escapes its source or hosting folder.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'AI repair refuses a junction or symbolic link in its source or hosting path.' }
        }
        $cursor = Split-Path $cursor -Parent
    }
}

function ConvertTo-AnajakAiHostingRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or ![IO.Path]::IsPathRooted($Path)) { return $null }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.TrimEnd('\','/') -eq [IO.Path]::GetPathRoot($full).TrimEnd('\','/')) { return $null }
    $full = $full.TrimEnd('\','/')
    $parent = Split-Path $full -Parent
    $outer = if ($parent) { Split-Path $parent -Parent } else { $null }
    foreach ($candidate in @($full,$outer)) {
        if (!$candidate) { continue }
        $backend = Join-Path $candidate 'AnajakMapBackend/AnajakMapBackend'
        $valid = $true
        foreach ($marker in @('.env','compose.yml','pom.xml')) {
            if (!(Test-Path -LiteralPath (Join-Path $backend $marker) -PathType Leaf)) { $valid = $false }
        }
        if ($valid) {
            Assert-AnajakAiRepairPath $candidate (Join-Path $backend '.env')
            return [IO.Path]::GetFullPath($candidate).TrimEnd('\','/')
        }
    }
    return $null
}

function Get-AnajakAiDockerFolders {
    # Only Compose labels are inspected. Never read Config.Env or raw logs.
    $previousPreference = $ErrorActionPreference
    $paths = @()
    try {
        $ErrorActionPreference = 'Continue'
        $ids = @(& docker ps -a --filter 'label=com.docker.compose.project=anajakmap' --filter 'label=com.docker.compose.service=ai-guide-service' --format '{{.ID}}' 2>$null)
        if ($LASTEXITCODE -ne 0) { return @() }
        foreach ($id in ($ids | Select-Object -First 8)) {
            if ([string]$id -notmatch '\A[a-fA-F0-9]{12,64}\z') { continue }
            $labelsJson = @(& docker inspect --format '{{json .Config.Labels}}' ([string]$id) 2>$null)
            if ($LASTEXITCODE -eq 0 -and $labelsJson.Count -gt 0) {
                $labels = ($labelsJson -join "`n") | ConvertFrom-Json
                $folder = [string]$labels.'com.docker.compose.project.working_dir'
                if (![string]::IsNullOrWhiteSpace($folder)) { $paths += $folder.Trim() }
            }
        }
    } catch { return @() }
    finally { $ErrorActionPreference = $previousPreference }
    return $paths
}

function Get-AnajakAiRepairCandidates {
    param([string]$SourceRoot, [string[]]$RecordedBackendFolders = @())
    $candidates = @()
    $ancestor = [IO.Path]::GetFullPath($SourceRoot)
    while ($ancestor) {
        $candidate = ConvertTo-AnajakAiHostingRoot $ancestor
        if ($candidate -and $candidates -notcontains $candidate) { $candidates += $candidate }
        $ancestor = Split-Path $ancestor -Parent
    }
    foreach ($folder in $RecordedBackendFolders) {
        $candidate = ConvertTo-AnajakAiHostingRoot $folder
        if ($candidate -and $candidates -notcontains $candidate) { $candidates += $candidate }
    }
    return $candidates
}

function Resolve-AnajakAiRepairTarget {
    param([string]$SourceRoot, [string]$HostingRoot, [string[]]$RecordedBackendFolders = @())
    if ($HostingRoot) {
        $target = ConvertTo-AnajakAiHostingRoot $HostingRoot
        if (!$target) { throw 'The hosting folder must be an existing initialized project containing AnajakMapBackend/AnajakMapBackend/.env, compose.yml and pom.xml. No credentials were created.' }
        return $target
    }
    $candidates = @(Get-AnajakAiRepairCandidates $SourceRoot $RecordedBackendFolders)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) { throw 'More than one initialized hosting project was found. Specify -HostingRoot with the exact project running your public backend.' }
    throw 'No initialized hosting project was found. Specify -HostingRoot with the existing project containing its original .env. This installer does not initialize credentials.'
}

function Install-AnajakAiRepair {
    param([string]$SourceRoot, [string]$HostingRoot)
    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
    $target = Resolve-AnajakAiRepairTarget -SourceRoot $source -HostingRoot $HostingRoot
    $manifestPath = Join-Path $source 'ai-repair-manifest.json'
    Assert-AnajakAiRepairPath $source $manifestPath
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'AI repair manifest is missing. Extract the complete version-2 repair ZIP before running Install AI Repair.cmd.' }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($manifest.version -ne $script:AnajakAiRepairVersion) { throw 'AI repair version mismatch. Extract the complete current repair ZIP into a new folder.' }
    $allowed = @(Get-AnajakAiRepairFiles)
    $records = @($manifest.files)
    if ($records.Count -ne $allowed.Count) { throw 'AI repair payload manifest has an unexpected file count.' }
    $seen = @()
    $validated = @()
    foreach ($record in $records) {
        $entry = [string]$record.path
        if ($entry -notin $allowed -or $seen -contains $entry -or [string]$record.sha256 -notmatch '\A[a-fA-F0-9]{64}\z') { throw 'AI repair payload manifest contains an unapproved path, duplicate or invalid hash.' }
        $seen += $entry
        $from = Join-Path $source $entry
        $to = Join-Path $target $entry
        Assert-AnajakAiRepairPath $source $from
        Assert-AnajakAiRepairPath $target $to
        if (!(Test-Path -LiteralPath $from -PathType Leaf)) { throw "AI repair payload file is missing: $entry" }
        if ((Test-Path -LiteralPath $to) -and !(Test-Path -LiteralPath $to -PathType Leaf)) { throw "AI repair destination is not a regular file: $entry" }
        $hash = (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash
        if ($hash -ne [string]$record.sha256) { throw "AI repair payload verification failed: $entry. No files were copied." }
        $validated += [pscustomobject]@{Entry=$entry;From=$from;To=$to;Hash=$hash;Replace=($from -ne $to)}
    }
    $scriptPath = Join-Path $source 'AnajakMapBackend/AnajakMapBackend/scripts/update-ai.ps1'
    $scriptText = [IO.File]::ReadAllText($scriptPath)
    if (!$scriptText.Contains("AnajakAiSetupVersion = '$script:AnajakAiRepairVersion'")) { throw 'The repair payload contains an outdated AI setup script. No files were copied.' }
    $envPath = Join-Path $target 'AnajakMapBackend/AnajakMapBackend/.env'
    $beforeEnv = (Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash
    $backup = $null
    $changes = @($validated | Where-Object {$_.Replace})
    if ($changes.Count -gt 0) {
        $backup = Join-Path $target ('.local/ai-setup-repair-backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
        Assert-AnajakAiRepairPath $target $backup
        New-Item -ItemType Directory -Path $backup -Force > $null
        foreach ($file in $changes) {
            if (Test-Path -LiteralPath $file.To -PathType Leaf) {
                $saved = Join-Path $backup $file.Entry
                New-Item -ItemType Directory -Path (Split-Path $saved -Parent) -Force > $null
                Copy-Item -LiteralPath $file.To -Destination $saved -Force
            }
        }
        foreach ($file in $changes) {
            New-Item -ItemType Directory -Path (Split-Path $file.To -Parent) -Force > $null
            Copy-Item -LiteralPath $file.From -Destination $file.To -Force
        }
    }
    foreach ($file in $validated) {
        if ((Get-FileHash -LiteralPath $file.To -Algorithm SHA256).Hash -ne $file.Hash) { throw "Installed AI repair verification failed: $($file.Entry). Sources are backed up at $backup" }
    }
    if ((Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash -ne $beforeEnv) { throw 'The original .env changed while installing sources. Stop and inspect the hosting project before continuing.' }
    return [pscustomobject]@{Version=$script:AnajakAiRepairVersion;TargetRoot=$target;ScriptPath=(Join-Path $target 'AnajakMapBackend/AnajakMapBackend/scripts/update-ai.ps1');BackupPath=$backup;FileCount=$validated.Count;EnvPreserved=$true}
}
