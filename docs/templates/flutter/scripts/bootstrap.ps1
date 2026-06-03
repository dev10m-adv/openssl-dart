$ErrorActionPreference = "Stop"
$AppRoot = Split-Path -Parent $PSScriptRoot
Set-Location $AppRoot

$env:GIT_LFS_SKIP_SMUDGE = "1"
$Toolchain = Join-Path $AppRoot "windows/cmake/community_vs.cmake"
if (Test-Path $Toolchain) {
  $env:CMAKE_TOOLCHAIN_FILE = $Toolchain
}

Write-Host "==> flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "==> dart run openssl:setup_prebuilts"
dart run openssl:setup_prebuilts
exit $LASTEXITCODE
