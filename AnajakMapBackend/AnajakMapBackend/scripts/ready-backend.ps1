# Portable startup orchestration. Never print configuration or container environments.

function Read-AnajakReadySettings([string]$Path) {
    . (Join-Path $PSScriptRoot 'ai-settings.ps1')
    $settings = @{}
    foreach ($line in ([IO.File]::ReadAllText($Path) -split "`r?`n")) {
        if ($line -match '^\s*(?:export\s+)?([A-Z][A-Z0-9_]*(?:\(X86\))?)=(.*)$') {
            $settings[$matches[1]] = ConvertFrom-AnajakAiDotEnvValue $matches[2]
        }
    }
    return $settings
}

function Get-AnajakReadyRequiredKeys {
    . (Join-Path $PSScriptRoot 'env-recovery.ps1')
    return @(Get-AnajakRecoveryRequiredKeys)
}

function Assert-AnajakReadySettings([hashtable]$Settings) {
    $reserved = @('PATH','PATHEXT','HOME','HOMEDRIVE','HOMEPATH','USERPROFILE','CODEX_HOME',
        'TEMP','TMP','SYSTEMROOT','COMSPEC','PSMODULEPATH','PROGRAMFILES','PROGRAMFILES(X86)',
        'PROGRAMW6432','COMMONPROGRAMFILES','COMMONPROGRAMFILES(X86)','COMMONPROGRAMW6432',
        'APPDATA','LOCALAPPDATA','ALLUSERSPROFILE','PROGRAMDATA','WINDIR','USERNAME','USERDOMAIN',
        'COMPUTERNAME','OS','PROCESSOR_ARCHITECTURE','NUMBER_OF_PROCESSORS','JAVA_HOME',
        'MAVEN_HOME','GRADLE_HOME','PYTHONHOME','PYTHONPATH','NODE_PATH')
    if (@($Settings.Keys | Where-Object { $_ -in $reserved }).Count) {
        throw 'Private configuration contains reserved system environment names. Remove system overrides from the backend .env; no configuration was adopted or services started.'
    }
    if ($Settings.ContainsKey('COMPOSE_PROJECT_NAME') -and
        ![string]::IsNullOrWhiteSpace([string]$Settings['COMPOSE_PROJECT_NAME']) -and
        [string]$Settings['COMPOSE_PROJECT_NAME'] -cne 'anajakmap') {
        throw 'This ready bundle supports the anajakmap Compose project only. Use the existing project workflow for a custom COMPOSE_PROJECT_NAME; no configuration was adopted or services started.'
    }
    $missing = @(Get-AnajakReadyRequiredKeys | Where-Object { !$Settings.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$Settings[$_]) })
    if ($missing.Count) { throw ('Required private configuration is incomplete. Missing setting names: ' + ($missing -join ', ') + '. Restore the matching original configuration; no credentials were generated.') }
}

function Test-AnajakReadyDocker {
    try {
        $kind = @(& docker info --format '{{.OSType}}' 2>$null)
        return $LASTEXITCODE -eq 0 -and ($kind -join '').Trim() -eq 'linux'
    } catch { return $false }
}

function Wait-AnajakReadyDocker {
    if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
        $folder = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
        if (!(Test-Path -LiteralPath (Join-Path $folder 'docker.exe'))) { throw 'Install Docker Desktop with its Linux-container engine first.' }
        $env:PATH = "$folder;$env:PATH"
    }
    if (Test-AnajakReadyDocker) { return }
    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (!(Test-Path -LiteralPath $desktop)) { throw 'Open Docker Desktop and switch to its Linux-container engine before starting.' }
    Start-Process -FilePath $desktop -WindowStyle Hidden
    Write-Host 'Waiting for the Docker Desktop Linux engine...'
    $deadline = (Get-Date).AddMinutes(4)
    while (!(Test-AnajakReadyDocker)) {
        if ((Get-Date) -ge $deadline) { throw 'Docker Linux engine did not become ready. Resolve the Docker Desktop startup prompt and retry.' }
        Start-Sleep -Seconds 3
    }
}

function Test-AnajakReadyOracleVolume {
    $names = @(& docker volume ls --filter 'name=^anajakmap_oracle-data$' --format '{{.Name}}' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect existing Oracle data. No private configuration was copied or services started.' }
    return @($names | Where-Object { [string]$_ -eq 'anajakmap_oracle-data' }).Count -gt 0
}

function Get-AnajakReadySnapshots {
    $services = @('oracle','redis','rabbitmq','minio','identity-service','trip-service','ai-guide-service','discovery-service','expense-service','reservation-service','journal-service','notification-service','gateway-service')
    $snapshots = @()
    foreach ($service in $services) {
        $ids = @(& docker ps -a --filter 'label=com.docker.compose.project=anajakmap' --filter "label=com.docker.compose.service=$service" --format '{{.ID}}' 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Could not verify the existing Docker project. No services were changed.' }
        $ids = @($ids | Where-Object { [string]$_ -match '\A[a-fA-F0-9]{12,64}\z' })
        if ($ids.Count -gt 1) { throw 'Multiple recorded service containers exist for this project. Resolve the existing hosting checkout before starting this bundle.' }
        if (!$ids.Count) { continue }
        $raw = @(& docker inspect --format '{{json .Config.Env}}' $ids[0] 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Could not read recorded container configuration privately. No services were changed.' }
        try { $environment = @(($raw -join "`n") | ConvertFrom-Json) }
        catch { throw 'Could not privately parse the recorded container settings. No services were changed.' }
        $mounts = @()
        if ($service -eq 'oracle') {
            $rawMounts = @(& docker inspect --format '{{json .Mounts}}' $ids[0] 2>$null)
            if ($LASTEXITCODE -ne 0) { throw 'Could not verify the Oracle data mount. No services were changed.' }
            try { $mounts = @(($rawMounts -join "`n") | ConvertFrom-Json) }
            catch { throw 'Could not parse the recorded Oracle data mount. No services were changed.' }
        }
        $snapshots += [pscustomobject]@{Service=$service;Environment=$environment;Mounts=$mounts}
    }
    return $snapshots
}

function Assert-AnajakReadyCredentialMatch {
    param([hashtable]$Settings, [object[]]$Snapshots)
    $oracle = @($Snapshots | Where-Object { $_.Service -eq 'oracle' })
    if ($oracle.Count -ne 1) { throw 'Oracle data exists but its original container is unavailable for a credential check. Restore the original hosting configuration/container record first. The bundled .env was not adopted.' }
    $mount = @($oracle[0].Mounts | Where-Object { $_.Destination -eq '/opt/oracle/oradata' -and $_.Type -eq 'volume' -and $_.Name -eq 'anajakmap_oracle-data' })
    if ($mount.Count -ne 1) { throw 'The recorded Oracle container does not use the expected project data volume. No services were changed.' }
    $allowed = @(Get-AnajakReadyRequiredKeys)
    $oracleRequired = @('ORACLE_PASSWORD') + @($allowed | Where-Object { $_ -match '_(DB|APP)_PASSWORD$' })
    $seenOracle = @{}
    foreach ($snapshot in $Snapshots) {
        $recorded = @{}
        foreach ($entry in $snapshot.Environment) {
            $index = ([string]$entry).IndexOf('=')
            if ($index -gt 0) { $recorded[$entry.Substring(0,$index)] = $entry.Substring($index+1) }
        }
        $candidates = @{}
        foreach ($name in $allowed) {
            if ($recorded.ContainsKey($name)) { $candidates[$name] = [string]$recorded[$name] }
        }
        if ($snapshot.Service -eq 'rabbitmq') {
            if ($recorded.ContainsKey('RABBITMQ_DEFAULT_USER')) { $candidates['RABBIT_USER'] = $recorded['RABBITMQ_DEFAULT_USER'] }
            if ($recorded.ContainsKey('RABBITMQ_DEFAULT_PASS')) { $candidates['RABBIT_PASSWORD'] = $recorded['RABBITMQ_DEFAULT_PASS'] }
        }
        if ($snapshot.Service -eq 'minio') {
            if ($recorded.ContainsKey('MINIO_ROOT_USER')) { $candidates['OBJECT_ACCESS_KEY'] = $recorded['MINIO_ROOT_USER'] }
            if ($recorded.ContainsKey('MINIO_ROOT_PASSWORD')) { $candidates['OBJECT_SECRET_KEY'] = $recorded['MINIO_ROOT_PASSWORD'] }
        }
        if ($snapshot.Service -like '*-service' -and $recorded.ContainsKey('DB_PASSWORD')) {
            $schema = ([string]$snapshot.Service).Replace('-service','').Replace('-','_').ToUpperInvariant()
            if ($recorded['DB_USER'] -eq "${schema}_APP") { $candidates["${schema}_APP_PASSWORD"] = $recorded['DB_PASSWORD'] }
            elseif ($recorded['DB_USER'] -eq $schema) { $candidates["${schema}_DB_PASSWORD"] = $recorded['DB_PASSWORD'] }
        }
        foreach ($name in $candidates.Keys) {
            if ($snapshot.Service -eq 'oracle') { $seenOracle[$name] = $true }
            if (!$Settings.ContainsKey($name) -or [string]$Settings[$name] -cne [string]$candidates[$name]) {
                throw 'The current .env does not match credentials recorded by this Docker project. Keep the initialized hosting folder and its original .env, or use Recover Backend Config.cmd. No services or data were changed.'
            }
        }
    }
    if (@($oracleRequired | Where-Object { !$seenOracle.ContainsKey($_) }).Count) { throw 'The Oracle record cannot verify all existing database credentials. Restore its matching original .env before proceeding. No services were changed.' }
}

function Initialize-AnajakReadyConfiguration {
    param([string]$ProjectRoot, [bool]$OracleVolumeExists)
    $backend = Join-Path $ProjectRoot 'AnajakMapBackend/AnajakMapBackend'
    foreach ($marker in @('compose.yml','pom.xml')) {
        if (!(Test-Path -LiteralPath (Join-Path $backend $marker) -PathType Leaf)) { throw 'Extract the entire backend folder before running its launcher.' }
    }
    $path = Join-Path $backend '.env'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $settings = Read-AnajakReadySettings $path
        Assert-AnajakReadySettings $settings
        return $settings
    }
    if ($OracleVolumeExists) { throw 'Oracle data already exists and this folder has no original .env. The bundled configuration was not copied. Use the initialized hosting folder or Recover Backend Config.cmd; never reset the data volume.' }
    $private = Join-Path $ProjectRoot 'private-config/.env'
    if (!(Test-Path -LiteralPath $private -PathType Leaf)) { throw 'The private configuration is missing. Extract the complete private bundle or restore your original .env. No credentials were generated.' }
    $settings = Read-AnajakReadySettings $private
    Assert-AnajakReadySettings $settings
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $bytes = [IO.File]::ReadAllBytes($private); $stream.Write($bytes,0,$bytes.Length) }
    finally { $stream.Dispose() }
    Write-Host 'Adopted bundled private configuration for a fresh database only. No existing credentials were replaced.'
    return $settings
}

function Get-AnajakReadySourceFingerprint([string]$Backend) {
    # FileInfo.FullName is normalized by the filesystem provider. The launcher's
    # input may still contain relative segments, repeated separators or a short
    # path spelling, so its textual Length is not a valid substring offset.
    # GetRelativePath is unavailable in Windows PowerShell 5.1 / .NET Framework.
    $root = Get-Item -LiteralPath $Backend -ErrorAction Stop
    if ($root -isnot [IO.DirectoryInfo] -or
        ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The backend source must be a regular filesystem directory. No build was started.'
    }
    $rootPath = [IO.Path]::GetFullPath($root.FullName)
    $rootPrefix = $rootPath.TrimEnd([char[]]@('\','/')) + [IO.Path]::DirectorySeparatorChar
    $pending = New-Object 'Collections.Generic.Stack[IO.DirectoryInfo]'
    $pending.Push($root)
    $records = @()
    while ($pending.Count) {
        $directory = $pending.Pop()
        foreach ($entry in (Get-ChildItem -LiteralPath $directory.FullName -ErrorAction Stop)) {
            $entryPath = [IO.Path]::GetFullPath($entry.FullName)
            # Include the separator in the boundary test: a sibling such as
            # backend-backup must never be mistaken for a descendant of backend.
            if (!$entryPath.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) {
                throw 'A backend source path is outside the selected source directory. No build was started.'
            }
            $relative = $entryPath.Substring($rootPrefix.Length).Replace('\','/')
            if ($relative -match '(^|/)(target|build|\.local|\.git|node_modules|private-config)(/|$)') { continue }
            if ($entry.PSIsContainer) {
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw 'A backend source directory is a link or junction. Extract regular source files before starting. No build was started.'
                }
                $pending.Push($entry)
                continue
            }
            if ($entry.Name -notlike 'Dockerfile*' -and $entry.Extension -notin @('.java','.xml','.sql','.yml','.yaml','.sh','.ps1','.properties')) { continue }
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'A backend source file is a link. Extract regular source files before starting. No build was started.'
            }
            $records += $relative + ':' + (Get-FileHash -LiteralPath $entryPath -Algorithm SHA256).Hash
        }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((@($records | Sort-Object) -join "`n")))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-AnajakReadyImages {
    $images = @()
    foreach ($service in @('identity','trip','ai-guide','discovery','expense','reservation','journal','notification','gateway')) {
        $images += "anajakmap-$service-service`:latest"
    }
    $images += 'anajakmap/minio:local-2025-04-22', 'anajakmap/mc:local-2025-04-16'
    foreach ($image in $images) {
        try {
            & docker image inspect $image *> $null
            if ($LASTEXITCODE -ne 0) { return $false }
        } catch { return $false }
    }
    return $true
}

function Invoke-AnajakReadyChildScript {
    param([string]$Scripts, [string]$Name, [hashtable]$Parameters=@{})
    & (Join-Path $Scripts $Name) @Parameters
    if ($LASTEXITCODE -ne 0) { throw "$Name failed. Read its preceding message before retrying." }
}

function Wait-AnajakReadyServices([string]$Scripts) {
    . (Join-Path $Scripts 'backend-readiness.ps1')
    $compose = @('compose','-f','compose.yml','-f','compose.media-source.yml','-f','compose.local.yml','-f','compose.runtime.yml','-f','compose.laptop.yml')
    $ports = [ordered]@{'identity-service'=8081;'trip-service'=8082;'ai-guide-service'=8083;'discovery-service'=8084;'expense-service'=8085;'reservation-service'=8086;'journal-service'=8087;'notification-service'=8088;'gateway-service'=8089}
    foreach ($service in $ports.Keys) {
        $id = @(& docker @compose ps -q $service 2>$null)
        if ($LASTEXITCODE -ne 0 -or $id.Count -ne 1 -or [string]$id[0] -notmatch '\A[a-fA-F0-9]{12,64}\z') { throw "$service does not have one running container after startup." }
        Wait-BackendServiceReady -ContainerId ([string]$id[0]) -Service $service -Port $ports[$service]
        Write-Host "$service readiness is UP."
    }
}

function Wait-AnajakReadyProxy([string]$Origin) {
    $deadline = (Get-Date).AddMinutes(3)
    do {
        try {
            $response = Invoke-WebRequest "$Origin/api/v1/auth/config" -UseBasicParsing -TimeoutSec 4
            $body = $response.Content | ConvertFrom-Json
            if ($response.StatusCode -eq 200 -and $null -ne $body.data) { return }
        } catch { }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 3
    } while ($true)
    throw 'The API behind Nginx did not return valid readiness configuration. Check the local Docker service status.'
}

function Start-AnajakReadyBackend {
    param([string]$ProjectRoot, [switch]$Public)
    $backend = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'AnajakMapBackend/AnajakMapBackend'))
    $scripts = Join-Path $backend 'scripts'
    $before = @{}
    $originalLocation = (Get-Location).Path
    try {
        Wait-AnajakReadyDocker
        $hasOracle = Test-AnajakReadyOracleVolume
        $settings = Initialize-AnajakReadyConfiguration -ProjectRoot $ProjectRoot -OracleVolumeExists $hasOracle
        if ($hasOracle) { Assert-AnajakReadyCredentialMatch -Settings $settings -Snapshots @(Get-AnajakReadySnapshots) }
        foreach ($name in @($settings.Keys) + @('COMPOSE_PROJECT_NAME')) {
            if (!$before.ContainsKey($name)) { $before[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
        }
        foreach ($name in $settings.Keys) { [Environment]::SetEnvironmentVariable($name,[string]$settings[$name],'Process') }
        [Environment]::SetEnvironmentVariable('COMPOSE_PROJECT_NAME','anajakmap','Process')
        Set-Location -LiteralPath $backend
        $fingerprint = Get-AnajakReadySourceFingerprint $backend
        $statePath = Join-Path $backend '.local/ready-bundle-build.json'
        $built = $false
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            try { $built = ([IO.File]::ReadAllText($statePath) | ConvertFrom-Json).fingerprint -eq $fingerprint } catch { }
        }
        if (!$hasOracle -or !$built -or !(Test-AnajakReadyImages)) {
            Write-Host 'Building the bundle and applying existing schema migrations. First startup can take several minutes.'
            Invoke-AnajakReadyChildScript -Scripts $scripts -Name 'start-local.ps1'
        }
        Invoke-AnajakReadyChildScript -Scripts $scripts -Name 'start-laptop.ps1'
        Wait-AnajakReadyServices $scripts
        $port = if ($env:LAPTOP_NGINX_PORT) { $env:LAPTOP_NGINX_PORT } else { '8090' }
        $origin = "http://127.0.0.1:$port"
        Wait-AnajakReadyProxy $origin
        Invoke-AnajakReadyChildScript -Scripts $scripts -Name 'test-laptop.ps1' -Parameters @{BaseUrl=$origin}
        [IO.Directory]::CreateDirectory((Split-Path $statePath -Parent)) > $null
        [IO.File]::WriteAllText($statePath,(@{fingerprint=$fingerprint;checkedUtc=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        Write-Host "Backend service readiness and Nginx boundary checks passed: $origin/api/v1/" -ForegroundColor Green
        Write-Host 'Email delivery and Google model availability still require their own real tests. No provider request was sent by this launcher.'
        if ($Public) { Invoke-AnajakReadyChildScript -Scripts $scripts -Name 'start-ngrok.ps1' }
    } finally {
        foreach ($name in $before.Keys) { [Environment]::SetEnvironmentVariable($name,$before[$name],'Process') }
        Set-Location -LiteralPath $originalLocation
        $settings = $null
    }
}
