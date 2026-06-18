param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('android-arm64-v8a', 'android-x86_64')]
  [string]$Triple,

  [string]$OutDir = '',
  [string]$PrebuiltDir = '',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$VerboseBuild = ($env:OPENSSL_BOOTSTRAP_VERBOSE -eq '1')
$QuietMode = $Quiet -or (-not $VerboseBuild)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'bootstrap_tools.ps1')
$NativeDir = Resolve-Path (Join-Path $ScriptDir '..')
$RepoRoot = Resolve-Path (Join-Path $NativeDir '..')

$Version = (Get-Content (Join-Path $NativeDir 'src\VERSION') -Raw).Trim()
$OutDir = if ($OutDir) { $OutDir } else { Join-Path $RepoRoot "native\out\$Version\$Triple" }
$PrebuiltDir = if ($PrebuiltDir) { $PrebuiltDir } else { Join-Path $RepoRoot "native\prebuilt\$Version\$Triple" }

function Get-AndroidNdkRoot {
  foreach ($key in @('ANDROID_NDK_ROOT', 'ANDROID_NDK_HOME')) {
    $value = [Environment]::GetEnvironmentVariable($key)
    if ($value -and (Test-Path -LiteralPath $value)) { return $value }
  }
  $sdkNdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk\ndk'
  if (Test-Path -LiteralPath $sdkNdk) {
    $latest = Get-ChildItem -Path $sdkNdk -Directory |
      Where-Object { Test-Path (Join-Path $_.FullName 'toolchains/llvm/prebuilt') } |
      Sort-Object Name -Descending |
      Select-Object -First 1
    if ($latest) { return $latest.FullName }
  }
  throw 'Android NDK not found. Install via Android Studio SDK Manager or set ANDROID_NDK_ROOT.'
}

function Get-NdkToolchainBin([string]$NdkRoot) {
  foreach ($hostTag in @('windows-x86_64', 'windows-arm64')) {
    $bin = Join-Path $NdkRoot "toolchains/llvm/prebuilt/$hostTag/bin"
    if (Test-Path -LiteralPath $bin) { return $bin }
  }
  throw "NDK toolchain bin not found under $NdkRoot"
}

function Resolve-BashExe {
  foreach ($candidate in @(
      'C:\Program Files\Git\bin\bash.exe',
      'C:\Program Files\Git\usr\bin\bash.exe'
    )) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'Git Bash required for Android OpenSSL builds on Windows (install Git for Windows).'
}

function Resolve-GitMakeDir {
  foreach ($candidate in @(
      'C:\Program Files\Git\usr\bin',
      'C:\Program Files\Git\bin'
    )) {
    if (Test-Path -LiteralPath (Join-Path $candidate 'make.exe')) { return $candidate }
  }
  return ''
}

$config = switch ($Triple) {
  'android-arm64-v8a' { 'android-arm64' }
  'android-x86_64' { 'android-x86_64' }
}

$ndkRoot = Get-AndroidNdkRoot
$toolchainBin = Get-NdkToolchainBin $ndkRoot
$bash = Resolve-BashExe
$toolsDir = Join-Path $RepoRoot 'native\out\_bootstrap-tools'
$makeExe = Ensure-GnuMakeOnPath -ToolsDir $toolsDir
Ensure-RmShim -ToolsDir $toolsDir | Out-Null
$makeDir = Split-Path -Parent $makeExe

$apiLevel = 21
if ($env:ANDROID_API) { $apiLevel = [int]$env:ANDROID_API }
$perlExe = Resolve-PerlExe -ToolsDir $toolsDir
$perlBin = Split-Path -Parent $perlExe
Write-Host "Using perl: $perlExe"

$env:ANDROID_NDK_ROOT = $ndkRoot
$env:ANDROID_NDK_HOME = $ndkRoot
$env:ANDROID_API = "$apiLevel"
Remove-Item Env:CC, Env:CXX, Env:AR, Env:RANLIB -ErrorAction SilentlyContinue

$gitUsrBin = 'C:\Program Files\Git\usr\bin'
if (Test-Path -LiteralPath $gitUsrBin) {
  $env:PATH = "$gitUsrBin;$env:PATH"
}

$pathParts = @($toolchainBin, $perlBin)
if ($makeDir) { $pathParts += $makeDir }
$pathParts += $env:PATH -split ';' | Where-Object { $_ -and ($_ -notmatch '\\Git\\usr\\bin|\\Git\\bin') }
$env:PATH = ($pathParts -join ';')

Write-Host "Using NDK: $ndkRoot"
Write-Host "Using bash: $bash"

$src = Ensure-OpenSslSrc -RepoRoot $RepoRoot -Version $Version -Triple $Triple
Patch-OpenSslAndroidConfForWindows -SrcRoot $src
Patch-OpenSslConfigureWhichForWindows -SrcRoot $src
Patch-OpenSslUnixCheckerForWindows -SrcRoot $src
$logDir = Join-Path $RepoRoot 'native\out'
$logFile = New-BuildLogPath -LogDir $logDir -Triple $Triple

$configureArgs = @(
  'Configure',
  $config,
  'no-unit-test',
  'no-makedepend',
  'no-ssl',
  'no-apps',
  'no-asm',
  '--openssldir=/usr/local/ssl'
)

$jobs = if ($env:NUMBER_OF_PROCESSORS) { $env:NUMBER_OF_PROCESSORS } else { '4' }
$srcUnix = Convert-ToUnixPath $src
$makePathParts = @($toolchainBin)
if ($makeDir) { $makePathParts += $makeDir }
$makePathUnix = (($makePathParts | ForEach-Object { Convert-ToUnixPath $_ }) -join ':')
$makeExeUnix = Convert-ToUnixPath $makeExe
$perlUnix = Convert-ToUnixPath $perlExe
$makeCmd = "export PATH='$makePathUnix':`$PATH && cd '$srcUnix' && '$makeExeUnix' -j $jobs PERL='$perlUnix'"

if ($QuietMode) {
  Write-Host "Compiling OpenSSL for $Triple (quiet; full log: $logFile)"
  Initialize-BuildLog -Path $logFile
} else {
  Write-Host "Configuring OpenSSL for $Triple ..."
}

Push-Location $src
try {
  if ($QuietMode) {
    $cfgExit = Invoke-Executable -FilePath $perlExe -ArgumentList $configureArgs -LogFile $logFile -Quiet
  } else {
    & $perlExe @configureArgs
    $cfgExit = $LASTEXITCODE
  }
  if ($cfgExit -ne 0) {
    Show-BuildLogTail -Path $logFile
    throw "OpenSSL Configure failed (exit $cfgExit)"
  }

  if ($QuietMode) {
    Write-Host 'Generating mandatory headers (build_generated) ...'
    $genExit = Invoke-Executable -FilePath $makeExe -ArgumentList @('-j', $jobs, "PERL=$perlExe", 'build_generated') -LogFile $logFile -Quiet
  } else {
    & $makeExe -j $jobs "PERL=$perlExe" build_generated
    $genExit = $LASTEXITCODE
  }
  if ($genExit -ne 0) {
    Show-BuildLogTail -Path $logFile
    throw "make build_generated failed (exit $genExit)"
  }

  if ($QuietMode) {
    Write-Host 'Compiling libcrypto with make ...'
    $makeExit = Invoke-Executable -FilePath $makeExe -ArgumentList @('-j', $jobs, "PERL=$perlExe", 'libcrypto.so') -LogFile $logFile -Quiet
  } else {
    & $makeExe -j $jobs "PERL=$perlExe" libcrypto.so
    $makeExit = $LASTEXITCODE
  }
  if ($makeExit -ne 0) {
    Write-Host 'make link failed; retrying libcrypto.so with response file...'
    $makeExit = Complete-LibcryptoSharedLink `
      -SrcRoot $src `
      -ToolchainBin $toolchainBin `
      -ArchPrefix $(if ($Triple -eq 'android-arm64-v8a') { 'aarch64' } else { 'x86_64' }) `
      -ApiLevel $apiLevel `
      -MakeExe $makeExe `
      -LogFile $(if ($QuietMode) { $logFile } else { '' })
  }
  if ($makeExit -ne 0) {
    Show-BuildLogTail -Path $logFile
    throw "make build failed (exit $makeExit)"
  }
  if ($QuietMode) {
    Write-Host "Build finished. Log: $logFile"
  }
} finally {
  Pop-Location
}

$so = Get-ChildItem -Path $src -Filter 'libcrypto.so*' -File | Select-Object -First 1
if (-not $so) { throw 'libcrypto.so not found after build' }

New-Item -ItemType Directory -Force -Path $OutDir, $PrebuiltDir | Out-Null
Copy-Item $so.FullName (Join-Path $OutDir $so.Name) -Force
Copy-Item $so.FullName (Join-Path $PrebuiltDir $so.Name) -Force
Get-ChildItem $PrebuiltDir
