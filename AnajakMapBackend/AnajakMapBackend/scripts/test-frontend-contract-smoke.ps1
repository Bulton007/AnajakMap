$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'frontend-contract-smoke.ps1')
$script:passed = 0
function Assert-ContractTest([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "Contract regression failed: $Name" }
    $script:passed++
}
function Assert-ContractThrows([scriptblock]$Action, [string]$Name) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert-ContractTest $failed $Name
}
function Envelope($Data) { return @{data=$Data;traceId='synthetic-trace';timestamp='2026-10-29T12:00:00Z'} }
$auth = @{emailDelivery=$true;registration=$true;google=$false;apple=$false;passwordMinLength=12;passwordMaxBytes=72;policyVersion='synthetic-policy';termsUrl='https://legal.example/terms';privacyUrl='https://legal.example/privacy'}
Assert-AnajakAuthConfigContract $auth
Assert-ContractTest $true 'current auth limits/legal configuration accepted'
$disabled = $auth.Clone();$disabled.registration=$false;$disabled.emailDelivery=$false;$disabled.policyVersion='';$disabled.termsUrl='';$disabled.privacyUrl=''
Assert-AnajakAuthConfigContract $disabled
Assert-ContractTest $true 'disabled registration can legitimately have no legal setup'
$copy = $auth.Clone();$copy.passwordMinLength=8
Assert-ContractThrows { Assert-AnajakAuthConfigContract $copy } 'mismatched mobile password limits rejected'
$copy = $auth.Clone();$copy.termsUrl='http://legal.example/terms'
Assert-ContractThrows { Assert-AnajakAuthConfigContract $copy } 'enabled registration without HTTPS legal pages rejected'
$copy = $auth.Clone();$copy.emailDelivery=$false
Assert-ContractThrows { Assert-AnajakAuthConfigContract $copy } 'enabled registration cannot lack delivery'
Assert-ContractThrows { Assert-AnajakFrontendEnvelope @{data=@{}} } 'malformed envelope rejected'
$enveloped = Assert-AnajakFrontendEnvelope (Envelope @())
Assert-ContractTest ((Test-AnajakContractList $enveloped) -and $enveloped.Count -eq 0) 'empty data array survives envelope unwrapping'
$caps = @{provider='gemini'}
foreach($name in @('configured','demo','providerVerified','chat','translation','itinerary','recommendations','recap','vision','voice','receipt','reservation')){$caps[$name]=$false}
Assert-AnajakGuideCapabilitiesContract $caps
Assert-ContractTest $true 'explicit provider capabilities accepted without Google calls'
$copy = $caps.Clone();$copy.Remove('configured')
Assert-ContractThrows { Assert-AnajakGuideCapabilitiesContract $copy } 'empty/missing capability cannot imply successful configuration'
$route = '{"distanceMeters":1729.9,"durationSeconds":300.1,"coordinates":[[104.9315,11.5638],[104.9231,11.5760]],"source":"OSRM synthetic"}' | ConvertFrom-Json
Assert-AnajakRoadRouteContract $route
Assert-ContractTest $true 'real road-contract fixture accepted'
Assert-ContractThrows { Assert-AnajakRoadRouteContract @{durationMinutes=25;estimatedCost='8.00';currency='USD';mock=$true;source='development fixture'} } 'observed legacy demo cost/time payload rejected'
Assert-ContractThrows { Assert-AnajakRoadRouteContract @{distanceMeters='12';durationSeconds=20;coordinates=@(@(104,11),@(104,12));source='test'} } 'string route estimate rejected'
Assert-ContractThrows { Assert-AnajakRoadRouteContract @{distanceMeters=12;durationSeconds=20;coordinates=@(@(104,11));source='test'} } 'one-point route rejected'
Assert-ContractThrows { Assert-AnajakRoadRouteContract @{distanceMeters=12;durationSeconds=20;coordinates=@(@(104,91),@(104,12));source='test'} } 'invalid latitude rejected'
Assert-ContractThrows { Assert-AnajakRoadRouteContract @{distanceMeters=[double]::NaN;durationSeconds=20;coordinates=@(@(104,11),@(104,12));source='test'} } 'nonfinite estimate rejected'
Assert-AnajakPlaceListContract @(@{id='fictional';name='Fictional place';latitude=11.5;longitude=104.9})
Assert-ContractTest $true 'place list fixture accepted'
Assert-AnajakPlacePhotosContract @{}
Assert-ContractTest $true 'optional empty photo map accepted'
$photo = @{url='https://upload.wikimedia.org/example.jpg';sourceUrl='https://commons.wikimedia.org/wiki/File:Example.jpg';licenseUrl='https://creativecommons.org/licenses/by-sa/4.0/';artist='Synthetic artist';license='CC BY-SA 4.0';credit='Synthetic credit'}
Assert-AnajakPlacePhotosContract @{fictional=$photo}
Assert-ContractTest $true 'licensed photo metadata accepted without downloading'
$copy = $photo.Clone();$copy.url='https://unapproved.example/image.jpg'
Assert-ContractThrows { Assert-AnajakPlacePhotosContract @{fictional=$copy} } 'unsupported image host rejected'
$snapshot = @{realm='field';profile=@{};activeSession=$null}
foreach($name in @('monsters','species','quests','ledger','party','inventory','achievements','exploration','history')){$snapshot[$name]=@()}
Assert-AnajakRpgSnapshotContract $snapshot 'field'
Assert-ContractTest $true 'full empty RPG snapshot shape accepted'
Assert-ContractThrows { Assert-AnajakRpgSnapshotContract $snapshot 'practice' } 'cross-realm snapshot rejected'

# Replace all transport before exercising orchestration. This suite cannot send a
# network request, email, password, provider request or real token anywhere.
$script:requests = New-Object 'Collections.Generic.List[object]'
$script:syntheticToken = 'synthetic-token-never-transmitted'
function Invoke-AnajakContractGet([string]$Url,[hashtable]$Headers=@{}) {
    $uri=[Uri]$Url
    Assert-ContractTest ($uri.Host -eq 'test.invalid') 'transport is restricted to synthetic hostname'
    $script:requests.Add(@{path=$uri.AbsolutePath;query=$uri.Query;authorized=$Headers.ContainsKey('Authorization')})
    $path=$uri.AbsolutePath.Replace('/api/v1/','')
    if($path -eq 'auth/config'){return @{Status=200;Document=(Envelope $auth)}}
    if(!$Headers.ContainsKey('Authorization')){return @{Status=401;Document=$null}}
    Assert-ContractTest ($Headers.Authorization -ceq ('Bearer '+$script:syntheticToken)) 'in-memory supplied token used only by fake transport'
    switch($path){
        'profile' {return @{Status=200;Document=(Envelope @{id='synthetic';email='synthetic@example.invalid';name='Synthetic'})}}
        'guide/capabilities' {return @{Status=200;Document=(Envelope $caps)}}
        'rpg/capabilities' {return @{Status=200;Document=(Envelope @{practiceEnabled=$false;fieldRequiresReviewedDestination=$true;redemptionEnabled=$false;partySize=3})}}
        'discovery/routes' {return @{Status=200;Document=(Envelope $route)}}
        'discovery/places' {return @{Status=200;Document=(Envelope @())}}
        'discovery/photos' {return @{Status=200;Document=(Envelope @{})}}
        'rpg/field/profile' {return @{Status=200;Document=(Envelope $snapshot)}}
        default {throw 'Unexpected synthetic request path.'}
    }
}
$anonymous = @(Invoke-AnajakFrontendContractSmoke -BaseUrl 'https://test.invalid/api/v1/')
Assert-ContractTest ($anonymous.Count -eq 4) 'default smoke only checks public config and three auth boundaries'
Assert-ContractTest (@($script:requests | Where-Object {$_.authorized}).Count -eq 0) 'default smoke sends no authorization header'
Assert-ContractTest (@($script:requests | Where-Object {$_.path -like '*discovery*' -or $_.path -like '*rpg/field*'}).Count -eq 0) 'provider and profile-initialization checks are opt-in'
$secret=ConvertTo-SecureString $script:syntheticToken -AsPlainText -Force
$authenticatedResults=@(Invoke-AnajakFrontendContractSmoke -BaseUrl 'https://test.invalid/api/v1/' -Authenticated -AccessToken $secret -CheckRoute -CheckPlaces -CheckRpgProfile -WarningAction SilentlyContinue)
Assert-ContractTest ($authenticatedResults.Count -eq 10) 'explicit optional checks cover route photos and RPG shape'
Assert-ContractTest (($authenticatedResults|ConvertTo-Json -Depth 5) -notmatch $script:syntheticToken) 'result contains no token'
Assert-ContractTest (@($script:requests | Where-Object {$_.path -like '*translation*' -or $_.path -like '*conversations*' -or $_.path -like '*media*' -or $_.path -like '*auth/login*'}).Count -eq 0) 'no AI media login or email operation is ever requested'
Assert-ContractThrows { Invoke-AnajakFrontendContractSmoke -BaseUrl 'http://test.invalid/api/v1/' } 'nonloopback cleartext rejected'
Assert-ContractThrows { Invoke-AnajakFrontendContractSmoke -BaseUrl 'https://user:password@test.invalid/api/v1/' } 'credentials in URL rejected'
Assert-ContractThrows { Invoke-AnajakFrontendContractSmoke -BaseUrl 'https://test.invalid/api/v1/' -CheckRoute } 'route check cannot silently run without authenticated opt-in'
Write-Host "PASS: $script:passed frontend contract checks. Synthetic responses only; no network, Docker, email or Google requests."
