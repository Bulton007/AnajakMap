param(
    [string]$DeviceId,
    [ValidateRange(1,65535)][int]$BackendPort = 8090,
    [ValidateRange(1,65535)][int]$DevicePort = 8080
)
$ErrorActionPreference = 'Stop'

try {
    $adbCommand = Get-Command adb.exe -ErrorAction SilentlyContinue
    $adbPath = if ($adbCommand) { $adbCommand.Source } else { $null }
    if (!$adbPath) {
        $sdkCandidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
        if ($env:LOCALAPPDATA) { $sdkCandidates += Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
        foreach ($sdkFolder in $sdkCandidates) {
            if ([string]::IsNullOrWhiteSpace($sdkFolder)) { continue }
            $candidate = Join-Path $sdkFolder 'platform-tools\adb.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $adbPath = $candidate; break }
        }
    }
    if (!$adbPath) { throw 'Android platform-tools were not found. Install them or configure ANDROID_HOME / ANDROID_SDK_ROOT.' }

    function Invoke-Adb {
        param([string[]]$Arguments)
        $previousPreference = $ErrorActionPreference
        try {
            # PowerShell 5.1 may turn native startup stderr into an ErrorRecord.
            $ErrorActionPreference = 'Continue'
            $output = @(& $adbPath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
            $nativeExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($nativeExit -ne 0) { throw "ADB failed (exit $nativeExit). Check USB debugging and reconnect the phone." }
        return $output
    }

    $devices = @()
    foreach ($line in (Invoke-Adb -Arguments @('devices'))) {
        if ($line -match '^\s*(\S+)\s+(device|unauthorized|offline)\b') {
            $devices += [pscustomobject]@{ Id = $matches[1]; State = $matches[2] }
        }
    }
    if ($DeviceId) {
        $selected = @($devices | Where-Object { $_.Id -eq $DeviceId })
        if ($selected.Count -ne 1) { throw 'The requested Android device is not connected. Check its DeviceId and USB cable.' }
    } else {
        if ($devices.Count -eq 0) { throw 'Connect one unlocked Android phone with USB debugging enabled.' }
        if ($devices.Count -gt 1) { throw 'Multiple Android devices are connected. Run connect-device.ps1 with -DeviceId to select one.' }
        $selected = @($devices[0])
    }
    if ($selected[0].State -eq 'unauthorized') { throw 'Unlock the phone and allow USB debugging from this computer, then try again.' }
    if ($selected[0].State -ne 'device') { throw 'The selected phone is offline. Reconnect its USB cable and try again.' }
    $selectedId = $selected[0].Id

    $apiUrl = "http://127.0.0.1:$BackendPort/api/v1/auth/config"
    try {
        $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 10
        $config = $response.Content | ConvertFrom-Json
        if ($response.StatusCode -ne 200 -or $null -eq $config.data) { throw 'Unexpected API response.' }
    } catch {
        throw "The local backend API is not ready on port $BackendPort. Start the backend and check its Nginx port before reconnecting the phone. No USB forwarding was changed."
    }

    Invoke-Adb -Arguments @('-s', $selectedId, 'reverse', "tcp:$DevicePort", "tcp:$BackendPort") | Out-Null
    $mapping = @(Invoke-Adb -Arguments @('-s', $selectedId, 'reverse', '--list'))
    $expected = '(?:^|\s)tcp:' + $DevicePort + '\s+tcp:' + $BackendPort + '(?:\s|$)'
    if (!($mapping | Where-Object { $_ -match $expected })) { throw 'ADB did not confirm the requested forwarding rule. Reconnect the phone and try again.' }

    Write-Host "Connected phone $selectedId to the local backend: phone port $DevicePort -> PC port $BackendPort." -ForegroundColor Green
    Write-Host 'Keep USB connected. Return to Anajak Test and retry the failed action once.'
    Write-Host 'No app was rebuilt, restarted or reinstalled. Sign-in inputs and app data were preserved.'
    exit 0
} catch {
    Write-Host "Phone connection failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
