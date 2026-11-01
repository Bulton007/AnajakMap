# Synthetic file/Docker orchestration tests only. No real services or providers.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ready-backend.ps1')
$testRoot = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) ('.local/ready-backend-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) > $null
$passed = 0
function Assert-Ready([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "Ready backend regression failed: $Name" }
    $script:passed++
}
function Assert-ReadyThrows([scriptblock]$Action,[string]$Name) {
    $failed = $false
    try { & $Action > $null } catch { $failed = $true }
    Assert-Ready $failed $Name
}
function New-ReadyTestRoot([string]$Name) {
    $root = Join-Path $testRoot $Name
    $backend = Join-Path $root 'AnajakMapBackend/AnajakMapBackend'
    [IO.Directory]::CreateDirectory((Join-Path $backend 'scripts')) > $null
    [IO.Directory]::CreateDirectory((Join-Path $root 'private-config')) > $null
    [IO.File]::WriteAllText((Join-Path $backend 'compose.yml'),'synthetic compose')
    [IO.File]::WriteAllText((Join-Path $backend 'pom.xml'),'synthetic pom')
    return $root
}
$settings = @{}
foreach ($name in @(Get-AnajakReadyRequiredKeys)) { $settings[$name] = 'synthetic-' + $name.ToLowerInvariant() }
$settings['AI_PROVIDER'] = 'fixture'
$settings['GEMINI_API_KEY'] = 'synthetic.header.$literal.key'
function Save-ReadyTestEnv([string]$Path,[hashtable]$Values) {
    $text = (@($Values.Keys | Sort-Object | ForEach-Object { $_ + '=' + (ConvertTo-AnajakAiDotEnvLiteral ([string]$Values[$_])) }) -join "`r`n") + "`r`n"
    [IO.File]::WriteAllText($Path,$text,(New-Object Text.UTF8Encoding($false)))
}
. (Join-Path $PSScriptRoot 'ai-settings.ps1')
$fresh = New-ReadyTestRoot 'Fresh Extracted (& spaces!)'
$freshEnv = Join-Path $fresh 'AnajakMapBackend/AnajakMapBackend/.env'
$private = Join-Path $fresh 'private-config/.env'
Save-ReadyTestEnv $private $settings
$sourceHash = (Get-FileHash -LiteralPath $private).Hash
Assert-ReadyThrows { Initialize-AnajakReadyConfiguration -ProjectRoot $fresh -OracleVolumeExists $true } 'existing data refuses bundled env adoption'
Assert-Ready (!(Test-Path -LiteralPath $freshEnv)) 'blocked adoption creates no backend env'
$adopted = Initialize-AnajakReadyConfiguration -ProjectRoot $fresh -OracleVolumeExists $false
Assert-Ready ((Get-FileHash -LiteralPath $freshEnv).Hash -eq $sourceHash) 'fresh adoption preserves every private config byte'
Assert-Ready ($adopted['GEMINI_API_KEY'] -ceq $settings['GEMINI_API_KEY']) 'literal credential punctuation decoded without output'
[IO.File]::WriteAllText($private,'changed bundled config which must never replace initialized env')
$existing = Initialize-AnajakReadyConfiguration -ProjectRoot $fresh -OracleVolumeExists $true
Assert-Ready ((Get-FileHash -LiteralPath $freshEnv).Hash -eq $sourceHash) 'existing original env wins over bundled file'
$missing = New-ReadyTestRoot 'Missing private config'
Assert-ReadyThrows { Initialize-AnajakReadyConfiguration -ProjectRoot $missing -OracleVolumeExists $false } 'missing bundled config fails without generating credentials'
[IO.File]::WriteAllText((Join-Path $missing 'private-config/.env'),'ORACLE_PASSWORD=synthetic-incomplete')
Assert-ReadyThrows { Initialize-AnajakReadyConfiguration -ProjectRoot $missing -OracleVolumeExists $false } 'incomplete private config fails before adoption'
Assert-Ready (!(Test-Path -LiteralPath (Join-Path $missing 'AnajakMapBackend/AnajakMapBackend/.env'))) 'incomplete config never creates backend env'
$guarded = New-ReadyTestRoot 'Rejected private settings'
$guardedPrivate = Join-Path $guarded 'private-config/.env'
$guardedEnv = Join-Path $guarded 'AnajakMapBackend/AnajakMapBackend/.env'
$customProject = @{} + $settings
$customProject['COMPOSE_PROJECT_NAME'] = 'other-existing-project'
Save-ReadyTestEnv $guardedPrivate $customProject
Assert-ReadyThrows { Initialize-AnajakReadyConfiguration -ProjectRoot $guarded -OracleVolumeExists $false } 'custom Compose project is rejected before adoption'
Assert-Ready (!(Test-Path -LiteralPath $guardedEnv)) 'custom Compose project creates no backend config or data'
foreach ($reservedName in @('PATH','PATHEXT','HOME','HOMEDRIVE','HOMEPATH','USERPROFILE','CODEX_HOME','TEMP','TMP','SYSTEMROOT','COMSPEC','PSMODULEPATH','PROGRAMFILES','PROGRAMFILES(X86)','LOCALAPPDATA')) {
    $reservedSettings = @{} + $settings
    $reservedSettings[$reservedName] = 'synthetic-system-override'
    Save-ReadyTestEnv $guardedPrivate $reservedSettings
    Assert-ReadyThrows { Initialize-AnajakReadyConfiguration -ProjectRoot $guarded -OracleVolumeExists $false } 'reserved system setting rejected before process override'
    Assert-Ready (!(Test-Path -LiteralPath $guardedEnv)) 'reserved system setting never creates backend env'
}
$projectOptions = @{} + $settings
$projectOptions['COMPOSE_PROJECT_NAME'] = 'anajakmap'
$projectOptions['ANAJAK_CUSTOM_OPTION'] = 'synthetic-project-option'
Assert-AnajakReadySettings $projectOptions
Assert-Ready $true 'the supported project and unrelated ANAJAK option remain allowed'

$oracleEnv = @()
foreach ($name in $settings.Keys) { if ($name -eq 'ORACLE_PASSWORD' -or $name -match '_(DB|APP)_PASSWORD$') { $oracleEnv += ($name + '=' + $settings[$name]) } }
$oracle = [pscustomobject]@{Service='oracle';Environment=$oracleEnv;Mounts=@([pscustomobject]@{Destination='/opt/oracle/oradata';Type='volume';Name='anajakmap_oracle-data'})}
$identity = [pscustomobject]@{Service='identity-service';Environment=@('DB_USER=IDENTITY_APP',('DB_PASSWORD='+$settings['IDENTITY_APP_PASSWORD']),('JWT_PRIVATE_KEY='+$settings['JWT_PRIVATE_KEY']),('DATA_ENCRYPTION_KEY='+$settings['DATA_ENCRYPTION_KEY']));Mounts=@()}
Assert-AnajakReadyCredentialMatch -Settings $settings -Snapshots @($oracle,$identity)
Assert-Ready $true 'recorded schema app and encryption credentials match privately'
$wrong = @{} + $settings
$wrong['ORACLE_PASSWORD'] = 'synthetic-wrong'
Assert-ReadyThrows { Assert-AnajakReadyCredentialMatch -Settings $wrong -Snapshots @($oracle,$identity) } 'wrong Oracle password blocks before startup'
$wrong = @{} + $settings
$wrong['JWT_PRIVATE_KEY'] = 'synthetic-wrong'
Assert-ReadyThrows { Assert-AnajakReadyCredentialMatch -Settings $wrong -Snapshots @($oracle,$identity) } 'wrong session signing key blocks before startup'
$wrong = @{} + $settings
$wrong['DATA_ENCRYPTION_KEY'] = 'synthetic-wrong'
Assert-ReadyThrows { Assert-AnajakReadyCredentialMatch -Settings $wrong -Snapshots @($oracle,$identity) } 'wrong encryption key blocks before startup'
Assert-ReadyThrows { Assert-AnajakReadyCredentialMatch -Settings $settings -Snapshots @($identity) } 'orphaned data without original Oracle container cannot be guessed'
$badMount = [pscustomobject]@{Service='oracle';Environment=$oracleEnv;Mounts=@([pscustomobject]@{Destination='/opt/oracle/oradata';Type='volume';Name='different-data'})}
Assert-ReadyThrows { Assert-AnajakReadyCredentialMatch -Settings $settings -Snapshots @($badMount) } 'unrelated Oracle volume rejected'

$backend = Join-Path $fresh 'AnajakMapBackend/AnajakMapBackend'
$fingerprint = Get-AnajakReadySourceFingerprint $backend
# Real Windows PowerShell 5.1 repro: Get-ChildItem resolves these segments,
# yielding a shorter FullName than the raw root text used by the old offset.
$aliasBackend = $backend + '\scripts\..\scripts\..'
Assert-Ready ($aliasBackend.Length -gt (Get-Item -LiteralPath (Join-Path $backend 'pom.xml')).FullName.Length) 'path fixture reproduces the old out-of-range substring offset'
foreach ($equivalentRoot in @($aliasBackend,($backend + '\'),($backend + '\.\'),($backend.Replace('\','/')))) {
    Assert-Ready ((Get-AnajakReadySourceFingerprint $equivalentRoot) -eq $fingerprint) 'equivalent resolved source paths have the same fingerprint'
}
$fingerprintLocation = (Get-Location).Path
try {
    Set-Location -LiteralPath $fresh
    Assert-Ready ((Get-AnajakReadySourceFingerprint '.\AnajakMapBackend\AnajakMapBackend\scripts\..') -eq $fingerprint) 'relative source root resolves before computing descendant offsets'
} finally { Set-Location -LiteralPath $fingerprintLocation }
$longExtraction = New-ReadyTestRoot 'Downloads/AnajakMap-Backend-Ready-PRIVATE/AnajakMap-Backend-v2-ngrok'
$longBackend = Join-Path $longExtraction 'AnajakMapBackend/AnajakMapBackend'
Assert-Ready ((Get-AnajakReadySourceFingerprint $longBackend) -eq $fingerprint) 'long nested extraction path keeps content fingerprint independent of installation folder'
Assert-Ready ((Get-AnajakReadySourceFingerprint ($longBackend + '\scripts\..\scripts\..')) -eq $fingerprint) 'long extraction plus normalized path segments no longer throws Substring'
Assert-ReadyThrows { Get-AnajakReadySourceFingerprint (Join-Path $backend 'pom.xml') } 'a file cannot be accepted as the source root'
Assert-Ready ((Get-FileHash -LiteralPath $freshEnv).Hash -eq $sourceHash) 'source path normalization never changes existing private configuration'

# A source junction must not cause hashing files from a sibling tree. Excluded
# generated directories are skipped without traversing their contents.
$outsideSource = Join-Path $testRoot 'source-sibling'
[IO.Directory]::CreateDirectory($outsideSource) > $null
[IO.File]::WriteAllText((Join-Path $outsideSource 'outside.java'),'synthetic outside source')
$linkBackend = Join-Path (New-ReadyTestRoot 'Linked source fixture') 'AnajakMapBackend/AnajakMapBackend'
$sourceJunction = Join-Path $linkBackend 'linked-source'
New-Item -ItemType Junction -Path $sourceJunction -Target $outsideSource > $null
Assert-ReadyThrows { Get-AnajakReadySourceFingerprint $linkBackend } 'source junction cannot traverse into a sibling directory'
Assert-ReadyThrows { Get-AnajakReadySourceFingerprint $sourceJunction } 'a source root junction is rejected before traversal'
$ignoredLinkBackend = Join-Path (New-ReadyTestRoot 'Ignored generated junction fixture') 'AnajakMapBackend/AnajakMapBackend'
New-Item -ItemType Junction -Path (Join-Path $ignoredLinkBackend 'target') -Target $outsideSource > $null
Assert-Ready ((Get-AnajakReadySourceFingerprint $ignoredLinkBackend) -eq $fingerprint) 'ignored generated junctions are never traversed or hashed'

[IO.Directory]::CreateDirectory((Join-Path $backend 'target')) > $null
[IO.File]::WriteAllText((Join-Path $backend 'target/ignored.java'),'generated bytes')
Assert-Ready ((Get-AnajakReadySourceFingerprint $backend) -eq $fingerprint) 'generated files do not invalidate source fingerprint'
[IO.File]::AppendAllText((Join-Path $backend 'compose.yml'),' changed source')
Assert-Ready ((Get-AnajakReadySourceFingerprint $backend) -ne $fingerprint) 'source change invalidates build fingerprint'

function docker { throw 'synthetic missing image native error' }
Assert-Ready (!(Test-AnajakReadyImages)) 'missing image native stderr becomes a rebuild instead of a startup crash'
$script:checkedImages = @()
function docker {
    $script:checkedImages += [string]$args[-1]
    $global:LASTEXITCODE = if ($args[-1] -eq 'anajakmap/mc:local-2025-04-16') { 1 } else { 0 }
}
Assert-Ready (!(Test-AnajakReadyImages)) 'missing locally built media image also forces a build'
Assert-Ready ($script:checkedImages -contains 'anajakmap/minio:local-2025-04-22' -and $script:checkedImages -contains 'anajakmap/mc:local-2025-04-16') 'all required local media images are checked'
function docker {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'ps' -and $args -contains 'label=com.docker.compose.service=oracle') { return ('a' * 12) }
    if ($args[0] -eq 'inspect' -and $args -contains '{{json .Config.Env}}') { return 'invalid-json-synthetic-private-value' }
}
$parseFailure = ''
try { Get-AnajakReadySnapshots > $null } catch { $parseFailure = $_.Exception.Message }
Assert-Ready ($parseFailure -like '*privately parse*' -and !$parseFailure.Contains('synthetic-private-value')) 'malformed private container output never reaches the console error'

# Exercise the actual child invoker before replacing orchestration hooks below.
# Array splatting of '-BaseUrl' would silently bind that flag text positionally.
$childScripts = Join-Path $testRoot 'Real child scripts (& spaces!)'
[IO.Directory]::CreateDirectory($childScripts) > $null
$childPath = Join-Path $childScripts 'capture-parameters.ps1'
[IO.File]::WriteAllText($childPath, @'
param([string]$BaseUrl, [switch]$Flag, [switch]$Fail)
$global:ReadyActualChildParameters = @{BaseUrl=$BaseUrl;Flag=[bool]$Flag;ExtraArguments=$args.Count;Script=$PSCommandPath}
if ($Fail) { exit 9 }
exit 0
'@)
Invoke-AnajakReadyChildScript -Scripts $childScripts -Name 'capture-parameters.ps1' -Parameters @{BaseUrl='http://127.0.0.1:8090';Flag=$true}
Assert-Ready ($global:ReadyActualChildParameters.BaseUrl -ceq 'http://127.0.0.1:8090') 'real child receives named BaseUrl value instead of literal flag text'
Assert-Ready ($global:ReadyActualChildParameters.Flag -and $global:ReadyActualChildParameters.ExtraArguments -eq 0) 'real child receives named switch with no positional leftovers'
Assert-Ready ($global:ReadyActualChildParameters.Script -ceq $childPath) 'actual child script path handles spaces and shell punctuation'
Assert-ReadyThrows { Invoke-AnajakReadyChildScript -Scripts $childScripts -Name 'capture-parameters.ps1' -Parameters @{Fail=$true} } 'actual child nonzero exit stops orchestration'
$global:ReadyActualChildParameters = $null

$global:ReadyTestState = @{HasVolume=$false;Images=$true;Calls=@();Snapshots=@($oracle,$identity);FailBuild=$false}
function Wait-AnajakReadyDocker { $global:ReadyTestState.Calls += 'docker-ready' }
function Test-AnajakReadyOracleVolume { $global:ReadyTestState.Calls += 'volume-check';return $global:ReadyTestState.HasVolume }
function Get-AnajakReadySnapshots { return $global:ReadyTestState.Snapshots }
function Test-AnajakReadyImages { $global:ReadyTestState.Calls += 'images-check'; return $global:ReadyTestState.Images }
function Invoke-AnajakReadyChildScript {
    param([string]$Scripts,[string]$Name,[hashtable]$Parameters=@{})
    $global:ReadyTestState.Calls += $Name
    if ($Name -eq 'start-local.ps1' -and $global:ReadyTestState.FailBuild) { throw 'synthetic build failed' }
    Assert-Ready ($env:ORACLE_PASSWORD -ceq $settings['ORACLE_PASSWORD']) 'Compose receives parsed matching credentials'
    Assert-Ready ($env:COMPOSE_PROJECT_NAME -eq 'anajakmap') 'fixed Compose project avoids stale shell override'
    Assert-Ready (!$Parameters.ContainsKey('TemporaryPublicUrl')) 'Cloudflare flow is never selected'
    if ($Name -eq 'test-laptop.ps1') {
        $expectedPort = if ($env:LAPTOP_NGINX_PORT) { $env:LAPTOP_NGINX_PORT } else { '8090' }
        Assert-Ready ($Parameters.BaseUrl -ceq "http://127.0.0.1:$expectedPort") 'proxy check receives explicit named origin parameter'
    }
}
function Wait-AnajakReadyServices([string]$Scripts) { $global:ReadyTestState.Calls += 'all-nine-ready' }
function Wait-AnajakReadyProxy([string]$Origin) { $global:ReadyTestState.Calls += 'proxy-ready' }
$priorOracle = [Environment]::GetEnvironmentVariable('ORACLE_PASSWORD','Process')
$priorProject = [Environment]::GetEnvironmentVariable('COMPOSE_PROJECT_NAME','Process')
$priorLocation = (Get-Location).Path
try {
    [Environment]::SetEnvironmentVariable('ORACLE_PASSWORD','synthetic-stale-shell','Process')
    [Environment]::SetEnvironmentVariable('COMPOSE_PROJECT_NAME','synthetic-wrong-project','Process')
    Start-AnajakReadyBackend -ProjectRoot $fresh
    $events = $global:ReadyTestState.Calls
    Assert-Ready ([array]::IndexOf($events,'volume-check') -lt [array]::IndexOf($events,'start-local.ps1')) 'existing data checked before any build/migration'
    Assert-Ready ($events -contains 'start-local.ps1' -and $events -contains 'start-laptop.ps1') 'first run builds migrates and starts Nginx'
    Assert-Ready ([array]::IndexOf($events,'all-nine-ready') -lt [array]::IndexOf($events,'test-laptop.ps1')) 'all services ready before proxy boundary checks'
    Assert-Ready ($events -notcontains 'start-ngrok.ps1') 'local run starts no public tunnel'
    Assert-Ready ($env:ORACLE_PASSWORD -ceq 'synthetic-stale-shell' -and $env:COMPOSE_PROJECT_NAME -eq 'synthetic-wrong-project') 'original shell settings restored after successful local start'
    Assert-Ready ((Get-Location).Path -eq $priorLocation) 'caller location restored'
    Assert-Ready (Test-Path -LiteralPath (Join-Path $backend '.local/ready-bundle-build.json')) 'successful readiness writes source stamp'
    $global:ReadyTestState.Calls = @()
    $global:ReadyTestState.HasVolume = $true
    Start-AnajakReadyBackend -ProjectRoot $fresh -Public
    Assert-Ready ($global:ReadyTestState.Calls -notcontains 'start-local.ps1') 'unchanged validated source avoids rebuild'
    Assert-Ready ($global:ReadyTestState.Calls[-1] -eq 'start-ngrok.ps1') 'public tunnel launches only after backend checks'
    $global:ReadyTestState.Calls = @()
    $global:ReadyTestState.HasVolume = $false
    Start-AnajakReadyBackend -ProjectRoot $fresh
    Assert-Ready ($global:ReadyTestState.Calls -contains 'start-local.ps1') 'fresh database always initializes even if an old build stamp exists'
    $global:ReadyTestState.Calls = @()
    [IO.File]::AppendAllText((Join-Path $backend 'pom.xml'),' new build')
    $global:ReadyTestState.FailBuild = $true
    Assert-ReadyThrows { Start-AnajakReadyBackend -ProjectRoot $fresh -Public } 'build failure stops public startup'
    Assert-Ready ($global:ReadyTestState.Calls -notcontains 'start-laptop.ps1' -and $global:ReadyTestState.Calls -notcontains 'start-ngrok.ps1') 'failed build starts neither Nginx nor tunnel'
    Assert-Ready ($env:ORACLE_PASSWORD -ceq 'synthetic-stale-shell') 'original environment restored after failure'
} finally {
    [Environment]::SetEnvironmentVariable('ORACLE_PASSWORD',$priorOracle,'Process')
    [Environment]::SetEnvironmentVariable('COMPOSE_PROJECT_NAME',$priorProject,'Process')
    Set-Location -LiteralPath $priorLocation
    $global:ReadyTestState = $null
}
Write-Host "PASS: $passed ready backend checks; synthetic configuration and mocked orchestration only. No real Docker, Google or database mutation."
