param([ValidateSet('web','android')][string]$Target='web')
$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
if($Target -eq 'web') { flutter run -d chrome --web-hostname localhost --web-port 7777 --dart-define-from-file=config/connected.web.json }
else { flutter run --dart-define-from-file=config/connected.android.json }
exit $LASTEXITCODE
