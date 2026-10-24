# Runs without Docker, network access, real credentials or service changes.
# Compatible with Windows PowerShell 5.1. Fixtures are retained for inspection.
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'backend-update-install.ps1'
for ($attempt = 0; $attempt -lt 10 -and !(Test-Path -LiteralPath $helper -PathType Leaf); $attempt++) {
    Start-Sleep -Milliseconds 200
}
if (!(Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'Backend update installer helper is missing.' }
. $helper

$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:suiteRoot = Join-Path $workspace ('.local/update-installer-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:suiteRoot) > $null
$script:originalNormalize = (Get-Item Function:\ConvertTo-InitializedProjectRoot).ScriptBlock

# The actual checkout above .local is initialized. Exclude that live ancestor
# from fixture discovery while executing the original normalization for every
# test path. This prevents fixture tests from depending on or selecting it.
function ConvertTo-InitializedProjectRoot([string]$Path) {
    if (!$Path) { return $null }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $boundary = $script:suiteRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($full -ne $script:suiteRoot -and !$full.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    $result = & $script:originalNormalize $Path
    if ($result -and ($result -eq $script:suiteRoot -or $result.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase))) { return $result }
    return $null
}

$script:passed = 0
$script:failures = @()
$backendRelative = 'AnajakMapBackend/AnajakMapBackend'
$javaRelative = "$backendRelative/ai-guide-service/src/main/java/com/anajakmap/ai/Guide.java"

function Write-FixtureFile([string]$Path, [string]$Content) {
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) > $null
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding $false))
}

function New-Fixture([string]$Name, [switch]$Initialized) {
    $root = Join-Path $script:suiteRoot ($Name + '-' + [guid]::NewGuid().ToString('N'))
    $backend = Join-Path $root $backendRelative
    [IO.Directory]::CreateDirectory($backend) > $null
    Write-FixtureFile (Join-Path $backend 'compose.yml') 'services: {}'
    Write-FixtureFile (Join-Path $backend 'pom.xml') '<project />'
    if ($Initialized) { Write-FixtureFile (Join-Path $backend '.env') 'TEST_ONLY_CONFIG=unchanged' }
    return $root
}

function Set-FixtureManifest([string]$Root, [string[]]$Entries) {
    Write-FixtureFile (Join-Path $Root 'backend-update-files.txt') (($Entries -join "`r`n") + "`r`n")
}

function New-Patch([string]$Name) {
    $root = New-Fixture $Name
    Write-FixtureFile (Join-Path $root $javaRelative) 'new Java source'
    Write-FixtureFile (Join-Path $root 'APP_AUDIT.md') 'new audit'
    Set-FixtureManifest $root @($javaRelative, 'APP_AUDIT.md', 'backend-update-files.txt')
    return $root
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) { throw $Message }
}

function Assert-PathEqual([string]$Expected, [string]$Actual) {
    Assert-Equal ([IO.Path]::GetFullPath($Expected).TrimEnd('\', '/')) ([IO.Path]::GetFullPath($Actual).TrimEnd('\', '/')) 'Selected the wrong project folder.'
}

function Expect-Failure([scriptblock]$Action) {
    $threw = $false
    try { & $Action > $null } catch { $threw = $true }
    Assert-True $threw 'Expected the unsafe or invalid update to be rejected.'
}

function Get-FixtureSnapshot([string]$Root) {
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($Root.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    ) -join "`n"
}

function Invoke-InstallerTest([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
        Write-Host "PASS $Name" -ForegroundColor Green
    } catch {
        $script:failures += $Name + ': ' + $_.Exception.Message
        Write-Host ("FAIL $Name - " + $_.Exception.Message) -ForegroundColor Red
    }
}

function Test-RejectedManifest([string]$Name, [string[]]$Entries) {
    $source = New-Patch ('unsafe-' + $Name)
    $target = New-Fixture ('unsafe-target-' + $Name) -Initialized
    Write-FixtureFile (Join-Path $target 'APP_AUDIT.md') 'original audit'
    Set-FixtureManifest $source $Entries
    $before = Get-FixtureSnapshot $target
    Expect-Failure { Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target }
    Assert-Equal $before (Get-FixtureSnapshot $target) 'Rejected manifest changed target files.'
    Assert-True (!(Test-Path -LiteralPath (Join-Path $target '.local/backend-update-backups'))) 'Rejected manifest created a backup or wrote files.'
}

try {
    Invoke-InstallerTest 'Find an initialized ancestor from a nested .local update folder' {
        $hostRoot = New-Fixture 'ancestor-host' -Initialized
        $source = Join-Path $hostRoot '.local/unpacked/AnajakMap-update'
        [IO.Directory]::CreateDirectory($source) > $null
        Assert-PathEqual $hostRoot (Get-BackendUpdateTarget -SourceRoot $source -RecordedBackendFolders @())
    }
    Invoke-InstallerTest 'Use the Docker-recorded backend directory and deduplicate equivalent roots' {
        $hostRoot = New-Fixture 'docker-host' -Initialized
        $source = New-Patch 'docker-source'
        $backend = Join-Path $hostRoot $backendRelative
        Assert-PathEqual $hostRoot (Get-BackendUpdateTarget -SourceRoot $source -RecordedBackendFolders @($backend, $hostRoot, $backend))
    }
    Invoke-InstallerTest 'Reject ambiguous initialized hosting checkouts' {
        $first = New-Fixture 'ambiguous-one' -Initialized
        $second = New-Fixture 'ambiguous-two' -Initialized
        $source = New-Patch 'ambiguous-source'
        Expect-Failure { Get-BackendUpdateTarget -SourceRoot $source -RecordedBackendFolders @($first, $second) }
    }
    Invoke-InstallerTest 'An explicit hosting project root wins over discovered alternatives' {
        $first = New-Fixture 'explicit-one' -Initialized
        $second = New-Fixture 'explicit-two' -Initialized
        $source = New-Patch 'explicit-source'
        Assert-PathEqual $second (Get-BackendUpdateTarget -SourceRoot $source -HostingRoot $second -RecordedBackendFolders @($first))
    }
    Invoke-InstallerTest 'Accept an explicit backend directory' {
        $target = New-Fixture 'explicit-backend' -Initialized
        $source = New-Patch 'explicit-backend-source'
        Assert-PathEqual $target (Get-BackendUpdateTarget -SourceRoot $source -HostingRoot (Join-Path $target $backendRelative))
    }
    Invoke-InstallerTest 'Reject missing original private configuration' {
        $source = New-Patch 'uninitialized-source'
        $target = New-Fixture 'uninitialized-target'
        Expect-Failure { Get-BackendUpdateTarget -SourceRoot $source -RecordedBackendFolders @($target) }
        Expect-Failure { Get-BackendUpdateTarget -SourceRoot $source -HostingRoot $target }
        Expect-Failure { Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target }
    }
    Invoke-InstallerTest 'Require compose.yml and pom.xml as well as .env' {
        $source = New-Patch 'missing-markers-source'
        foreach ($marker in @('compose.yml', 'pom.xml')) {
            $target = New-Fixture ('missing-' + $marker) -Initialized
            # A single named fixture file is removed; no recursive delete occurs.
            Remove-Item -LiteralPath (Join-Path (Join-Path $target $backendRelative) $marker)
            Expect-Failure { Get-BackendUpdateTarget -SourceRoot $source -HostingRoot $target }
        }
    }
    Invoke-InstallerTest 'CheckOnly validates without target writes or backups' {
        $source = New-Patch 'dry-source'
        $target = New-Fixture 'dry-target' -Initialized
        Write-FixtureFile (Join-Path $target 'APP_AUDIT.md') 'existing audit'
        $before = Get-FixtureSnapshot $target
        $result = Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target -CheckOnly
        Assert-PathEqual $target $result.TargetRoot
        Assert-Equal 3 $result.FileCount 'Dry run reported the wrong file count.'
        Assert-True (!$result.BackupPath) 'Dry run returned a backup path.'
        Assert-Equal $before (Get-FixtureSnapshot $target) 'Dry run changed target files.'
        Assert-True (!(Test-Path -LiteralPath (Join-Path $target '.local'))) 'Dry run created target directories.'
    }
    Invoke-InstallerTest 'Install preserves .env and unrelated files and backs up overwritten files' {
        $source = New-Patch 'install-source'
        $target = New-Fixture 'install-target' -Initialized
        $envPath = Join-Path (Join-Path $target $backendRelative) '.env'
        $originalEnvHash = (Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash
        Write-FixtureFile (Join-Path $target $javaRelative) 'original Java source'
        Write-FixtureFile (Join-Path $target 'APP_AUDIT.md') 'original audit'
        Write-FixtureFile (Join-Path $target "$backendRelative/ai-guide-service/src/main/java/com/anajakmap/ai/Unrelated.java") 'unrelated source'
        $result = Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target
        Assert-PathEqual $target $result.TargetRoot
        Assert-Equal 3 $result.FileCount 'Installed the wrong file count.'
        Assert-Equal 'new Java source' ([IO.File]::ReadAllText((Join-Path $target $javaRelative))) 'Java update was not copied.'
        Assert-Equal 'new audit' ([IO.File]::ReadAllText((Join-Path $target 'APP_AUDIT.md'))) 'Audit update was not copied.'
        Assert-Equal $originalEnvHash ((Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash) 'Original .env changed.'
        Assert-Equal 'unrelated source' ([IO.File]::ReadAllText((Join-Path $target "$backendRelative/ai-guide-service/src/main/java/com/anajakmap/ai/Unrelated.java"))) 'Unrelated source changed.'
        Assert-True (Test-Path -LiteralPath $result.BackupPath -PathType Leaf) 'No backup ZIP was produced.'
        Assert-True ($result.BackupPath.StartsWith((Join-Path $target '.local/backend-update-backups'), [StringComparison]::OrdinalIgnoreCase)) 'Backup escaped its project folder.'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($result.BackupPath)
        try {
            Assert-Equal 2 $zip.Entries.Count 'Backup should contain only the two overwritten files.'
            foreach ($expected in @{ $javaRelative = 'original Java source'; 'APP_AUDIT.md' = 'original audit' }.GetEnumerator()) {
                $entry = $zip.GetEntry($expected.Key)
                Assert-True ($null -ne $entry) 'An overwritten file is missing from the backup.'
                $reader = New-Object IO.StreamReader($entry.Open())
                try { Assert-Equal $expected.Value $reader.ReadToEnd() 'Backup does not contain the original content.' } finally { $reader.Dispose() }
            }
            Assert-True ($null -eq $zip.GetEntry("$backendRelative/.env")) 'Private configuration entered the source backup.'
        } finally { $zip.Dispose() }
    }
    Invoke-InstallerTest 'Allow the reviewed Java, scripts, compose, documentation and launcher paths' {
        $source = New-Patch 'allowed-source'
        $target = New-Fixture 'allowed-target' -Initialized
        $entries = @(
            $javaRelative,
            "$backendRelative/discovery-service/src/test/java/com/anajakmap/discovery/FixtureTest.java",
            "$backendRelative/scripts/update-fixture.ps1",
            "$backendRelative/compose.local.yml",
            "$backendRelative/deploy/laptop/README.md",
            'Update App Backend.cmd', 'APP_UPDATE_SETUP.md', 'APP_AUDIT.md', 'backend-update-files.txt'
        )
        foreach ($entry in $entries) { Write-FixtureFile (Join-Path $source $entry) 'reviewed source fixture' }
        Set-FixtureManifest $source $entries
        $result = Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target -CheckOnly
        Assert-Equal $entries.Count $result.FileCount 'A reviewed file type was rejected.'
    }
    Invoke-InstallerTest 'Prevalidate every source before any backup or copy' {
        $source = New-Patch 'missing-file-source'
        $target = New-Fixture 'missing-file-target' -Initialized
        Write-FixtureFile (Join-Path $target 'APP_AUDIT.md') 'original audit'
        Set-FixtureManifest $source @('APP_AUDIT.md', "$backendRelative/scripts/not-present.ps1")
        $before = Get-FixtureSnapshot $target
        Expect-Failure { Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target }
        Assert-Equal $before (Get-FixtureSnapshot $target) 'Missing later source caused a partial update.'
        Assert-True (!(Test-Path -LiteralPath (Join-Path $target '.local'))) 'Prevalidation failure created a backup.'
    }
    Invoke-InstallerTest 'Reject traversal in a manifest before writes' { Test-RejectedManifest 'traversal' @('APP_AUDIT.md', '../APP_AUDIT.md') }
    Invoke-InstallerTest 'Reject backslash paths in a manifest' { Test-RejectedManifest 'backslash' @('APP_AUDIT.md', 'AnajakMapBackend\AnajakMapBackend\scripts\update-fixture.ps1') }
    Invoke-InstallerTest 'Reject rooted paths in a manifest' { Test-RejectedManifest 'rooted' @('APP_AUDIT.md', (Join-Path $script:suiteRoot 'absolute.txt')) }
    Invoke-InstallerTest 'Reject .env in a manifest' { Test-RejectedManifest 'env' @('APP_AUDIT.md', "$backendRelative/.env") }
    Invoke-InstallerTest 'Reject signing keys in a manifest' { Test-RejectedManifest 'signing-key' @('APP_AUDIT.md', 'flutter_app/android/key.properties') }
    Invoke-InstallerTest 'Reject unreviewed configuration in a manifest' { Test-RejectedManifest 'private-json' @('APP_AUDIT.md', 'flutter_app/config/production.local.json') }
    Invoke-InstallerTest 'Reject duplicate manifest entries' { Test-RejectedManifest 'duplicate' @('APP_AUDIT.md', 'APP_AUDIT.md') }
    Invoke-InstallerTest 'Reject whitespace around manifest paths' { Test-RejectedManifest 'whitespace' @('APP_AUDIT.md', ' APP_AUDIT.md') }
    Invoke-InstallerTest 'Reject empty manifest' { Test-RejectedManifest 'empty' @() }
    Invoke-InstallerTest 'Reject manifest without an explicit reviewed list' {
        $source = New-Fixture 'no-manifest-source'
        $target = New-Fixture 'no-manifest-target' -Initialized
        Expect-Failure { Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target }
    }
    Invoke-InstallerTest 'Reject source files reached through a junction' {
        $source = New-Patch 'source-junction'
        $target = New-Fixture 'source-junction-target' -Initialized
        $outside = Join-Path $script:suiteRoot ('junction-payload-' + [guid]::NewGuid().ToString('N'))
        Write-FixtureFile (Join-Path $outside 'Guide.java') 'linked source'
        $link = Join-Path $source "$backendRelative/ai-guide-service/src/main/java/linked"
        [IO.Directory]::CreateDirectory((Split-Path $link -Parent)) > $null
        New-Item -ItemType Junction -Path $link -Value $outside > $null
        Set-FixtureManifest $source @('APP_AUDIT.md', "$backendRelative/ai-guide-service/src/main/java/linked/Guide.java")
        $before = Get-FixtureSnapshot $target
        Expect-Failure { Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target }
        Assert-Equal $before (Get-FixtureSnapshot $target) 'Source junction caused target writes.'
    }
    Invoke-InstallerTest 'Reject destination directories reached through a junction' {
        $source = New-Patch 'target-junction-source'
        $target = New-Fixture 'target-junction' -Initialized
        $outside = Join-Path $script:suiteRoot ('junction-destination-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($outside) > $null
        $link = Join-Path $target "$backendRelative/ai-guide-service/src/main/java/linked"
        [IO.Directory]::CreateDirectory((Split-Path $link -Parent)) > $null
        New-Item -ItemType Junction -Path $link -Value $outside > $null
        $entry = "$backendRelative/ai-guide-service/src/main/java/linked/Guide.java"
        Write-FixtureFile (Join-Path $source $entry) 'must not escape'
        Set-FixtureManifest $source @('APP_AUDIT.md', $entry)
        Expect-Failure { Install-BackendUpdateSources -SourceRoot $source -TargetRoot $target }
        Assert-True (!(Test-Path -LiteralPath (Join-Path $outside 'Guide.java'))) 'Update followed a target junction.'
        Assert-True (!(Test-Path -LiteralPath (Join-Path $target 'APP_AUDIT.md'))) 'Target junction caused partial writes.'
    }
} finally {
    Set-Item Function:\ConvertTo-InitializedProjectRoot -Value $script:originalNormalize
}

Write-Host ("`nInstaller regression tests: {0} passed, {1} failed." -f $script:passed, $script:failures.Count)
Write-Host "Isolated fixtures retained at: $script:suiteRoot"
if ($script:failures.Count -gt 0) { throw ($script:failures -join "`n") }
exit 0
