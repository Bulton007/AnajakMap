$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ai-settings.ps1')
$passed=0
function Assert-AiSetting([bool]$Condition,[string]$Name) {
    if (!$Condition) { throw "AI setting regression failed: $Name" }
    $script:passed++
}
$longDotted='synthetic.header.' + ('a' * 256) + '.signature'
Assert-AiSetting (Test-AnajakAiKey $longDotted) 'opaque dotted credential longer than 200 accepted'
Assert-AiSetting (Test-AnajakAiKey ('x'*16)) 'minimum visible length accepted'
Assert-AiSetting (Test-AnajakAiKey ('x'*4096)) 'maximum visible length accepted'
foreach($bad in @('',('x'*15),('x'*4097),'key with spaces abcdef',"abcdefghijklmnop`t", "abcdefghijklmnop`n", "abcdefghijklmnop`r", ("abcdefghijklmnop"+[char]0),('ខ'*20))) {
    Assert-AiSetting (!(Test-AnajakAiKey $bad)) 'length whitespace control or non-ASCII input rejected'
}
$visible=-join (0x21..0x7e | ForEach-Object {[char]$_})
foreach($value in @($longDotted,$visible,'synthetic$1${NAME}$$#=value','synthetic"double''single\tail\','synthetic\n\r\t\$literal')) {
    $literal=ConvertTo-AnajakAiDotEnvLiteral $value
    Assert-AiSetting ((ConvertFrom-AnajakAiDotEnvValue $literal) -ceq $value) 'opaque punctuation survives dotenv encoding/decoding'
    $original="GMAIL_APP_PASSWORD=synthetic-unchanged`r`nGEMINI_API_KEY=old-synthetic-value`r`n"
    $written=Set-AnajakAiDotEnvValue $original 'GEMINI_API_KEY' $value
    $line=@($written -split "`r?`n" | Where-Object {$_ -like 'GEMINI_API_KEY=*'})[0]
    Assert-AiSetting ((ConvertFrom-AnajakAiDotEnvValue $line.Substring('GEMINI_API_KEY='.Length)) -ceq $value) 'regex replacement is literal for dollar and backslash values'
    Assert-AiSetting ($written.Contains("GMAIL_APP_PASSWORD=synthetic-unchanged`r`n")) 'unrelated credential line unchanged'
}
Write-Host "$passed AI setting checks passed with synthetic credentials only. Google was not contacted."
