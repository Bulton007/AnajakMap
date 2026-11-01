[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8090/api/v1/',
    [switch]$Authenticated,
    [Security.SecureString]$AccessToken,
    [switch]$CheckRoute,
    [switch]$CheckPlaces,
    [switch]$CheckRpgProfile
)
$ErrorActionPreference = 'Stop'

function Test-AnajakContractField($Value, [string]$Name) {
    if ($Value -is [Collections.IDictionary]) { return $Value.Contains($Name) }
    return $null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name]
}
function Get-AnajakContractField($Value, [string]$Name) {
    if ($Value -is [Collections.IDictionary]) { return ,$Value[$Name] }
    if ($null -eq $Value) { return $null }
    return ,$Value.$Name
}
function Assert-AnajakContract([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Test-AnajakContractObject($Value) {
    return $Value -is [Collections.IDictionary] -or $Value -is [Management.Automation.PSCustomObject]
}
function Test-AnajakContractList($Value) {
    return $Value -is [Collections.IList] -and $Value -isnot [string]
}
function Test-AnajakContractNumber($Value) {
    if ($null -eq $Value -or $Value -is [bool] -or $Value -is [string]) { return $false }
    if ($Value -isnot [byte] -and $Value -isnot [sbyte] -and $Value -isnot [System.Int16] -and
        $Value -isnot [System.UInt16] -and $Value -isnot [int] -and $Value -isnot [System.UInt32] -and
        $Value -isnot [long] -and $Value -isnot [System.UInt64] -and $Value -isnot [System.Single] -and
        $Value -isnot [double] -and $Value -isnot [decimal]) { return $false }
    return ![double]::IsNaN([double]$Value) -and ![double]::IsInfinity([double]$Value)
}
function Test-AnajakContractHttps([string]$Value, [string[]]$Hosts = @()) {
    $uri = $null
    if (![Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$uri)) { return $false }
    return $uri.Scheme -eq 'https' -and $uri.Host -and !$uri.UserInfo -and
        ($Hosts.Count -eq 0 -or $uri.Host -in $Hosts)
}
function Assert-AnajakFrontendEnvelope($Document) {
    Assert-AnajakContract ((Test-AnajakContractObject $Document) -and (Test-AnajakContractField $Document 'data')) 'Expected one JSON API envelope with data.'
    $stamp = [DateTimeOffset]::MinValue
    Assert-AnajakContract ([DateTimeOffset]::TryParse([string]$Document.timestamp,[ref]$stamp)) 'API envelope timestamp is missing or invalid.'
    Assert-AnajakContract ($Document.traceId -is [string]) 'API envelope traceId must be a string.'
    return ,(Get-AnajakContractField $Document 'data')
}
function Assert-AnajakAuthConfigContract($Data) {
    foreach ($name in @('emailDelivery','registration','google','apple')) {
        Assert-AnajakContract ((Get-AnajakContractField $Data $name) -is [bool]) "Authentication configuration is missing boolean $name."
    }
    Assert-AnajakContract ($Data.passwordMinLength -eq 12 -and $Data.passwordMaxBytes -eq 72) 'Password limits differ from the current Flutter 12-character/72-byte validation.'
    Assert-AnajakContract ($Data.policyVersion -is [string]) 'Authentication policy version must be a string.'
    if ($Data.registration) {
        Assert-AnajakContract ($Data.emailDelivery -and $Data.policyVersion.Trim().Length -gt 0) 'Enabled registration requires email delivery and a policy version.'
        Assert-AnajakContract ((Test-AnajakContractHttps $Data.termsUrl) -and (Test-AnajakContractHttps $Data.privacyUrl)) 'Enabled registration requires public HTTPS Terms and Privacy links.'
    }
}
function Assert-AnajakGuideCapabilitiesContract($Data) {
    Assert-AnajakContract ($Data.provider -is [string] -and $Data.provider.Trim().Length -gt 0) 'AI capabilities are missing the provider name; configuration is not a successful AI request.'
    foreach ($name in @('configured','demo','providerVerified','chat','translation','itinerary','recommendations','recap','vision','voice','receipt','reservation')) {
        Assert-AnajakContract ((Get-AnajakContractField $Data $name) -is [bool]) "AI capabilities are missing boolean $name."
    }
}
function Assert-AnajakRoadRouteContract($Data) {
    Assert-AnajakContract (Test-AnajakContractObject $Data) 'Road route data must be an object.'
    foreach ($name in @('distanceMeters','durationSeconds')) {
        $number = Get-AnajakContractField $Data $name
        Assert-AnajakContract ((Test-AnajakContractNumber $number) -and $number -ge 0) "Road route is missing numeric $name; legacy cost/time demo responses are not road directions."
    }
    $points = Get-AnajakContractField $Data 'coordinates'
    Assert-AnajakContract ((Test-AnajakContractList $points) -and $points.Count -ge 2 -and $points.Count -le 50000) 'Road route requires 2 to 50,000 GeoJSON coordinate pairs; no straight-line substitute is accepted.'
    foreach ($point in $points) {
        Assert-AnajakContract ((Test-AnajakContractList $point) -and $point.Count -ge 2) 'Road route contains an invalid coordinate pair.'
        Assert-AnajakContract ((Test-AnajakContractNumber $point[0]) -and (Test-AnajakContractNumber $point[1]) -and
            [Math]::Abs([double]$point[0]) -le 180 -and [Math]::Abs([double]$point[1]) -le 90) 'Road route coordinates must be finite numeric longitude/latitude pairs.'
    }
    Assert-AnajakContract ($Data.source -is [string] -and $Data.source.Trim().Length -gt 0) 'Road route source is missing.'
}
function Assert-AnajakPlaceListContract($Data) {
    Assert-AnajakContract (Test-AnajakContractList $Data) 'Place search must return a data array.'
    foreach ($place in $Data) {
        Assert-AnajakContract ($place.id -is [string] -and $place.id.Length -gt 0 -and $place.name -is [string] -and $place.name.Length -gt 0) 'A place is missing its id or name.'
        Assert-AnajakContract ((Test-AnajakContractNumber $place.latitude) -and (Test-AnajakContractNumber $place.longitude) -and
            [Math]::Abs([double]$place.latitude) -le 90 -and [Math]::Abs([double]$place.longitude) -le 180) 'A place has invalid coordinates.'
    }
}
function Assert-AnajakPlacePhotosContract($Data) {
    Assert-AnajakContract (Test-AnajakContractObject $Data) 'Optional place photos must return an object keyed by place id.'
    $photos = if ($Data -is [Collections.IDictionary]) { @($Data.Values) } else { @($Data.PSObject.Properties | ForEach-Object { $_.Value }) }
    foreach ($photo in $photos) {
        Assert-AnajakContract ((Test-AnajakContractHttps $photo.url @('upload.wikimedia.org','thumb.wikimedia.org')) -and
            (Test-AnajakContractHttps $photo.sourceUrl @('commons.wikimedia.org')) -and
            (Test-AnajakContractHttps $photo.licenseUrl @('creativecommons.org','commons.wikimedia.org'))) 'A place photo has missing or unsupported image/source/license URLs.'
        Assert-AnajakContract ($photo.artist -is [string] -and $photo.artist.Trim().Length -gt 0 -and
            $photo.license -is [string] -and $photo.license -match '^(?i:CC BY(?:-SA)? [1-4]\.0|CC0(?: 1\.0)?|Public domain)$') 'A place photo lacks supported license/artist metadata.'
    }
}
function Assert-AnajakRpgCapabilitiesContract($Data) {
    foreach ($name in @('practiceEnabled','fieldRequiresReviewedDestination','redemptionEnabled')) {
        Assert-AnajakContract ((Get-AnajakContractField $Data $name) -is [bool]) "RPG capabilities are missing boolean $name."
    }
    Assert-AnajakContract ($Data.partySize -eq 3) 'RPG party size differs from the current three-companion client.'
}
function Assert-AnajakRpgSnapshotContract($Data, [string]$Realm) {
    Assert-AnajakContract ($Data.realm -eq $Realm -and (Test-AnajakContractObject $Data.profile)) 'RPG snapshot realm/profile does not match the selected account realm.'
    foreach ($name in @('monsters','species','quests','ledger','party','inventory','achievements','exploration','history')) {
        Assert-AnajakContract (Test-AnajakContractList (Get-AnajakContractField $Data $name)) "RPG snapshot is missing array $name."
    }
    if ($null -ne $Data.activeSession) {
        Assert-AnajakContract ((Test-AnajakContractObject $Data.activeSession) -and $Data.activeSession.id -is [string] -and
            $Data.activeSession.status -is [string] -and (Test-AnajakContractNumber $Data.activeSession.revision)) 'RPG active session has an invalid id/status/revision shape.'
    }
}
function Invoke-AnajakContractGet([string]$Url, [hashtable]$Headers = @{}) {
    try {
        $response = Invoke-WebRequest -Uri $Url -Headers $Headers -Method Get -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 0
    } catch {
        if ($_.Exception.Response) { return @{Status=[int]$_.Exception.Response.StatusCode;Document=$null} }
        throw 'The contract probe could not connect. No raw request, credentials or response body were logged.'
    }
    try { $document = $response.Content | ConvertFrom-Json }
    catch { throw 'The contract probe received non-JSON data. Response body was not logged.' }
    return @{Status=[int]$response.StatusCode;Document=$document}
}
function Invoke-AnajakFrontendContractSmoke {
    [CmdletBinding()]
    param([string]$BaseUrl, [switch]$Authenticated, [Security.SecureString]$AccessToken,
        [switch]$CheckRoute, [switch]$CheckPlaces, [switch]$CheckRpgProfile)
    $uri = $null
    Assert-AnajakContract ([Uri]::TryCreate($BaseUrl,[UriKind]::Absolute,[ref]$uri)) 'Use an absolute backend API base URL.'
    Assert-AnajakContract (!$uri.UserInfo -and !$uri.Query -and !$uri.Fragment -and $uri.AbsolutePath.TrimEnd('/') -eq '/api/v1' -and
        ($uri.Scheme -eq 'https' -or ($uri.Scheme -eq 'http' -and $uri.Host -in @('127.0.0.1','localhost','[::1]')))) 'Use HTTPS /api/v1/ or a loopback-only HTTP API base URL, without credentials/query/fragment.'
    Assert-AnajakContract ($Authenticated -or !($CheckRoute -or $CheckPlaces -or $CheckRpgProfile -or $AccessToken)) 'Optional protected checks require -Authenticated and a dedicated test-account access token.'
    $base = $BaseUrl.TrimEnd('/') + '/'
    $results = New-Object 'Collections.Generic.List[object]'
    $config = Invoke-AnajakContractGet ($base + 'auth/config')
    Assert-AnajakContract ($config.Status -eq 200) 'Public auth/config did not return HTTP 200.'
    Assert-AnajakAuthConfigContract (Assert-AnajakFrontendEnvelope $config.Document)
    $results.Add(@{check='auth-config';passed=$true;status=200})
    foreach ($path in @('profile','guide/capabilities','rpg/capabilities')) {
        $response = Invoke-AnajakContractGet ($base + $path)
        Assert-AnajakContract ($response.Status -eq 401) "Protected $path did not return unauthenticated HTTP 401."
        $results.Add(@{check=('unauthenticated-' + $path);passed=$true;status=401})
    }
    if (!$Authenticated) { return $results.ToArray() }
    if (!$AccessToken) { $AccessToken = Read-Host 'Dedicated test account access token (hidden; never paste into chat)' -AsSecureString }
    $pointer = [IntPtr]::Zero
    $headers = @{}
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccessToken)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        Assert-AnajakContract ($plain.Length -gt 0 -and $plain -notmatch '[\r\n\s]') 'The supplied access token is empty or contains whitespace.'
        $headers.Authorization = 'Bearer ' + $plain
        foreach ($path in @('profile','guide/capabilities','rpg/capabilities')) {
            $response = Invoke-AnajakContractGet ($base + $path) $headers
            Assert-AnajakContract ($response.Status -eq 200) "Authenticated $path did not return HTTP 200; a valid unexpired access token is required."
            $data = Assert-AnajakFrontendEnvelope $response.Document
            switch ($path) {
                'profile' { Assert-AnajakContract ($data.id -is [string] -and $data.email -is [string] -and $data.name -is [string]) 'Current-user profile is missing id/email/name.' }
                'guide/capabilities' { Assert-AnajakGuideCapabilitiesContract $data }
                'rpg/capabilities' { Assert-AnajakRpgCapabilitiesContract $data }
            }
            $results.Add(@{check=$path;passed=$true;status=200})
        }
        if ($CheckRoute) {
            # Fictional public landmark pair, never device GPS or stored trip data.
            $response = Invoke-AnajakContractGet ($base + 'discovery/routes?originLat=11.5638&originLon=104.9315&destinationLat=11.5760&destinationLon=104.9231&mode=driving') $headers
            Assert-AnajakContract ($response.Status -eq 200) 'Synthetic landmark route did not return HTTP 200; its router needs a separate availability check.'
            Assert-AnajakRoadRouteContract (Assert-AnajakFrontendEnvelope $response.Document)
            $results.Add(@{check='road-route-geometry';passed=$true;status=200})
        }
        if ($CheckPlaces) {
            foreach ($path in @('discovery/places?query=Phnom%20Penh&page=0&size=20','discovery/photos?query=Phnom%20Penh&page=0')) {
                $response = Invoke-AnajakContractGet ($base + $path) $headers
                Assert-AnajakContract ($response.Status -eq 200) 'A synthetic place/photo search did not return HTTP 200.'
                $data = Assert-AnajakFrontendEnvelope $response.Document
                if ($path.StartsWith('discovery/places')) { Assert-AnajakPlaceListContract $data }
                else { Assert-AnajakPlacePhotosContract $data }
            }
            $results.Add(@{check='places-and-optional-licensed-photos';passed=$true;status=200})
        }
        if ($CheckRpgProfile) {
            Write-Warning 'This explicit RPG check may initialize a starter for this test account and expire overdue sessions. It does not start battles, claim rewards or spend inventory.'
            $response = Invoke-AnajakContractGet ($base + 'rpg/field/profile') $headers
            Assert-AnajakContract ($response.Status -eq 200) 'Field RPG profile did not return HTTP 200.'
            Assert-AnajakRpgSnapshotContract (Assert-AnajakFrontendEnvelope $response.Document) 'field'
            $results.Add(@{check='field-rpg-snapshot';passed=$true;status=200})
        }
        return $results.ToArray()
    } finally {
        $headers.Clear()
        $plain = $null
        $AccessToken = $null
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $checks = @(Invoke-AnajakFrontendContractSmoke -BaseUrl $BaseUrl -Authenticated:$Authenticated -AccessToken $AccessToken -CheckRoute:$CheckRoute -CheckPlaces:$CheckPlaces -CheckRpgProfile:$CheckRpgProfile)
        @{checks=$checks;liveAiCalled=$false;emailSent=$false;passwordsAccepted=$false} | ConvertTo-Json -Depth 5
        Write-Host 'Contract shapes passed for the selected checks. This does not prove live Gemini, inbox delivery, route navigation, battle acceptance or production readiness.'
        exit 0
    } catch {
        Write-Error ('Frontend contract check failed: ' + $_.Exception.Message)
        exit 1
    }
}
