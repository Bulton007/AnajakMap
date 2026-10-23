param([switch]$SkipBuild, [switch]$OfficialOracle)
$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
function Invoke-Docker([string[]]$Arguments) {
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed (exit $LASTEXITCODE). Check the preceding output." }
}
Invoke-Docker -Arguments @('info','--format','{{.ServerVersion}}')
if (-not (Test-Path -LiteralPath '.env')) { & "$PSScriptRoot/init-dev.ps1" }
$compose=@('compose','-f','compose.yml')
if($OfficialOracle){$compose+=@('-f','compose.oracle-official.yml')}
$compose+=@('-f','compose.media-source.yml','-f','compose.local.yml')
if (-not $SkipBuild) {
    $source=(Get-Location).Path
    Invoke-Docker -Arguments @('run','--rm','--mount',"type=bind,source=$source,target=/workspace",'--mount','type=volume,source=anajak-maven-cache,target=/root/.m2','-w','/workspace','maven:3.9.11-eclipse-temurin-21','mvn','-B','-ntp','package')
    Invoke-Docker ($compose+@('build'))
}
Invoke-Docker ($compose+@('up','-d','oracle','redis','rabbitmq','minio','object-init'))
$ready=$false
for($attempt=0;$attempt -lt 180;$attempt++) {
    $oracleId=& docker @compose ps -q oracle
    if($oracleId) {
        $health=& docker inspect --format '{{.State.Health.Status}}' $oracleId
        if($health -eq 'healthy') {$ready=$true;break}
    }
    Start-Sleep -Seconds 5
}
if(-not $ready){throw 'Oracle did not become healthy within 15 minutes.'}
$schemaPath=if($OfficialOracle){'/opt/oracle/scripts/setup/01-schemas.sh'}else{'/container-entrypoint-initdb.d/01-schemas.sh'}
Invoke-Docker ($compose+@('exec','-T','oracle','bash',$schemaPath))
foreach($service in @('identity','trip','ai-guide','discovery','expense','reservation','journal','notification','gateway')) {
    Invoke-Docker ($compose+@('run','--rm','--no-deps','-e','MIGRATE_ONLY=true',"$service-service"))
}
$oracleId=& docker @compose ps -q oracle
Invoke-Docker -Arguments @('cp','scripts/grant-runtime.sh',"${oracleId}:/tmp/anajak-grant-runtime.sh")
Invoke-Docker ($compose+@('exec','-T','oracle','bash','/tmp/anajak-grant-runtime.sh'))
Invoke-Docker ($compose+@('-f','compose.runtime.yml','up','-d'))
$gatewayPort=if($env:GATEWAY_HTTP_PORT){$env:GATEWAY_HTTP_PORT}else{'8080'}
Write-Host "Gateway: http://127.0.0.1:$gatewayPort. Wait for /actuator/health/readiness before using Flutter."

