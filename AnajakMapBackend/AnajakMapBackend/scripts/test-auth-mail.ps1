param()
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$normal = @('compose', '-f', 'compose.yml', '-f', 'compose.media-source.yml', '-f', 'compose.local.yml', '-f', 'compose.runtime.yml')
$test = $normal + @('-f', 'compose.auth-test.yml')
$oldKey = $env:MAIL_TEST_KEY
$oldInbox = $env:MAIL_TEST_INBOX_URL
$env:MAIL_TEST_KEY = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$env:MAIL_TEST_INBOX_URL = 'http://127.0.0.1:8095/code'
$result = 1
try {
    & docker @test up -d --no-deps mail-test-sink identity-service
    if ($LASTEXITCODE -ne 0) { throw 'Could not start isolated mail adapter' }
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        try {
            $config = Invoke-RestMethod 'http://127.0.0.1:8080/api/v1/auth/config'
            if ($config.data.policyVersion -eq 'automated-test-only') { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'Test identity service did not become ready' }
    python scripts/smoke.py
    $result = $LASTEXITCODE
} finally {
    & docker @normal up -d --no-deps identity-service
    $restoreResult = $LASTEXITCODE
    & docker @test rm -s -f mail-test-sink
    $env:MAIL_TEST_KEY = $oldKey
    $env:MAIL_TEST_INBOX_URL = $oldInbox
    if ($restoreResult -ne 0) { throw 'Normal identity configuration could not be restored. Run scripts/start-local.ps1 -SkipBuild.' }
}
exit $result
