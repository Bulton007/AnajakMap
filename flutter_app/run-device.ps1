param(
    [string]$DeviceId,
    [ValidateRange(1,65535)][int]$BackendPort = $(if ($env:GATEWAY_HTTP_PORT) { [int]$env:GATEWAY_HTTP_PORT } else { 8080 }),
    [switch]$Test,
    [string]$TestConfig
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\sdk' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (!(Test-Path -LiteralPath $adb)) { throw "Android platform-tools not found at $adb" }
if (!$DeviceId) {
    $devices = @(& $adb devices | Select-String '^([^\s]+)\s+device$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    if ($devices.Count -ne 1) { throw 'Connect one unlocked Android device with USB debugging enabled, or pass -DeviceId.' }
    $DeviceId = $devices[0]
}
$health = Invoke-RestMethod "http://127.0.0.1:$BackendPort/actuator/health/readiness" -TimeoutSec 15
if ($health.status -ne 'UP') { throw 'Backend readiness is not UP. Start the backend first.' }
& $adb -s $DeviceId reverse "tcp:$BackendPort" "tcp:$BackendPort"
if ($LASTEXITCODE -ne 0) { throw 'USB backend forwarding failed.' }
$apiDefine = "--dart-define=API_BASE_URL=http://127.0.0.1:$BackendPort/api/v1/"
Write-Host "Phone $DeviceId -> USB -> gateway port $BackendPort. Keep USB connected."
# Short socket directory avoids Windows/MSIX Java loopback path failures.
$socketDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) '.java-tmp'
New-Item -ItemType Directory -Force -Path $socketDirectory | Out-Null
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
try {
    $env:JAVA_TOOL_OPTIONS = "$previousJavaOptions -Djdk.net.unixdomain.tmpdir=$socketDirectory".Trim()
    if ($Test) {
        if (!$TestConfig -or !(Test-Path -LiteralPath $TestConfig)) { throw 'Pass -TestConfig with a local JSON containing AUTH_TEST_EMAIL and AUTH_TEST_PASSWORD for a dedicated, already verified test account. See AUTH_SETUP.md.' }
        flutter test integration_test/connected_device_test.dart -d $DeviceId --dart-define-from-file=config/connected.usb.json "--dart-define-from-file=$TestConfig" $apiDefine
    } else {
        flutter run -d $DeviceId --dart-define-from-file=config/connected.usb.json $apiDefine
    }
    $result = $LASTEXITCODE
} finally {
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
}
exit $result
