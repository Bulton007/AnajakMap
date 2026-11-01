$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai-repair-install.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('anajak-ai-repair-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force > $null
$passed = 0
function Assert-Repair([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "AI repair installer regression failed: $Name" }
    $script:passed++
}
function Assert-RepairThrows([scriptblock]$Operation,[string]$Name) {
    $failed = $false
    try { & $Operation > $null } catch { $failed = $true }
    Assert-Repair $failed $Name
}
function New-TestHosting([string]$Name) {
    $root = Join-Path $fixture $Name
    $backend = Join-Path $root 'AnajakMapBackend/AnajakMapBackend'
    New-Item -ItemType Directory -Path (Join-Path $backend 'scripts') -Force > $null
    foreach ($name in @('.env','compose.yml','pom.xml')) { [IO.File]::WriteAllText((Join-Path $backend $name),'synthetic-only-unchanged') }
    return $root
}
function Save-TestManifest([string]$Root) {
    $records = @()
    foreach ($relative in @(Get-AnajakAiRepairFiles)) {
        $records += [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $Root $relative) -Algorithm SHA256).Hash}
    }
    [IO.File]::WriteAllText((Join-Path $Root 'ai-repair-manifest.json'),(@{version='2026.10.28.1';files=$records} | ConvertTo-Json -Depth 6))
}
$source = Join-Path $fixture 'Downloads/Extracted repair (& spaces!)'
New-Item -ItemType Directory -Path $source -Force > $null
foreach ($relative in @(Get-AnajakAiRepairFiles)) {
    $path = Join-Path $source $relative
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force > $null
    $text = if ($relative.EndsWith('/update-ai.ps1')) { '$script:AnajakAiSetupVersion = ''2026.10.28.1''' + "`r`n" + '$global:AnajakTestLaunchedScript = $PSCommandPath' + "`r`nexit 0" } else { 'synthetic-repaired-source:' + $relative }
    [IO.File]::WriteAllText($path,$text)
}
foreach ($helper in @('repair-ai-setup.ps1','ai-repair-install.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $helper) -Destination (Join-Path $source ('AnajakMapBackend/AnajakMapBackend/scripts/' + $helper)) }
Save-TestManifest $source
$target = New-TestHosting 'Existing hosting project (& spaces!)'
$targetBackend = Join-Path $target 'AnajakMapBackend/AnajakMapBackend'
$oldScript = Join-Path $targetBackend 'scripts/update-ai.ps1'
[IO.File]::WriteAllText($oldScript,'original-setup-source')
$envPath = Join-Path $targetBackend '.env'
$originalEnv = (Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash

Assert-Repair ((ConvertTo-AnajakAiHostingRoot $target) -eq $target) 'initialized project root accepted'
Assert-Repair ((ConvertTo-AnajakAiHostingRoot $targetBackend) -eq $target) 'initialized inner backend accepted'
Assert-Repair ($null -eq (ConvertTo-AnajakAiHostingRoot 'relative-folder')) 'relative hosting path rejected'
$driveRoot = [IO.Path]::GetPathRoot($target)
Push-Location $target
try { Assert-Repair ($null -eq (ConvertTo-AnajakAiHostingRoot $driveRoot)) 'drive root never resolves relative to current checkout' }
finally { Pop-Location }
Assert-Repair ((Resolve-AnajakAiRepairTarget -SourceRoot $source -RecordedBackendFolders @($targetBackend)) -eq $target) 'Docker working directory discovers initialized target'
Assert-RepairThrows { Resolve-AnajakAiRepairTarget -SourceRoot $source } 'uninitialized Downloads never initializes credentials'
$second = New-TestHosting 'Second hosting project'
Assert-RepairThrows { Resolve-AnajakAiRepairTarget -SourceRoot $source -RecordedBackendFolders @($targetBackend,(Join-Path $second 'AnajakMapBackend/AnajakMapBackend')) } 'ambiguous targets rejected'
Assert-Repair ((Resolve-AnajakAiRepairTarget -SourceRoot $source -HostingRoot $target -RecordedBackendFolders @($second)) -eq $target) 'explicit target resolves ambiguity'
Assert-RepairThrows { Assert-AnajakAiRepairPath $target (Join-Path $fixture 'outside.txt') } 'paths cannot escape target'
$uninitialized = New-TestHosting 'Missing private config'
Remove-Item -LiteralPath (Join-Path $uninitialized 'AnajakMapBackend/AnajakMapBackend/.env')
Assert-RepairThrows { Install-AnajakAiRepair -SourceRoot $source -HostingRoot $uninitialized } 'missing env refused'
Assert-Repair (!(Test-Path -LiteralPath (Join-Path $uninitialized 'Update AI.cmd'))) 'missing env failure made no source replacements'

$manifestPath = Join-Path $source 'ai-repair-manifest.json'
$originalManifest = [IO.File]::ReadAllText($manifestPath)
$bad = $originalManifest | ConvertFrom-Json
$bad.files[0].path = 'AnajakMapBackend/AnajakMapBackend/.env'
[IO.File]::WriteAllText($manifestPath,($bad | ConvertTo-Json -Depth 6))
Assert-RepairThrows { Install-AnajakAiRepair -SourceRoot $source -HostingRoot $target } 'private configuration path cannot enter manifest'
Assert-Repair ([IO.File]::ReadAllText($oldScript) -eq 'original-setup-source') 'bad manifest rejected before copying'
[IO.File]::WriteAllText($manifestPath,$originalManifest)
$payloadFile = Join-Path $source 'Update AI.cmd'
[IO.File]::AppendAllText($payloadFile,'tampered')
Assert-RepairThrows { Install-AnajakAiRepair -SourceRoot $source -HostingRoot $target } 'payload hash mismatch rejected'
Assert-Repair ([IO.File]::ReadAllText($oldScript) -eq 'original-setup-source') 'hash failure rejected before copying'
[IO.File]::WriteAllText($payloadFile,'synthetic-repaired-source:Update AI.cmd')
Save-TestManifest $source
$result = Install-AnajakAiRepair -SourceRoot $source -HostingRoot $target
Assert-Repair ($result.FileCount -eq 9 -and $result.Version -eq '2026.10.28.1') 'exact nine sources installed'
Assert-Repair ((Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash -eq $originalEnv) 'private env bytes unchanged'
Assert-Repair ([IO.File]::ReadAllText((Join-Path $result.BackupPath 'AnajakMapBackend/AnajakMapBackend/scripts/update-ai.ps1')) -eq 'original-setup-source') 'previous source backed up'
foreach ($relative in @(Get-AnajakAiRepairFiles)) {
    Assert-Repair ((Get-FileHash -LiteralPath (Join-Path $source $relative) -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $target $relative) -Algorithm SHA256).Hash) ('installed file hash:' + $relative)
}
# The normal target does not receive the package manifest; put a test-only copy
# there to simulate extracting the complete repair over the project first.
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $target 'ai-repair-manifest.json')
$self = Install-AnajakAiRepair -SourceRoot $target -HostingRoot $target
Assert-Repair ($self.EnvPreserved -and !$self.BackupPath) 'already extracted target verifies without self-copy'

$sourceScript = Join-Path $source 'AnajakMapBackend/AnajakMapBackend/scripts/update-ai.ps1'
$fixedScript = [IO.File]::ReadAllText($sourceScript)
[IO.File]::WriteAllText($sourceScript,$fixedScript.Replace('2026.10.28.1','2025.01.01.0'))
Save-TestManifest $source
Assert-RepairThrows { Install-AnajakAiRepair -SourceRoot $source -HostingRoot $target } 'outdated updater refused despite a matching manifest hash'
[IO.File]::WriteAllText($sourceScript,$fixedScript)
Save-TestManifest $source

$global:RepairDockerDirectory = $targetBackend
$global:RepairDockerCalls = @()
function global:docker {
    $global:LASTEXITCODE = 0
    $global:RepairDockerCalls += ($args -join '|')
    if ($args[0] -eq 'ps') { return '123456abcdef' }
    if ($args[0] -eq 'inspect') {
        if ($args[2] -ne '{{json .Config.Labels}}') { throw 'Docker inspection must use PowerShell-5-safe labels-only JSON.' }
        return (@{'com.docker.compose.project.working_dir'=$global:RepairDockerDirectory} | ConvertTo-Json -Compress)
    }
    throw 'Unexpected Docker mutation in repair test'
}
function global:Read-Host { throw 'Unexpected interactive prompt in automatic discovery test' }
$folders = @(Get-AnajakAiDockerFolders)
Assert-Repair ($folders.Count -eq 1 -and $folders[0] -eq $targetBackend) 'read-only Docker labels discover hosting folder'
Assert-Repair (!(($global:RepairDockerCalls -join '|').Contains('Config.Env'))) 'Docker credentials never inspected'
$wrapper = Join-Path $source 'AnajakMapBackend/AnajakMapBackend/scripts/repair-ai-setup.ps1'
$output = @(& $wrapper -InstallOnly -NonInteractive 6>&1)
Assert-Repair ($LASTEXITCODE -eq 0) 'default source location and Docker discovery install successfully'
Assert-Repair (($output -join "`n").Contains('2026.10.28.1')) 'installer reports its explicit version'
Assert-Repair (($output -join "`n").Contains($oldScript)) 'installer reports exact verified hosting script path'
Assert-Repair ((Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash -eq $originalEnv) 'default wrapper preserves env bytes'
$global:AnajakTestLaunchedScript = $null
$output = @(& $wrapper -NonInteractive 6>&1)
Assert-Repair ($LASTEXITCODE -eq 0 -and $global:AnajakTestLaunchedScript -eq $oldScript) 'one click launches exact installed script rather than source ZIP copy'
Assert-Repair ((Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash -eq $originalEnv) 'test launch leaves original config untouched'
$global:RepairDockerDirectory = Join-Path $second 'AnajakMapBackend/AnajakMapBackend'
$output = @(& $wrapper -SourceRoot $target -InstallOnly -NonInteractive 6>&1)
Assert-Repair ($LASTEXITCODE -eq 1) 'wrapper never resolves ambiguous Docker/source roots by ignoring Docker'
Assert-Repair ((Get-FileHash -LiteralPath $envPath -Algorithm SHA256).Hash -eq $originalEnv) 'ambiguous wrapper preserves private config'
$global:RepairDockerDirectory = $uninitialized
Assert-RepairThrows { Resolve-AnajakAiRepairTarget -SourceRoot $source -RecordedBackendFolders @(Get-AnajakAiDockerFolders) } 'Docker label without initialized env never creates credentials'
function global:Read-Host { return '' }
$output = @(& $wrapper -InstallOnly 6>&1)
Assert-Repair ($LASTEXITCODE -eq 1) 'blank folder prompt fails rather than choosing a different checkout'
Assert-Repair (!(Test-Path -LiteralPath (Join-Path $uninitialized 'AnajakMapBackend/AnajakMapBackend/.env'))) 'blank prompt never creates env'
Write-Host "PASS: $passed AI repair installer checks. Synthetic files, mocked Docker labels, no provider or live Docker operations."
Write-Host "Synthetic fixture: $fixture"
