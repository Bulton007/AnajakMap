# Run on the PC hosting the backend. Compatible with Windows PowerShell 5.1.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$client = $null
$message = $null
$secret = $null
try {
    Set-Location (Split-Path $PSScriptRoot -Parent)
    if (!(Test-Path -LiteralPath '.env')) {
        throw 'Initialize the backend using Start Backend.cmd before configuring Gmail.'
    }
    & docker info --format '{{.ServerVersion}}' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Open Docker Desktop and wait for the Linux engine to start.' }
    Write-Host 'Configure the Gmail sender on this hosting PC.'
    Write-Host 'A test email will be sent only to the sender address you enter.'
    Write-Host 'Use a Google App Password, not your normal Google password. Input is hidden.'
    $sender = (Read-Host 'Sender Gmail or Google Workspace address').Trim()
    try { $address = New-Object System.Net.Mail.MailAddress($sender) } catch {
        throw 'Enter a valid sender email address.'
    }
    if ($address.Address -ne $sender -or $sender -match '[\r\n$#"\s]') {
        throw 'Enter only the email address, without a display name or spaces.'
    }
    $secret = Read-Host 'Google App Password (16 letters)' -AsSecureString
    $credential = New-Object System.Net.NetworkCredential($sender, $secret)
    # Google displays App Passwords in groups; spaces are not part of the password.
    $appPassword = $credential.Password -replace '\s', ''
    if ($appPassword -notmatch '^[a-zA-Z]{16}$') {
        throw 'A Google App Password contains 16 letters. Generate one in your Google Account security settings.'
    }
    $client = New-Object System.Net.Mail.SmtpClient('smtp.gmail.com', 587)
    $client.EnableSsl = $true
    $client.UseDefaultCredentials = $false
    $client.Credentials = New-Object System.Net.NetworkCredential($sender, $appPassword)
    $client.Timeout = 20000
    $message = New-Object System.Net.Mail.MailMessage($sender, $sender)
    $message.Subject = 'AnajakMap sender setup test'
    $message.Body = 'Gmail accepted this AnajakMap setup test. Check your inbox or spam folder. This is not a verification code and does not create an account.'
    Write-Host 'Testing Gmail authentication and sending one setup email...'
    try { $client.Send($message) } catch {
        throw 'Gmail did not accept the test. Check the sender/App Password, Google two-step verification, and outbound access to smtp.gmail.com:587. No settings were changed.'
    }
    $envPath = Join-Path (Get-Location) '.env'
    $content = [IO.File]::ReadAllText($envPath)
    foreach ($setting in @(
        @('GMAIL_USERNAME', $sender),
        @('GMAIL_APP_PASSWORD', $appPassword)
    )) {
        $pattern = '(?m)^' + $setting[0] + '=.*$'
        $line = $setting[0] + '=' + $setting[1]
        if ([regex]::IsMatch($content, $pattern)) {
            $content = [regex]::Replace($content, $pattern, $line)
        } else { $content += "`r`n$line`r`n" }
    }
    [IO.File]::WriteAllText($envPath, $content, (New-Object Text.UTF8Encoding($false)))
    $appPassword = $null
    $content = $null
    Write-Host 'Gmail accepted the test. Sender settings saved locally; do not share or commit .env.'
    $compose = @('compose', '-f', 'compose.yml', '-f', 'compose.media-source.yml',
        '-f', 'compose.local.yml', '-f', 'compose.runtime.yml', '-f', 'compose.laptop.yml')
    & docker @compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Compose validation failed. Settings were saved; resolve configuration before restarting.' }
    # Recreate only identity. Leave the running public tunnel and its URL intact.
    & docker @compose up -d --no-deps --no-build identity-service
    if ($LASTEXITCODE -ne 0) { throw 'Could not restart identity. Settings were saved; run Start Backend.cmd.' }
    $port = if ($env:LAPTOP_NGINX_PORT) { $env:LAPTOP_NGINX_PORT } else { '8090' }
    $ready = $false
    Write-Host 'Waiting for the authentication service...'
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        try {
            $result = Invoke-RestMethod "http://127.0.0.1:$port/api/v1/auth/config" -TimeoutSec 3
            if ($result.data.emailDelivery -eq $true -and $result.data.registration -eq $true) {
                $ready = $true
                break
            }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'Registration is not ready. Check identity logs and Terms/Privacy/policy-version settings. The Gmail test alone does not verify registration.' }
    Write-Host 'Email delivery and registration are enabled.' -ForegroundColor Green
    Write-Host 'Now register using your own test email in the phone app, check the received code, verify, then sign in.'
    Write-Host 'SMTP acceptance does not guarantee inbox placement; check spam and Google sending limits.'
    exit 0
} catch {
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    $appPassword = $null
    $credential = $null
    if ($secret) { $secret.Dispose() }
    if ($message) { $message.Dispose() }
    if ($client) { $client.Dispose() }
}
