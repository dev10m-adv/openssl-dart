param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Target,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot/bootstrap.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build $Target @FlutterArgs
exit $LASTEXITCODE
