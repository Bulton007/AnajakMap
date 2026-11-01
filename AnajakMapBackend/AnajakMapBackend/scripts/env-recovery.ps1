# Pure recovery rules. Values must never be written to the console or logs.
function Get-AnajakRecoveryRequiredKeys {
    $keys = @('ORACLE_PASSWORD','REDIS_PASSWORD','RABBIT_USER','RABBIT_PASSWORD',
        'OBJECT_ACCESS_KEY','OBJECT_SECRET_KEY','SERVICE_TOKEN','DATA_ENCRYPTION_KEY',
        'JWT_PUBLIC_KEY','JWT_PRIVATE_KEY')
    foreach ($schema in @('IDENTITY','TRIP','AI_GUIDE','DISCOVERY','EXPENSE',
        'RESERVATION','JOURNAL','NOTIFICATION','GATEWAY')) {
        $keys += "${schema}_DB_PASSWORD", "${schema}_APP_PASSWORD"
    }
    return $keys
}

function Assert-AnajakRecoveryOracleVolume {
    param([object[]]$Mounts, [string]$ExpectedVolume)
    $matches = @($Mounts | Where-Object { $_.Destination -eq '/opt/oracle/oradata' })
    if ($matches.Count -ne 1 -or $matches[0].Type -ne 'volume' -or $matches[0].Name -ne $ExpectedVolume) {
        throw 'Oracle is not attached to the expected project data volume. No configuration was written.'
    }
}

function Get-AnajakRecoveredSettings {
    param([object[]]$Snapshots)
    $required = @(Get-AnajakRecoveryRequiredKeys)
    $allowed = $required + @('GMAIL_USERNAME','GMAIL_APP_PASSWORD','AUTH_TERMS_URL',
        'AUTH_PRIVACY_URL','AUTH_POLICY_VERSION','AUTH_LINK_BASE','MAIL_PROVIDER_URL',
        'MAIL_PROVIDER_KEY','AI_PROVIDER','GEMINI_API_KEY','GEMINI_MODEL',
        'GEMINI_VISION_ENABLED','GEMINI_VOICE_ENABLED','OSRM_URL','OSRM_DEMO_ENABLED',
        'WEATHER_PROVIDER','RPG_SIMULATION_ENABLED','RPG_ENCOUNTER_TTL_SECONDS',
        'PHOTON_BASE_URL','APP_KHR_PER_USD')
    $values = @{}
    foreach ($snapshot in $Snapshots) {
        $environment = @{}
        foreach ($entry in $snapshot.Environment) {
            $separator = ([string]$entry).IndexOf('=')
            if ($separator -lt 1) { continue }
            $environment[$entry.Substring(0,$separator)] = $entry.Substring($separator+1)
        }
        $candidates = @{}
        foreach ($key in $allowed) {
            if ($environment.ContainsKey($key)) { $candidates[$key] = $environment[$key] }
        }
        if ($snapshot.Service -eq 'rabbitmq') {
            if ($environment.ContainsKey('RABBITMQ_DEFAULT_USER')) { $candidates['RABBIT_USER'] = $environment['RABBITMQ_DEFAULT_USER'] }
            if ($environment.ContainsKey('RABBITMQ_DEFAULT_PASS')) { $candidates['RABBIT_PASSWORD'] = $environment['RABBITMQ_DEFAULT_PASS'] }
        }
        if ($snapshot.Service -eq 'minio') {
            if ($environment.ContainsKey('MINIO_ROOT_USER')) { $candidates['OBJECT_ACCESS_KEY'] = $environment['MINIO_ROOT_USER'] }
            if ($environment.ContainsKey('MINIO_ROOT_PASSWORD')) { $candidates['OBJECT_SECRET_KEY'] = $environment['MINIO_ROOT_PASSWORD'] }
        }
        $schema = ([string]$snapshot.Service).Replace('-service','').Replace('-','_').ToUpperInvariant()
        if ($snapshot.Service -like '*-service' -and $environment.ContainsKey('DB_PASSWORD')) {
            if ($environment['DB_USER'] -eq "${schema}_APP") { $candidates["${schema}_APP_PASSWORD"] = $environment['DB_PASSWORD'] }
            elseif ($environment['DB_USER'] -eq $schema) { $candidates["${schema}_DB_PASSWORD"] = $environment['DB_PASSWORD'] }
        }
        foreach ($key in $candidates.Keys) {
            $value = [string]$candidates[$key]
            if ([string]::IsNullOrEmpty($value)) { continue }
            if ($values.ContainsKey($key) -and $values[$key] -cne $value) {
                throw "Recorded containers disagree about $key. No configuration was written."
            }
            $values[$key] = $value
        }
    }
    $missing = @($required | Where-Object { !$values.ContainsKey($_) })
    if ($missing.Count) {
        throw ('Incomplete recovery; missing setting names: ' + ($missing -join ', ') + '. Restore a matching backup. No new credentials were generated.')
    }
    return $values
}

function ConvertTo-AnajakRecoveredEnv {
    param([hashtable]$Settings)
    $lines = @('# Recovered from this Docker project; keep private and out of Git.')
    foreach ($key in @($Settings.Keys | Sort-Object)) {
        if ($key -notmatch '^[A-Z][A-Z0-9_]*$') { throw 'Invalid recovered setting name.' }
        $value = [string]$Settings[$key]
        # Single quotes prevent Compose interpolation of dollar signs. Reject
        # ambiguous quoting rather than silently changing any credential bytes.
        if ($value.IndexOfAny([char[]]@(0,10,13,39,92)) -ge 0) {
            throw "Setting $key needs manual quote-safe recovery. No configuration was written."
        }
        $lines += ($key + "='" + $value + "'")
    }
    return (($lines -join "`r`n") + "`r`n")
}
