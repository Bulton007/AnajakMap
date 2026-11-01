$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env-recovery.ps1')
$passed = 0
function Assert-Recovery([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "Recovery regression failed: $Name" }
    $script:passed++
}
function Assert-RecoveryThrows([scriptblock]$Action,[string]$Name) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-Recovery $failed $Name
}
$original = @{}
foreach ($key in @(Get-AnajakRecoveryRequiredKeys)) { $original[$key] = 'synthetic-' + $key }
$entries = @($original.Keys | ForEach-Object { $_ + '=' + $original[$_] })
$source = @([pscustomobject]@{Service='oracle';Environment=$entries})
$result = Get-AnajakRecoveredSettings $source
Assert-Recovery ($result.Count -eq 28) 'all required settings are present'
Assert-Recovery ($result['IDENTITY_APP_PASSWORD'] -ceq $original['IDENTITY_APP_PASSWORD']) 'runtime password bytes preserved'
$missing = @($entries | Where-Object { $_ -notlike 'JWT_PRIVATE_KEY=*' })
Assert-RecoveryThrows { Get-AnajakRecoveredSettings @([pscustomobject]@{Service='oracle';Environment=$missing}) } 'missing signing key refuses recovery'
$conflict = $source + @([pscustomobject]@{Service='identity-service';Environment=@('SERVICE_TOKEN=different-synthetic-value')})
Assert-RecoveryThrows { Get-AnajakRecoveredSettings $conflict } 'conflicting existing credentials refuse recovery'
$aliasEntries = @($entries | Where-Object { $_ -notmatch '^(RABBIT_USER|RABBIT_PASSWORD|OBJECT_ACCESS_KEY|OBJECT_SECRET_KEY)=' })
$aliasSources = @([pscustomobject]@{Service='oracle';Environment=$aliasEntries},
    [pscustomobject]@{Service='rabbitmq';Environment=@('RABBITMQ_DEFAULT_USER=synthetic-RABBIT_USER','RABBITMQ_DEFAULT_PASS=synthetic-RABBIT_PASSWORD')},
    [pscustomobject]@{Service='minio';Environment=@('MINIO_ROOT_USER=synthetic-OBJECT_ACCESS_KEY','MINIO_ROOT_PASSWORD=synthetic-OBJECT_SECRET_KEY')})
$aliasResult = Get-AnajakRecoveredSettings $aliasSources
Assert-Recovery ($aliasResult['OBJECT_SECRET_KEY'] -ceq $original['OBJECT_SECRET_KEY'] -and $aliasResult['RABBIT_PASSWORD'] -ceq $original['RABBIT_PASSWORD']) 'infrastructure aliases preserve values'
$runtimeSources = @([pscustomobject]@{Service='oracle';Environment=@($entries | Where-Object { $_ -notlike 'IDENTITY_APP_PASSWORD=*' })},
    [pscustomobject]@{Service='identity-service';Environment=@('DB_USER=IDENTITY_APP','DB_PASSWORD=synthetic-IDENTITY_APP_PASSWORD')})
$runtime = Get-AnajakRecoveredSettings $runtimeSources
Assert-Recovery ($runtime['IDENTITY_APP_PASSWORD'] -ceq $original['IDENTITY_APP_PASSWORD']) 'runtime DB role maps to correct original key'
$validMount = @([pscustomobject]@{Destination='/opt/oracle/oradata';Type='volume';Name='anajakmap_oracle-data'})
Assert-AnajakRecoveryOracleVolume $validMount 'anajakmap_oracle-data'
$passed++
Assert-RecoveryThrows { Assert-AnajakRecoveryOracleVolume $validMount 'different_oracle-data' } 'wrong database volume rejected'
$literal = ConvertTo-AnajakRecoveredEnv @{SERVICE_TOKEN='synthetic$literal#value=with space'}
Assert-Recovery ($literal.Contains("SERVICE_TOKEN='synthetic`$literal#value=with space'")) 'dotenv quoting prevents dollar interpolation'
Assert-RecoveryThrows { ConvertTo-AnajakRecoveredEnv @{SERVICE_TOKEN="unsafe'quote"} } 'ambiguous quotes never change credential bytes'
Assert-RecoveryThrows { ConvertTo-AnajakRecoveredEnv @{SERVICE_TOKEN="bad`nline"} } 'multiline values rejected'
Assert-RecoveryThrows { Get-AnajakRecoveredSettings @() } 'no containers does not generate replacements'
Write-Host "$passed recovery regression checks passed. Only synthetic settings were used."
