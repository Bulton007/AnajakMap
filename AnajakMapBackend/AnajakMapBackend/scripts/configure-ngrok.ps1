$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ngrok-command.ps1')
try {
    $agent = Get-AnajakNgrokCommand
    Write-Host 'Sign in at https://dashboard.ngrok.com/get-started/your-authtoken'
    Write-Host 'Copy YOUR account authtoken. Paste it below; the characters are hidden.'
    Write-Host 'Do not paste it into chat or commit it to Git.'
    $secureToken = Read-Host 'ngrok authtoken' -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ([string]::IsNullOrWhiteSpace($token) -or $token -match '\s' -or $token.StartsWith('-')) {
            throw 'Paste just the authtoken value, without the command or surrounding spaces.'
        }
        # The official agent stores its account credential in the user profile,
        # outside the source tree. Suppress native output to keep it out of logs.
        & $agent config add-authtoken $token *> $null
        if ($LASTEXITCODE -ne 0) { throw 'ngrok could not save the token. Check the agent installation and try again.' }
    } finally {
        $token = $null
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($secureToken) { $secureToken.Dispose() }
    }
    & $agent config check *> $null
    if ($LASTEXITCODE -ne 0) { throw 'The saved ngrok configuration did not pass validation.' }
    Write-Host 'Saved locally. This checks configuration; the server will confirm the account when the tunnel starts.' -ForegroundColor Green
    Write-Host 'Next: run Start Public Backend.cmd and keep its window open.'
    exit 0
} catch {
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
