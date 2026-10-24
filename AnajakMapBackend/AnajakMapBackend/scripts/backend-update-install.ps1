# Source overlay only: never initialize credentials or run Docker here.
function ConvertTo-InitializedProjectRoot([string]$Path) {
    if (!$Path) { return $null }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\', '/') }
    $parent = Split-Path $full -Parent
    $projectParent = if ($parent) { Split-Path $parent -Parent } else { $null }
    foreach ($candidate in @($full, $projectParent)) {
        if (!$candidate) { continue }
        $backend = Join-Path $candidate 'AnajakMapBackend/AnajakMapBackend'
        $valid = $true
        foreach ($marker in @('.env', 'compose.yml', 'pom.xml')) {
            if (!(Test-Path -LiteralPath (Join-Path $backend $marker) -PathType Leaf)) { $valid = $false }
        }
        if ($valid) { return [IO.Path]::GetFullPath($candidate).TrimEnd('\', '/') }
    }
    return $null
}

function Get-BackendUpdateTarget {
    param([string]$SourceRoot, [string]$HostingRoot, [string[]]$RecordedBackendFolders = @())
    if ($HostingRoot) {
        $explicit = ConvertTo-InitializedProjectRoot $HostingRoot
        if (!$explicit) { throw 'The specified hosting folder must contain the initialized backend .env, compose.yml and pom.xml.' }
        return $explicit
    }
    $candidates = @()
    $ancestor = [IO.Path]::GetFullPath($SourceRoot)
    while ($ancestor) {
        $found = ConvertTo-InitializedProjectRoot $ancestor
        if ($found -and $candidates -notcontains $found) { $candidates += $found }
        $ancestor = Split-Path $ancestor -Parent
    }
    foreach ($folder in $RecordedBackendFolders) {
        $found = ConvertTo-InitializedProjectRoot $folder
        if ($found -and $candidates -notcontains $found) { $candidates += $found }
    }
    if ($candidates.Count -eq 0) { throw 'No initialized hosting checkout found. Restore its original .env or specify -HostingRoot with the existing project folder.' }
    if ($candidates.Count -ne 1) { throw ('Multiple initialized checkouts found. Specify -HostingRoot explicitly: ' + ($candidates -join '; ')) }
    return $candidates[0]
}

function Assert-BackendUpdatePath([string]$Root, [string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (!$full.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Update path escapes its project folder.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Update path contains a junction or symlink: $cursor" }
        }
        $cursor = Split-Path $cursor -Parent
    }
}

function Install-BackendUpdateSources {
    param([string]$SourceRoot, [string]$TargetRoot, [switch]$CheckOnly)
    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
    $target = ConvertTo-InitializedProjectRoot $TargetRoot
    if (!$target) { throw 'The update target is not an initialized backend project.' }
    if ($source -eq $target) { throw 'Source overlay requires a different source folder.' }
    $manifest = Join-Path $source 'backend-update-files.txt'
    Assert-BackendUpdatePath $source $manifest
    if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Source manifest missing. Use the complete updated patch ZIP or copy the update into the existing checkout first.' }
    $files = @([IO.File]::ReadAllLines($manifest) | Where-Object { $_.Trim() })
    if ($files.Count -eq 0 -or $files.Count -gt 250) { throw 'Invalid backend source manifest.' }
    $seen = @()
    $validated = @()
    $prefix = 'AnajakMapBackend/AnajakMapBackend/'
    foreach ($entry in $files) {
        if ($entry -ne $entry.Trim() -or $entry.Contains('\') -or [IO.Path]::IsPathRooted($entry) -or $entry -match '(^|/)\.{1,2}(/|$)') { throw "Unsafe update manifest path: $entry" }
        $allowed = $entry -in @('Update App Backend.cmd', 'APP_UPDATE_SETUP.md', 'APP_AUDIT.md', 'backend-update-files.txt')
        if ($entry.StartsWith($prefix, [StringComparison]::Ordinal)) {
            $relative = $entry.Substring($prefix.Length)
            $allowed = $relative -match '^[a-z-]+/src/(main|test)/java/[A-Za-z0-9_/]+\.java$' -or
                $relative -match '^scripts/[a-z0-9-]+\.ps1$' -or
                $relative -in @('compose.local.yml', 'deploy/laptop/README.md')
        }
        if (!$allowed -or $seen -contains $entry) { throw "Unapproved or duplicate backend update file: $entry" }
        $seen += $entry
        $from = Join-Path $source $entry
        $to = Join-Path $target $entry
        Assert-BackendUpdatePath $source $from
        Assert-BackendUpdatePath $target $to
        if (!(Test-Path -LiteralPath $from -PathType Leaf)) { throw "Patch source missing: $entry. No files were copied." }
        if ((Test-Path -LiteralPath $to) -and !(Test-Path -LiteralPath $to -PathType Leaf)) { throw "Update destination is not a file: $entry" }
        $validated += [pscustomobject]@{ Entry = $entry; From = $from; To = $to }
    }
    $backupFolder = Join-Path $target '.local/backend-update-backups'
    Assert-BackendUpdatePath $target $backupFolder
    if ($CheckOnly) { return [pscustomobject]@{ TargetRoot = $target; BackupPath = $null; FileCount = $validated.Count } }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $backupFolder -Force > $null
    $backupPath = Join-Path $backupFolder ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.zip')
    $archive = [IO.Compression.ZipFile]::Open($backupPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $validated) {
            if (Test-Path -LiteralPath $file.To -PathType Leaf) {
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.To, $file.Entry) > $null
            }
        }
    } finally { $archive.Dispose() }
    foreach ($file in $validated) {
        $parent = Split-Path $file.To -Parent
        New-Item -ItemType Directory -Path $parent -Force > $null
        Copy-Item -LiteralPath $file.From -Destination $file.To -Force
        if ((Get-FileHash -LiteralPath $file.From -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $file.To -Algorithm SHA256).Hash) { throw "Copy verification failed: $($file.Entry). Original sources are in $backupPath" }
    }
    return [pscustomobject]@{ TargetRoot = $target; BackupPath = $backupPath; FileCount = $validated.Count }
}
