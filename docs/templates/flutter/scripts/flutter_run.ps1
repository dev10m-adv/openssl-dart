param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot/bootstrap.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter run @FlutterArgs
exit $LASTEXITCODE
