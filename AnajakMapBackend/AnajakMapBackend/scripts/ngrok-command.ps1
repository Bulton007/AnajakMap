function Get-AnajakNgrokCommand {
    $command = Get-Command ngrok -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    $aliasPath = Join-Path $localData 'Microsoft\WinGet\Links\ngrok.exe'
    if (Test-Path -LiteralPath $aliasPath -PathType Leaf) { return $aliasPath }
    throw 'ngrok is not installed or not on PATH. Install it from https://ngrok.com/download/windows, then reopen this launcher.'
}
