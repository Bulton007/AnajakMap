$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if(Test-Path -LiteralPath '.env'){throw '.env already exists; refusing to overwrite.'}
function Random-Hex([int]$count=24) {
    $bytes=[byte[]]::new($count)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToHexString($bytes)
}
$rsa=[System.Security.Cryptography.RSA]::Create(3072)
try {
    $values=[ordered]@{
        ORACLE_PASSWORD=(Random-Hex)
        REDIS_PASSWORD=(Random-Hex)
        RABBIT_USER='anajak'
        RABBIT_PASSWORD=(Random-Hex)
        OBJECT_ACCESS_KEY='anajak-local'
        OBJECT_SECRET_KEY=(Random-Hex)
        SERVICE_TOKEN=(Random-Hex 32)
        DATA_ENCRYPTION_KEY=[Convert]::ToBase64String([Convert]::FromHexString((Random-Hex 32)))
        JWT_PUBLIC_KEY=[Convert]::ToBase64String($rsa.ExportSubjectPublicKeyInfo())
        JWT_PRIVATE_KEY=[Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey())
    }
    foreach($service in @('IDENTITY','TRIP','AI_GUIDE','DISCOVERY','EXPENSE','RESERVATION','JOURNAL','NOTIFICATION','GATEWAY')) {
        $values["${service}_DB_PASSWORD"]=Random-Hex
        $values["${service}_APP_PASSWORD"]=Random-Hex
    }
    $lines=$values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    [IO.File]::WriteAllLines((Join-Path (Get-Location) '.env'),$lines)
    Write-Host 'Created local development credentials in ignored .env. Existing databases require their original credentials.'
} finally {$rsa.Dispose()}
