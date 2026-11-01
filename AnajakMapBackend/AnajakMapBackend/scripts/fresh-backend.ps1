# Isolated Version 12 startup. Never generate credentials or inspect the old project.
. (Join-Path $PSScriptRoot 'ready-backend.ps1')

function Get-AnajakFreshProject { return 'anajakmap-v12' }
function Get-AnajakFreshServices {
    return @('identity','trip','ai-guide','discovery','expense','reservation','journal','notification','gateway')
}

function Get-AnajakFreshMigrationArguments([string]$Service) {
    if ($Service -notin (Get-AnajakFreshServices)) { throw 'Unknown isolated migration service.' }
    # `run` has no --no-build flag. Images are built explicitly before this
    # phase; without --build, Compose reuses those existing local images.
    return @('run','--rm','--no-deps','-e','MIGRATE_ONLY=true',($Service+'-service'))
}

function Get-AnajakFreshComposeArguments {
    param([string]$Backend,[switch]$Runtime)
    $arguments = @('compose','-p',(Get-AnajakFreshProject),'--project-directory',$Backend,
        '--env-file',(Join-Path $Backend '.env'),'-f','compose.yml','-f','compose.media-source.yml','-f','compose.local.yml')
    if ($Runtime) { $arguments += @('-f','compose.runtime.yml') }
    return $arguments + @('-f','compose.laptop.yml','-f','compose.fresh.yml')
}

function Invoke-AnajakFreshDocker([string[]]$Arguments) {
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "The isolated Docker command failed (exit $LASTEXITCODE). No old project services or volumes were changed." }
}

function Read-AnajakFreshConfiguration([string]$Backend) {
    foreach ($marker in @('pom.xml','compose.yml','compose.media-source.yml','compose.local.yml','compose.runtime.yml','compose.laptop.yml','compose.fresh.yml')) {
        if (!(Test-Path -LiteralPath (Join-Path $Backend $marker) -PathType Leaf)) { throw 'Extract the complete isolated Version 12 backend bundle before starting.' }
    }
    $path = Join-Path $Backend '.env'
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw 'This isolated bundle requires its included private .env. Restore that original file; this launcher never generates, adopts or replaces credentials.' }
    $settings = Read-AnajakReadySettings $path
    if (!$settings.ContainsKey('COMPOSE_PROJECT_NAME') -or $settings['COMPOSE_PROJECT_NAME'] -cne (Get-AnajakFreshProject)) {
        throw 'The isolated .env must declare COMPOSE_PROJECT_NAME=anajakmap-v12. The old anajakmap configuration cannot be used here.'
    }
    foreach ($port in @(@('GATEWAY_HTTP_PORT','18080'),@('LAPTOP_NGINX_PORT','18090'))) {
        if (!$settings.ContainsKey($port[0]) -or $settings[$port[0]] -cne $port[1]) { throw 'The isolated bundle requires gateway port 18080 and Nginx port 18090. No configuration or services were changed.' }
    }
    foreach ($reserved in @('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_CONFIG','COMPOSE_FILE','COMPOSE_PROFILES','COMPOSE_ENV_FILES','COMPOSE_PATH_SEPARATOR','COMPOSE_DISABLE_ENV_FILE')) {
        if ($settings.ContainsKey($reserved)) { throw 'Private configuration contains a reserved Docker environment override. No configuration or services were changed.' }
    }
    $general = @{} + $settings
    $general.Remove('COMPOSE_PROJECT_NAME')
    Assert-AnajakReadySettings $general
    return $settings
}

function Test-AnajakFreshOracleVolume {
    $name = (Get-AnajakFreshProject) + '_oracle-data'
    $names = @(& docker volume ls --filter "name=^$name`$" --format '{{.Name}}' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Could not check the isolated Oracle volume. No services were changed.' }
    return @($names | Where-Object { [string]$_ -ceq $name }).Count -gt 0
}

function ConvertFrom-AnajakFreshDockerArray {
    param([string]$Json,[ValidateSet('Environment','Mounts')][string]$Kind)
    try {
        $document = $Json.Trim()
        if (!$document.StartsWith('[') -or !$document.EndsWith(']')) { throw 'Expected JSON array.' }
        $decodeArguments = @{InputObject=$document;ErrorAction='Stop'}
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('NoEnumerate')) {
            $decodeArguments['NoEnumerate'] = $true
        }
        $decoded = ConvertFrom-Json @decodeArguments
        # Windows PowerShell 5.1 emits a root JSON array as one pipeline item;
        # PowerShell 7 can preserve it with NoEnumerate. Explicit foreach normalizes both before
        # the caller captures the individually validated entries with @(...).
        foreach ($entry in $decoded) {
            if ($Kind -eq 'Environment') {
                if ($entry -isnot [string]) { throw 'Expected environment string.' }
            } elseif ($entry -isnot [System.Management.Automation.PSCustomObject]) {
                throw 'Expected mount object.'
            }
            $entry
        }
    } catch {
        # ConvertFrom-Json errors can contain input excerpts. Never forward the
        # original exception when the JSON contains private environment values.
        throw 'Could not privately parse isolated container records. No services were changed.'
    }
}

function Get-AnajakFreshSnapshots {
    $snapshots = @()
    foreach ($service in @('oracle','redis','rabbitmq','minio') + @((Get-AnajakFreshServices) | ForEach-Object { $_ + '-service' })) {
        $ids = @(& docker ps -a --filter ('label=com.docker.compose.project=' + (Get-AnajakFreshProject)) --filter "label=com.docker.compose.service=$service" --format '{{.ID}}' 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the isolated Docker project. No services were changed.' }
        $ids = @($ids | Where-Object { [string]$_ -match '\A[a-fA-F0-9]{12,64}\z' })
        if ($ids.Count -gt 1) { throw 'Multiple isolated service records exist. Resolve the Version 12 project records before retrying; no services were changed.' }
        if (!$ids.Count) { continue }
        $raw = @(& docker inspect --format '{{json .Config.Env}}' $ids[0] 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Could not privately verify isolated credentials. No services were changed.' }
        $environment = @(ConvertFrom-AnajakFreshDockerArray -Json ($raw -join "`n") -Kind Environment)
        $mounts = @()
        if ($service -eq 'oracle') {
            $rawMounts = @(& docker inspect --format '{{json .Mounts}}' $ids[0] 2>$null)
            if ($LASTEXITCODE -ne 0) { throw 'Could not verify the isolated Oracle data mount. No services were changed.' }
            $mounts = @(ConvertFrom-AnajakFreshDockerArray -Json ($rawMounts -join "`n") -Kind Mounts)
        }
        $snapshots += [pscustomobject]@{Service=$service;Environment=$environment;Mounts=$mounts}
    }
    return $snapshots
}

function Assert-AnajakFreshCredentialMatch {
    param([hashtable]$Settings,[object[]]$Snapshots)
    $expectedVolume = (Get-AnajakFreshProject) + '_oracle-data'
    $oracle = @($Snapshots | Where-Object { $_.Service -eq 'oracle' })
    if ($oracle.Count -ne 1) { throw 'Isolated Oracle data already exists without its original container record. Restore the matching Version 12 configuration/container; no credentials were replaced.' }
    $mounts = @($oracle[0].Mounts | Where-Object { $_.Destination -eq '/opt/oracle/oradata' -and $_.Type -eq 'volume' -and $_.Name -ceq $expectedVolume })
    if ($mounts.Count -ne 1) { throw 'The isolated Oracle record does not use its dedicated Version 12 volume. No services were changed.' }
    # Reuse the established private comparison on a copy after verifying the
    # real fresh mount above. The helper's legacy volume name is an invariant
    # of its own workflow; no old Docker container or volume is ever inspected.
    $comparison = @()
    foreach ($snapshot in $Snapshots) {
        $comparison += [pscustomobject]@{Service=$snapshot.Service;Environment=$snapshot.Environment;Mounts=@(
            foreach ($mount in $snapshot.Mounts) {
                [pscustomobject]@{Destination=$mount.Destination;Type=$mount.Type;Name=if ($snapshot.Service -eq 'oracle' -and $mount.Name -ceq $expectedVolume) { 'anajakmap_oracle-data' } else { $mount.Name }}
            }
        )}
    }
    try { Assert-AnajakReadyCredentialMatch -Settings $Settings -Snapshots $comparison }
    catch { throw 'The isolated .env does not match its recorded Version 12 database/session credentials. Restore the matching original file. No services or data were changed.' }
}

function Test-AnajakFreshImages {
    $images = @((Get-AnajakFreshServices) | ForEach-Object { 'anajakmap-v12/' + $_ + '-service:latest' })
    $images += 'anajakmap-v12/minio:local-2025-04-22','anajakmap-v12/mc:local-2025-04-16'
    foreach ($image in $images) {
        try { & docker image inspect $image *> $null; if ($LASTEXITCODE -ne 0) { return $false } }
        catch { return $false }
    }
    return $true
}

function Wait-AnajakFreshOracle([string[]]$Compose) {
    $deadline = (Get-Date).AddMinutes(15)
    do {
        $ids = @(& docker @Compose ps -q oracle 2>$null)
        if ($LASTEXITCODE -eq 0 -and $ids.Count -eq 1 -and [string]$ids[0] -match '\A[a-fA-F0-9]{12,64}\z') {
            $raw = @(& docker inspect --format '{{json .State}}' $ids[0] 2>$null)
            if ($LASTEXITCODE -eq 0) {
                try { $state = ($raw -join "`n") | ConvertFrom-Json } catch { $state = $null }
                if ($state -and $state.Status -in @('exited','dead','paused','removing')) { throw 'The isolated Oracle container stopped. Check its local logs; no credentials were changed.' }
                if ($state -and $state.Health -and $state.Health.Status -eq 'healthy') { return [string]$ids[0] }
            }
        }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 5
    } while ($true)
    throw 'The isolated Oracle database did not become healthy within 15 minutes. No old data was touched.'
}

function Wait-AnajakFreshServices([string[]]$Compose) {
    . (Join-Path $PSScriptRoot 'backend-readiness.ps1')
    $port = 8080
    foreach ($service in (Get-AnajakFreshServices)) {
        $port++
        $name = $service + '-service'
        $ids = @(& docker @Compose ps -q $name 2>$null)
        if ($LASTEXITCODE -ne 0 -or $ids.Count -ne 1 -or [string]$ids[0] -notmatch '\A[a-fA-F0-9]{12,64}\z') { throw "$name does not have one isolated running container." }
        Wait-BackendServiceReady -ContainerId ([string]$ids[0]) -Service $name -Port $port
        Write-Host "$name isolated readiness is UP."
    }
}

function Assert-AnajakFreshAuthContract([string]$Origin) {
    $auth = Invoke-RestMethod "$Origin/api/v1/auth/config" -TimeoutSec 15
    if (!$auth.data -or $auth.data.registration -isnot [bool] -or $auth.data.registration -ne $true -or
        $auth.data.emailDelivery -isnot [bool] -or $auth.data.emailDelivery -ne $true -or
        $auth.data.passwordMinLength -is [string] -or $auth.data.passwordMaxBytes -is [string] -or
        $auth.data.passwordMinLength -ne 12 -or $auth.data.passwordMaxBytes -ne 72 -or
        [string]::IsNullOrWhiteSpace([string]$auth.data.policyVersion)) {
        throw 'The isolated authentication contract is not ready: registration, email configuration and password rules must match the app. No public tunnel was started.'
    }
    foreach ($link in @($auth.data.termsUrl,$auth.data.privacyUrl)) {
        $uri = $null
        if (![Uri]::TryCreate([string]$link,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo) { throw 'The isolated legal URLs are not valid HTTPS links. No public tunnel was started.' }
    }
    Write-Host 'Version 12 authentication contract is ready. Actual inbox delivery and AI still require their own live checks.'
}

function Get-AnajakFreshPublicUri([hashtable]$Settings) {
    $public = $null
    if (!$Settings.ContainsKey('ANAJAK_PUBLIC_BASE_URL') -or
        ![Uri]::TryCreate([string]$Settings['ANAJAK_PUBLIC_BASE_URL'],[UriKind]::Absolute,[ref]$public) -or
        $public.Scheme -ne 'https' -or !$public.IsDefaultPort -or $public.UserInfo -or $public.Query -or $public.Fragment -or
        $public.AbsolutePath.TrimEnd('/') -cne '/api/v1' -or
        $public.Host -notmatch '\A[a-z0-9-]+\.(ngrok-free\.dev|ngrok\.dev)\z') {
        throw 'Configure ANAJAK_PUBLIC_BASE_URL with the account-assigned HTTPS ngrok address ending in /api/v1/. The local backend remains available on port 18090.'
    }
    return $public
}

function Start-AnajakFreshPublic([hashtable]$Settings) {
    . (Join-Path $PSScriptRoot 'ngrok-command.ps1')
    $public = Get-AnajakFreshPublicUri $Settings
    $agent = Get-AnajakNgrokCommand
    & $agent config check *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Run Configure Ngrok.cmd once to save your account token privately on this PC.' }
    $origin = 'http://127.0.0.1:18090'
    $existing = $null
    try { $existing = Invoke-RestMethod 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 2 } catch { }
    if ($existing) {
        $matching = @($existing.tunnels | Where-Object {
            $endpoint = $null
            $_.proto -eq 'https' -and ([string]$_.config.addr).TrimEnd('/') -ceq $origin -and
                [Uri]::TryCreate([string]$_.public_url,[UriKind]::Absolute,[ref]$endpoint) -and
                $endpoint.Scheme -eq 'https' -and !$endpoint.UserInfo -and $endpoint.Host -ceq $public.Host
        })
        if ($matching.Count -eq 1) {
            Assert-AnajakFreshAuthContract ($public.GetLeftPart([UriPartial]::Authority))
            Write-Host "Version 12 public API is already running: $($public.AbsoluteUri)" -ForegroundColor Green
            return
        }
        throw 'An ngrok agent is already forwarding another backend. Close that tunnel window yourself before exposing Version 12. The old backend was not stopped.'
    }
    Write-Host "Starting the Version 12 public API: $($public.AbsoluteUri)" -ForegroundColor Green
    Write-Host 'Keep this window, Docker, your PC and internet connection running. Request inspection is disabled.'
    & $agent http $origin --url ($public.GetLeftPart([UriPartial]::Authority)) --inspect=false
    if ($LASTEXITCODE -ne 0) { throw 'The Version 12 ngrok endpoint could not start. Check account access, hostname, quota and connection; the old backend was not changed.' }
}

function Start-AnajakFreshBackend {
    param([string]$ProjectRoot,[switch]$Public)
    $backend = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'AnajakMapBackend/AnajakMapBackend'))
    $before = @{PATH=[Environment]::GetEnvironmentVariable('PATH','Process')}
    $originalLocation = (Get-Location).Path
    try {
        # Configuration must already be present; never invoke init-dev or adopt
        # a different bundle's credentials when a project has existing data.
        $settings = Read-AnajakFreshConfiguration $backend
        Wait-AnajakReadyDocker
        $hasOracle = Test-AnajakFreshOracleVolume
        $snapshots = @(Get-AnajakFreshSnapshots)
        if ($hasOracle) { Assert-AnajakFreshCredentialMatch -Settings $settings -Snapshots $snapshots }
        elseif ($snapshots.Count) { throw 'Isolated container records exist without their expected Oracle volume. Restore the original Version 12 data/configuration; this launcher never resets it.' }
        foreach ($name in @($settings.Keys)) { $before[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
        foreach ($name in $settings.Keys) { [Environment]::SetEnvironmentVariable($name,[string]$settings[$name],'Process') }
        Set-Location -LiteralPath $backend
        $schemaCompose = @(Get-AnajakFreshComposeArguments -Backend $backend)
        $runtimeCompose = @(Get-AnajakFreshComposeArguments -Backend $backend -Runtime)
        # Older Compose versions fail safely here before any builds or startup.
        Invoke-AnajakFreshDocker ($runtimeCompose + @('config','--quiet'))
        $fingerprint = Get-AnajakReadySourceFingerprint $backend
        $statePath = Join-Path $backend '.local/fresh-v12-build.json'
        $built = $false
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            try { $built = ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json).fingerprint -ceq $fingerprint } catch { }
        }
        $mustBuild = !$hasOracle -or !$built -or !(Test-AnajakFreshImages)
        if ($mustBuild) {
            Write-Host 'Building the isolated Version 12 services. The original backend and database remain untouched.'
            Invoke-AnajakFreshDocker @('run','--rm','--label','com.anajak.fresh.project=anajakmap-v12','--mount',"type=bind,source=$backend,target=/workspace",'--mount','type=volume,source=anajakmap-v12_maven-cache,target=/root/.m2','-w','/workspace','maven:3.9.11-eclipse-temurin-21','mvn','-B','-ntp','package')
            Invoke-AnajakFreshDocker ($schemaCompose + @('build'))
        }
        Invoke-AnajakFreshDocker ($schemaCompose + @('up','-d','oracle','redis','rabbitmq','minio','object-init'))
        $oracleId = Wait-AnajakFreshOracle $schemaCompose
        Invoke-AnajakFreshDocker ($schemaCompose + @('exec','-T','oracle','bash','/container-entrypoint-initdb.d/01-schemas.sh'))
        foreach ($service in (Get-AnajakFreshServices)) {
            Invoke-AnajakFreshDocker ($schemaCompose + @(Get-AnajakFreshMigrationArguments $service))
        }
        Invoke-AnajakFreshDocker @('cp',(Join-Path $backend 'scripts/grant-runtime.sh'),"${oracleId}:/tmp/anajak-v12-grant-runtime.sh")
        Invoke-AnajakFreshDocker ($schemaCompose + @('exec','-T','oracle','bash','/tmp/anajak-v12-grant-runtime.sh'))
        Invoke-AnajakFreshDocker ($runtimeCompose + @('up','-d','--no-build'))
        Wait-AnajakFreshServices $runtimeCompose
        $origin = 'http://127.0.0.1:18090'
        Wait-AnajakReadyProxy $origin
        Assert-AnajakFreshAuthContract $origin
        Invoke-AnajakReadyChildScript -Scripts (Join-Path $backend 'scripts') -Name 'test-laptop.ps1' -Parameters @{BaseUrl=$origin}
        [IO.Directory]::CreateDirectory((Split-Path $statePath -Parent)) > $null
        [IO.File]::WriteAllText($statePath,(@{fingerprint=$fingerprint;project=(Get-AnajakFreshProject);checkedUtc=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        Write-Host 'Version 12 isolated backend is ready: http://127.0.0.1:18090/api/v1/' -ForegroundColor Green
        if ($Public) { Start-AnajakFreshPublic $settings }
    } finally {
        foreach ($name in $before.Keys) { [Environment]::SetEnvironmentVariable($name,$before[$name],'Process') }
        Set-Location -LiteralPath $originalLocation
        $settings = $null
        $snapshots = $null
    }
}
