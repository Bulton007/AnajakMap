param([string]$BaseUrl = 'http://127.0.0.1:8090')
$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')
function Get-Status([string]$Path) {
    try {
        return [int](Invoke-WebRequest "$BaseUrl$Path" -UseBasicParsing -TimeoutSec 15).StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        throw
    }
}
foreach ($check in @(
    @('/api/v1/auth/config', 200),
    @('/api/v1/profile', 401),
    @('/actuator/health', 404),
    @('/swagger-ui/index.html', 404),
    @('/internal', 404)
)) {
    $status = Get-Status $check[0]
    if ($status -ne $check[1]) { throw "$($check[0]) returned $status, expected $($check[1])." }
    Write-Host "$($check[0]): $status"
}
Write-Host 'Proxy routing, authentication boundary and blocked internal paths passed.'
$auth = Invoke-RestMethod "$BaseUrl/api/v1/auth/config" -TimeoutSec 15
if ($auth.data.emailDelivery -ne $true) {
    Write-Warning 'Email delivery is disabled. Run Configure Email.cmd on this hosting PC before testing registration or recovery.'
} elseif ($auth.data.registration -ne $true) {
    Write-Warning 'Registration is disabled. Check the Terms URL, Privacy URL and policy version in the backend .env.'
} else {
    Write-Host 'Registration and email delivery are configured. Verify actual inbox delivery with your own test account.'
}
