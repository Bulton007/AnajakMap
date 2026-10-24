# Windows PowerShell 5.1 integration checks. All Docker/HTTP calls are simulated.
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$suite = Join-Path $workspace ('.local/tunnel-tests-' + [guid]::NewGuid().ToString('N'))
$passed = 0
foreach ($mode in @('Single', 'Multiple', 'Empty')) {
    $root = Join-Path $suite $mode
    $scripts = Join-Path $root 'AnajakMapBackend/AnajakMapBackend/scripts'
    $config = Join-Path $root 'flutter_app/config/connected.public.local.json'
    New-Item -ItemType Directory -Path $scripts,(Split-Path $config -Parent) -Force > $null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-laptop.ps1') -Destination (Join-Path $scripts 'start-laptop.ps1')
    [IO.File]::WriteAllText((Join-Path (Split-Path $scripts -Parent) '.env'), 'FAKE_TEST_ONLY=unchanged')
    [IO.File]::WriteAllText($config, '{"APP_MODE":"connected","API_BASE_URL":"https://keep.example/api/v1/"}')
    $before = (Get-FileHash -LiteralPath $config).Hash
    $wrapper = @'
param([string]$Mode)
$ErrorActionPreference = 'Stop'
$global:TunnelTestMode = $Mode
$global:TunnelFixture = $PSScriptRoot
function global:docker {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'info') { return 'fixture-engine' }
    if ($args[0] -eq 'compose') {
        if ($args -contains 'ps') { return 'fixture-tunnel' }
        return
    }
    if ($args[0] -eq 'inspect') { return '2026-10-24T05:00:00.000000000Z' }
    if ($args[0] -eq 'logs') {
        $index = [Array]::IndexOf($args, '--since')
        if ($index -lt 0) {
            return @('https://stale-session.trycloudflare.com', 'https://new-session.trycloudflare.com')
        }
        if ($args[$index+1] -ne '2026-10-24T05:00:00.000000000Z') { throw 'Incorrect log session boundary' }
        [IO.File]::WriteAllText((Join-Path $global:TunnelFixture 'since-ok.txt'), 'current-session')
        if ($global:TunnelTestMode -eq 'Empty') { return }
        if ($global:TunnelTestMode -eq 'Multiple') {
            return @('https://new-session.trycloudflare.com', 'https://latest-session.trycloudflare.com')
        }
        return 'https://new-session.trycloudflare.com'
    }
    throw 'Unexpected Docker operation in fixture'
}
function global:Invoke-WebRequest { return [pscustomobject]@{StatusCode=200} }
function global:Start-Sleep {}
try {
    & (Join-Path $PSScriptRoot 'AnajakMapBackend/AnajakMapBackend/scripts/start-laptop.ps1') -TemporaryPublicUrl
    exit 0
} catch {
    Write-Output $_.Exception.Message
    exit 1
}
'@
    $wrapperPath = Join-Path $root 'run.ps1'
    [IO.File]::WriteAllText($wrapperPath, $wrapper)
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapperPath -Mode $mode 2>&1
    $code = $LASTEXITCODE
    if (!(Test-Path -LiteralPath (Join-Path $root 'since-ok.txt'))) { throw "$mode did not limit logs to the current session." }
    if ($mode -eq 'Empty') {
        if ($code -ne 1 -or ($output -join "`n") -notmatch 'Tunnel address is not available' -or (Get-FileHash -LiteralPath $config).Hash -ne $before) {
            throw 'Empty current-session logs must fail without overwriting the saved URL.'
        }
        Write-Host 'PASS Empty current-session logs retain the existing configuration and fail safely'
    } else {
        $expected = if ($mode -eq 'Multiple') { 'https://latest-session.trycloudflare.com/api/v1/' } else { 'https://new-session.trycloudflare.com/api/v1/' }
        $actual = [IO.File]::ReadAllText($config) | ConvertFrom-Json
        if ($code -ne 0 -or $actual.API_BASE_URL -ne $expected) { throw "$mode selected an incorrect tunnel URL." }
        Write-Host "PASS $mode current-session URLs exclude retained logs and select the latest address"
    }
    $passed++
}
Write-Host "Tunnel startup regression tests: $passed passed, 0 failed. No real Docker or HTTP calls."
