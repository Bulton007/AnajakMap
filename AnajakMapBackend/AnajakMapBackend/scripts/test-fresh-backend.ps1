# Synthetic fixtures and mocked Docker only. No daemon, provider or real .env.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fresh-backend.ps1')
. (Join-Path $PSScriptRoot 'ai-settings.ps1')
$testRoot = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) ('.local/fresh-v12-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) > $null
$passed = 0
function Assert-Fresh([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "Fresh backend regression failed: $Name" }
    $script:passed++
}
function Assert-FreshThrows([scriptblock]$Action,[string]$Name) {
    $failed = $false
    try { & $Action > $null } catch { $failed = $true }
    Assert-Fresh $failed $Name
}
function New-FreshFixture([string]$Name) {
    $root = Join-Path $testRoot $Name
    $backend = Join-Path $root 'AnajakMapBackend/AnajakMapBackend'
    [IO.Directory]::CreateDirectory((Join-Path $backend 'scripts')) > $null
    foreach ($name in @('pom.xml','compose.yml','compose.media-source.yml','compose.local.yml','compose.runtime.yml','compose.laptop.yml','compose.fresh.yml')) {
        [IO.File]::WriteAllText((Join-Path $backend $name),'synthetic source')
    }
    [IO.File]::WriteAllText((Join-Path $backend 'scripts/grant-runtime.sh'),'synthetic runtime grants')
    return $root
}
function Save-FreshFixtureEnv([string]$Path,[hashtable]$Values) {
    $lines = @($Values.Keys | Sort-Object | ForEach-Object { $_ + '=' + (ConvertTo-AnajakAiDotEnvLiteral ([string]$Values[$_])) })
    [IO.File]::WriteAllText($Path,(($lines -join "`r`n") + "`r`n"),(New-Object Text.UTF8Encoding($false)))
}
$settings = @{}
foreach ($name in (Get-AnajakReadyRequiredKeys)) { $settings[$name] = 'synthetic-' + $name.ToLowerInvariant() }
$settings['COMPOSE_PROJECT_NAME'] = 'anajakmap-v12'
$settings['GATEWAY_HTTP_PORT'] = '18080'
$settings['LAPTOP_NGINX_PORT'] = '18090'
$settings['AI_PROVIDER'] = 'fixture'
$settings['ANAJAK_PUBLIC_BASE_URL'] = 'https://fictional-test.ngrok-free.dev/api/v1/'
$root = New-FreshFixture 'Extracted Version 12 (& spaces!)'
$backend = Join-Path $root 'AnajakMapBackend/AnajakMapBackend'
$envPath = Join-Path $backend '.env'
Assert-FreshThrows { Read-AnajakFreshConfiguration $backend } 'missing preincluded env fails instead of generating or adopting credentials'
Assert-Fresh (!(Test-Path -LiteralPath $envPath)) 'missing config failure creates no env'
Save-FreshFixtureEnv $envPath $settings
$envHash = (Get-FileHash -LiteralPath $envPath).Hash
$read = Read-AnajakFreshConfiguration $backend
Assert-Fresh ($read['COMPOSE_PROJECT_NAME'] -ceq 'anajakmap-v12') 'isolated project is read without rewriting config'
Assert-Fresh ((Get-FileHash -LiteralPath $envPath).Hash -ceq $envHash) 'configuration read preserves every byte'
foreach ($change in @(
    @('COMPOSE_PROJECT_NAME','anajakmap'),@('COMPOSE_PROJECT_NAME','other'),
    @('GATEWAY_HTTP_PORT','8080'),@('LAPTOP_NGINX_PORT','8090'),
    @('PATH','synthetic-system-path'),@('DOCKER_HOST','tcp://example.test:2375'),
    @('COMPOSE_FILE','other.yml'),@('DOCKER_CONTEXT','unrelated-context')
)) {
    $bad = @{} + $settings
    $bad[$change[0]] = $change[1]
    Save-FreshFixtureEnv $envPath $bad
    Assert-FreshThrows { Read-AnajakFreshConfiguration $backend } 'project ports and Docker system overrides fail closed'
}
Save-FreshFixtureEnv $envPath $settings
Assert-Fresh ((Get-FileHash -LiteralPath $envPath).Hash -ceq $envHash) 'restored synthetic config matches original fixture'
$public = Get-AnajakFreshPublicUri $settings
Assert-Fresh ($public.Host -ceq 'fictional-test.ngrok-free.dev') 'pinned public hostname is parsed without exposing credentials'
foreach ($url in @('http://fictional.ngrok-free.dev/api/v1/','https://fictional.ngrok-free.dev:444/api/v1/','https://fictional.ngrok-free.dev/','https://fictional.ngrok-free.dev/api/v1/?token=synthetic','https://name:synthetic@fictional.ngrok-free.dev/api/v1/','https://example.test/api/v1/')) {
    $bad = @{} + $settings
    $bad['ANAJAK_PUBLIC_BASE_URL'] = $url
    Assert-FreshThrows { Get-AnajakFreshPublicUri $bad } 'invalid public URL fails before starting a tunnel'
}

$schemaCompose = @(Get-AnajakFreshComposeArguments -Backend $backend)
$runtimeCompose = @(Get-AnajakFreshComposeArguments -Backend $backend -Runtime)
foreach ($compose in @($schemaCompose,$runtimeCompose)) {
    Assert-Fresh ($compose[0] -ceq 'compose' -and $compose[1] -ceq '-p' -and $compose[2] -ceq 'anajakmap-v12') 'every compose invocation pins the isolated project explicitly'
    Assert-Fresh ($compose[-1] -ceq 'compose.fresh.yml') 'fresh overlay is last and cannot merge the legacy port bindings'
    Assert-Fresh ($compose -contains '--env-file' -and $compose -contains $envPath) 'every compose invocation uses the included isolated env'
}
Assert-Fresh ($schemaCompose -notcontains 'compose.runtime.yml') 'migrations use schema-owner credentials'
Assert-Fresh ($runtimeCompose -contains 'compose.runtime.yml') 'runtime uses restricted app credentials'
$overlay = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'compose.fresh.yml'))
Assert-Fresh ($overlay.Contains('ports: !override ["127.0.0.1:18080:8089"]') -and $overlay.Contains('ports: !override ["127.0.0.1:18090:8080"]')) 'port override replaces rather than appends old bindings'
Assert-Fresh (!$overlay.Contains('container_name:') -and !$overlay.Contains('external:')) 'fresh overlay introduces no shared containers or external data volumes'

# Exercise the installed Compose flag parser, not a mocked command. --help
# exits before project loading or daemon access, so no container can be started.
$dockerCli = Get-Command docker -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$dockerCli) { throw 'The migration CLI syntax regression requires the Docker CLI installed. It never connects to the Docker daemon.' }
$migrationArguments = @(Get-AnajakFreshMigrationArguments 'identity')
Assert-Fresh ($migrationArguments -notcontains '--no-build') 'migration run never receives the up-only no-build flag'
$parserArguments = @($migrationArguments[0],'--help') + @($migrationArguments | Select-Object -Skip 1)
$help = @(& $dockerCli.Source compose @parserArguments 2>$null)
Assert-Fresh ($LASTEXITCODE -eq 0 -and ($help -join "`n") -match 'docker compose run') 'actual Compose parser accepts the exact production migration arguments without engine access'
$beforePreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & $dockerCli.Source compose run --help --rm --no-deps --no-build -e MIGRATE_ONLY=true identity-service *> $null
    $invalidFlagExit = $LASTEXITCODE
} finally { $ErrorActionPreference = $beforePreference }
Assert-Fresh ($invalidFlagExit -ne 0) 'actual Compose parser rejects the original unsupported no-build run flag'
Assert-FreshThrows { Get-AnajakFreshMigrationArguments 'unknown-service' } 'migration helper rejects unsupported services'

$oracleEnv = @()
foreach ($name in $settings.Keys) {
    if ($name -ceq 'ORACLE_PASSWORD' -or $name -match '_(DB|APP)_PASSWORD$') { $oracleEnv += $name + '=' + $settings[$name] }
}
$oracle = [pscustomobject]@{Service='oracle';Environment=$oracleEnv;Mounts=@([pscustomobject]@{Destination='/opt/oracle/oradata';Type='volume';Name='anajakmap-v12_oracle-data'})}
$identity = [pscustomobject]@{Service='identity-service';Environment=@('DB_USER=IDENTITY_APP',('DB_PASSWORD='+$settings['IDENTITY_APP_PASSWORD']),('JWT_PRIVATE_KEY='+$settings['JWT_PRIVATE_KEY']),('DATA_ENCRYPTION_KEY='+$settings['DATA_ENCRYPTION_KEY']));Mounts=@()}
Assert-AnajakFreshCredentialMatch -Settings $settings -Snapshots @($oracle,$identity)
Assert-Fresh $true 'existing fresh database and session credentials match privately'
Assert-Fresh ($oracle.Mounts[0].Name -ceq 'anajakmap-v12_oracle-data') 'private credential comparison never changes the real snapshot mount'
foreach ($key in @('ORACLE_PASSWORD','IDENTITY_APP_PASSWORD','JWT_PRIVATE_KEY','DATA_ENCRYPTION_KEY')) {
    $wrong = @{} + $settings
    $wrong[$key] = 'synthetic-wrong'
    Assert-FreshThrows { Assert-AnajakFreshCredentialMatch -Settings $wrong -Snapshots @($oracle,$identity) } 'mismatched database or session credentials block reuse'
}
Assert-FreshThrows { Assert-AnajakFreshCredentialMatch -Settings $settings -Snapshots @($identity) } 'orphaned fresh volume cannot be guessed'
$oldMount = [pscustomobject]@{Service='oracle';Environment=$oracleEnv;Mounts=@([pscustomobject]@{Destination='/opt/oracle/oradata';Type='volume';Name='anajakmap_oracle-data'})}
Assert-FreshThrows { Assert-AnajakFreshCredentialMatch -Settings $settings -Snapshots @($oldMount,$identity) } 'old database volume cannot be adopted by the fresh workflow'

# Exercise actual scoped snapshot discovery against synthetic Docker output.
$script:dockerCalls = @()
function docker {
    $script:dockerCalls += ,@($args)
    $global:LASTEXITCODE = 0
    if ($args[0] -ceq 'volume') { return 'anajakmap-v12_oracle-data' }
    if ($args[0] -ceq 'ps' -and $args -contains 'label=com.docker.compose.service=oracle') { return ('a' * 12) }
    if ($args[0] -ceq 'inspect' -and $args -contains '{{json .Config.Env}}') { return (ConvertTo-Json -InputObject @($oracleEnv) -Compress) }
    if ($args[0] -ceq 'inspect' -and $args -contains '{{json .Mounts}}') { return (ConvertTo-Json -InputObject @($oracle.Mounts) -Compress) }
}
Assert-Fresh (Test-AnajakFreshOracleVolume) 'volume probe recognizes only the dedicated fresh volume'
$snapshots = @(Get-AnajakFreshSnapshots)
Assert-Fresh ($snapshots.Count -eq 1 -and $snapshots[0].Service -ceq 'oracle') 'scoped snapshots return only matching fresh records'
Assert-Fresh ($snapshots[0].Environment.Count -eq $oracleEnv.Count -and $snapshots[0].Environment[0] -is [string]) 'real JSON parser produces flat environment strings in Windows PowerShell 5 and PowerShell 7'
Assert-Fresh ($snapshots[0].Mounts.Count -eq 1 -and $snapshots[0].Mounts[0] -is [System.Management.Automation.PSCustomObject]) 'real JSON parser produces flat mount objects rather than a nested array'
Assert-AnajakFreshCredentialMatch -Settings $settings -Snapshots $snapshots
Assert-Fresh $true 'Docker JSON discovery feeds the actual credential guard without a false mismatch'
$singleEnvironment = @(ConvertFrom-AnajakFreshDockerArray -Json '["REDIS_PASSWORD=synthetic"]' -Kind Environment)
Assert-Fresh ($singleEnvironment.Count -eq 1 -and $singleEnvironment[0] -is [string]) 'one JSON environment entry remains a scalar string inside the result array'
Assert-Fresh (@(ConvertFrom-AnajakFreshDockerArray -Json '[]' -Kind Environment).Count -eq 0) 'empty Docker environment array remains empty'
Assert-FreshThrows { ConvertFrom-AnajakFreshDockerArray -Json '{"REDIS_PASSWORD":"synthetic"}' -Kind Environment } 'a JSON object cannot replace the required environment array'
Assert-FreshThrows { ConvertFrom-AnajakFreshDockerArray -Json '[["REDIS_PASSWORD=synthetic"]]' -Kind Environment } 'nested environment arrays are rejected instead of stringified'
Assert-FreshThrows { ConvertFrom-AnajakFreshDockerArray -Json '["synthetic-mount"]' -Kind Mounts } 'mount arrays must contain objects'
$privateParseError = ''
try { ConvertFrom-AnajakFreshDockerArray -Json '["synthetic-private-value",invalid]' -Kind Environment > $null } catch { $privateParseError = $_.Exception.Message }
Assert-Fresh ($privateParseError -like '*privately parse*' -and !$privateParseError.Contains('synthetic-private-value')) 'malformed private JSON never echoes its input in the error'
foreach ($call in $script:dockerCalls) {
    if ($call[0] -ceq 'ps') { Assert-Fresh ($call -contains 'label=com.docker.compose.project=anajakmap-v12') 'container discovery never inspects the old project' }
    if ($call[0] -ceq 'volume') { Assert-Fresh (($call -join ' ') -like '*anajakmap-v12_oracle-data*' -and ($call -join ' ') -notlike '*name=^anajakmap_oracle-data*') 'volume discovery never queries old data' }
}

$script:contract = @{data=@{registration=$true;emailDelivery=$true;passwordMinLength=12;passwordMaxBytes=72;policyVersion='synthetic-v12-policy';termsUrl='https://example.test/terms';privacyUrl='https://example.test/privacy'}}
function Invoke-RestMethod {
    param([string]$Uri,[int]$TimeoutSec)
    Assert-Fresh ($Uri -ceq 'http://127.0.0.1:18090/api/v1/auth/config') 'real contract verifier is bound to the fresh local origin'
    return $script:contract
}
Assert-AnajakFreshAuthContract 'http://127.0.0.1:18090'
Assert-Fresh $true 'matching typed authentication contract is accepted'
foreach ($change in @(
    @('registration',$false),@('registration','true'),@('emailDelivery',$false),
    @('passwordMinLength',8),@('passwordMinLength','12'),@('passwordMaxBytes','72'),
    @('policyVersion',''),@('termsUrl','http://example.test/terms'),
    @('privacyUrl','https://user:synthetic@example.test/privacy')
)) {
    $beforeValue = $script:contract.data[$change[0]]
    $script:contract.data[$change[0]] = $change[1]
    Assert-FreshThrows { Assert-AnajakFreshAuthContract 'http://127.0.0.1:18090' } 'unready malformed or unsafe authentication contract cannot expose the backend'
    $script:contract.data[$change[0]] = $beforeValue
}

$global:FreshTestState = @{HasVolume=$false;Images=$true;Events=@();Commands=@();Fail='';Snapshots=@($oracle,$identity)}
function Wait-AnajakReadyDocker { $env:PATH = 'synthetic-docker-discovery-path';$global:FreshTestState.Events += 'docker-ready' }
function Test-AnajakFreshOracleVolume { $global:FreshTestState.Events += 'volume-check';return $global:FreshTestState.HasVolume }
function Get-AnajakFreshSnapshots { if ($global:FreshTestState.HasVolume) { return $global:FreshTestState.Snapshots }; return @() }
function Test-AnajakFreshImages { return $global:FreshTestState.Images }
function Invoke-AnajakFreshDocker([string[]]$Arguments) {
    $global:FreshTestState.Commands += ,@($Arguments)
    Assert-Fresh ($env:COMPOSE_PROJECT_NAME -ceq 'anajakmap-v12' -and $env:GATEWAY_HTTP_PORT -ceq '18080' -and $env:LAPTOP_NGINX_PORT -ceq '18090') 'process project and ports are pinned for every isolated Docker operation'
    Assert-Fresh ($env:ORACLE_PASSWORD -ceq $settings['ORACLE_PASSWORD']) 'stale shell credentials cannot override matching isolated config'
    Assert-Fresh ($Arguments -notcontains 'down' -and $Arguments -notcontains '--remove-orphans' -and $Arguments -notcontains 'prune') 'startup contains no destructive Docker cleanup'
    if ($Arguments[0] -ceq 'compose') {
        Assert-Fresh ($Arguments[1] -ceq '-p' -and $Arguments[2] -ceq 'anajakmap-v12' -and $Arguments -contains 'compose.fresh.yml') 'all orchestration commands target only the fresh project and overlay'
        if ($Arguments -contains 'config') { $global:FreshTestState.Events += 'compose-config';if ($global:FreshTestState.Fail -ceq 'config') { throw 'synthetic unsupported Compose version' } }
        elseif ($Arguments -contains 'build') { $global:FreshTestState.Events += 'build';if ($global:FreshTestState.Fail -ceq 'build') { throw 'synthetic build failure' } }
        elseif ($Arguments -contains 'MIGRATE_ONLY=true') {
            Assert-Fresh ($Arguments -notcontains 'compose.runtime.yml') 'every migration retains schema-owner settings'
            Assert-Fresh ($Arguments -notcontains '--no-build') 'no migration run receives a flag supported only by compose up'
            $global:FreshTestState.Events += 'migrate:' + $Arguments[-1]
            if ($global:FreshTestState.Fail -ceq 'migration') { throw 'synthetic migration failure' }
        }
        elseif ($Arguments -contains 'up' -and $Arguments -contains 'compose.runtime.yml') {
            $global:FreshTestState.Events += 'runtime-up'
            Assert-Fresh (@($global:FreshTestState.Events | Where-Object { $_ -like 'migrate:*' }).Count -eq 9) 'all nine migrations finish before runtime replacement'
        }
        elseif ($Arguments -contains 'up') { $global:FreshTestState.Events += 'infra-up' }
        elseif ($Arguments -contains '/container-entrypoint-initdb.d/01-schemas.sh') { $global:FreshTestState.Events += 'schema-setup' }
        elseif ($Arguments -contains '/tmp/anajak-v12-grant-runtime.sh') { $global:FreshTestState.Events += 'runtime-grants' }
    } elseif ($Arguments[0] -ceq 'run') {
        Assert-Fresh ($Arguments -contains 'type=volume,source=anajakmap-v12_maven-cache,target=/root/.m2') 'Maven cache uses a separate fresh volume'
        $global:FreshTestState.Events += 'maven'
    } elseif ($Arguments[0] -ceq 'cp') {
        Assert-Fresh ($Arguments[-1] -ceq (('a' * 12)+':/tmp/anajak-v12-grant-runtime.sh')) 'runtime grants copy targets the recorded fresh Oracle container only'
    } else { throw 'Unexpected synthetic Docker invocation' }
}
function Wait-AnajakFreshOracle([string[]]$Compose) { $global:FreshTestState.Events += 'oracle-ready';return ('a' * 12) }
function Wait-AnajakFreshServices([string[]]$Compose) { $global:FreshTestState.Events += 'all-nine-ready' }
function Wait-AnajakReadyProxy([string]$Origin) { Assert-Fresh ($Origin -ceq 'http://127.0.0.1:18090') 'Nginx readiness targets the fresh port';$global:FreshTestState.Events += 'proxy-ready' }
function Assert-AnajakFreshAuthContract([string]$Origin) { Assert-Fresh ($Origin -ceq 'http://127.0.0.1:18090') 'contract verifier targets the fresh endpoint';$global:FreshTestState.Events += 'auth-contract' }
function Invoke-AnajakReadyChildScript {
    param([string]$Scripts,[string]$Name,[hashtable]$Parameters)
    Assert-Fresh ($Name -ceq 'test-laptop.ps1' -and $Parameters.BaseUrl -ceq 'http://127.0.0.1:18090') 'only the parameterized boundary checker is reused; legacy startup scripts are never called'
    $global:FreshTestState.Events += 'boundaries'
}
function Start-AnajakFreshPublic([hashtable]$Settings) {
    Assert-Fresh ($global:FreshTestState.Events[-1] -ceq 'boundaries') 'no public tunnel starts before real contract and boundary checks'
    $global:FreshTestState.Events += 'public'
    if ($global:FreshTestState.Fail -ceq 'public') { throw 'synthetic tunnel failure' }
}
$names = @('ORACLE_PASSWORD','COMPOSE_PROJECT_NAME','GATEWAY_HTTP_PORT','LAPTOP_NGINX_PORT')
$prior = @{}
foreach ($name in $names) { $prior[$name] = [Environment]::GetEnvironmentVariable($name,'Process');[Environment]::SetEnvironmentVariable($name,'synthetic-stale-shell','Process') }
$priorPath = [Environment]::GetEnvironmentVariable('PATH','Process')
$priorLocation = (Get-Location).Path
try {
    Start-AnajakFreshBackend -ProjectRoot $root -Public
    $events = $global:FreshTestState.Events
    Assert-Fresh ([array]::IndexOf($events,'volume-check') -lt [array]::IndexOf($events,'maven')) 'fresh data existence is checked before any build or migration'
    Assert-Fresh ([array]::IndexOf($events,'compose-config') -lt [array]::IndexOf($events,'maven')) 'unsupported Compose overlay fails before any build or startup'
    Assert-Fresh ([array]::IndexOf($events,'schema-setup') -lt [array]::IndexOf($events,'migrate:identity-service')) 'schema setup precedes all migrations'
    Assert-Fresh ([array]::IndexOf($events,'runtime-grants') -lt [array]::IndexOf($events,'runtime-up')) 'runtime roles granted before app startup'
    Assert-Fresh ([array]::IndexOf($events,'all-nine-ready') -lt [array]::IndexOf($events,'auth-contract')) 'every service is ready before contract acceptance'
    Assert-Fresh ($events[-1] -ceq 'public') 'public launch follows all local checks'
    Assert-Fresh ((Get-Location).Path -ceq $priorLocation) 'caller directory restored after success'
    foreach ($name in $names) { Assert-Fresh ([Environment]::GetEnvironmentVariable($name,'Process') -ceq 'synthetic-stale-shell') 'caller environment restored after success' }
    Assert-Fresh ($env:PATH -ceq $priorPath) 'Docker command discovery restores the caller PATH after success'
    Assert-Fresh ((Get-FileHash -LiteralPath $envPath).Hash -ceq $envHash) 'successful startup preserves original private config bytes'
    Assert-Fresh (Test-Path -LiteralPath (Join-Path $backend '.local/fresh-v12-build.json')) 'only verified startup records the fingerprint stamp'

    $global:FreshTestState.HasVolume = $true
    $global:FreshTestState.Events = @()
    Start-AnajakFreshBackend -ProjectRoot $root
    Assert-Fresh ($global:FreshTestState.Events -notcontains 'maven' -and $global:FreshTestState.Events -notcontains 'build') 'matching validated existing source/images avoid unnecessary rebuild'
    Assert-Fresh ($global:FreshTestState.Events -notcontains 'public') 'local startup exposes no public tunnel'
    Assert-Fresh (@($global:FreshTestState.Events | Where-Object { $_ -like 'migrate:*' }).Count -eq 9) 'repeat startup still checks idempotent migrations before runtime'
    foreach ($failure in @('config','build','migration','public')) {
        $global:FreshTestState.HasVolume = $false
        $global:FreshTestState.Fail = $failure
        $global:FreshTestState.Events = @()
        $stampHash = (Get-FileHash -LiteralPath (Join-Path $backend '.local/fresh-v12-build.json')).Hash
        Assert-FreshThrows { Start-AnajakFreshBackend -ProjectRoot $root -Public } 'phase failure is propagated without cleanup or credential replacement'
        if ($failure -ne 'public') {
            Assert-Fresh ($global:FreshTestState.Events -notcontains 'runtime-up' -and $global:FreshTestState.Events -notcontains 'public') 'failed build/config/migration never starts runtime or tunnel'
            Assert-Fresh ((Get-FileHash -LiteralPath (Join-Path $backend '.local/fresh-v12-build.json')).Hash -ceq $stampHash) 'failed pre-readiness startup never updates success stamp'
        }
        Assert-Fresh ((Get-Location).Path -ceq $priorLocation) 'caller directory restored on failure'
        foreach ($name in $names) { Assert-Fresh ([Environment]::GetEnvironmentVariable($name,'Process') -ceq 'synthetic-stale-shell') 'caller process environment restored on failure' }
        Assert-Fresh ($env:PATH -ceq $priorPath) 'Docker command discovery restores the caller PATH after failure'
    }
    $global:FreshTestState.HasVolume = $true
    $global:FreshTestState.Fail = ''
    $global:FreshTestState.Snapshots = @($identity)
    $global:FreshTestState.Events = @()
    Assert-FreshThrows { Start-AnajakFreshBackend -ProjectRoot $root } 'unverifiable existing isolated volume blocks before any Compose operation'
    Assert-Fresh ($global:FreshTestState.Events -notcontains 'compose-config') 'credential guard runs before Docker mutations'
    Assert-Fresh ((Get-FileHash -LiteralPath $envPath).Hash -ceq $envHash) 'all failure paths leave private configuration intact'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$prior[$name],'Process') }
    [Environment]::SetEnvironmentVariable('PATH',$priorPath,'Process')
    Set-Location -LiteralPath $priorLocation
    $global:FreshTestState = $null
}
Write-Host "PASS: $passed fresh Version 12 backend checks. Synthetic configuration, mocked orchestration and actual CLI help parsing; no real provider, services, credentials or data changed."
