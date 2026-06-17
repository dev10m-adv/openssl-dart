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

$ndkRoot = Get-AndroidNdkRoot
$toolchainBin = Get-NdkToolchainBin $ndkRoot
$bash = Resolve-BashExe

$env:ANDROID_NDK_ROOT = $ndkRoot
$env:ANDROID_NDK_HOME = $ndkRoot
$env:TRIPLE = $Triple
$env:OUT_DIR = $OutDir
$env:PREBUILT_DIR = $PrebuiltDir
$env:OPENSSL_NDK_HOST_TAG = 'windows-x86_64'

# Reuse portable Perl from windows bootstrap when available.
$toolsPerl = Join-Path $RepoRoot 'native\out\_bootstrap-tools\perl\perl\bin'
if (Test-Path -LiteralPath $toolsPerl) {
  $env:PATH = "$toolsPerl;$toolchainBin;$env:PATH"
} else {
  $env:PATH = "$toolchainBin;$env:PATH"
}

Write-Host "Using NDK: $ndkRoot"
Write-Host "Using bash: $bash"

$androidSh = Join-Path $ScriptDir 'android.sh'
$repoRootUnix = ($RepoRoot -replace '\\', '/')
$androidShUnix = ($androidSh -replace '\\', '/')
$logFile = Join-Path $RepoRoot "native/out/build-$Triple.log"
New-Item -ItemType Directory -Force -Path (Split-Path $logFile -Parent) | Out-Null

if ($QuietMode) {
  Write-Host "Compiling OpenSSL for $Triple (quiet; full log: $logFile)"
  & $bash -lc "cd '$repoRootUnix' && bash '$androidShUnix'" *>> $logFile 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host "--- last 40 lines of $logFile ---"
    if (Test-Path $logFile) { Get-Content $logFile -Tail 40 | Write-Host }
    exit $LASTEXITCODE
  }
  Write-Host "Build finished. Log: $logFile"
} else {
  & $bash -lc "cd '$repoRootUnix' && bash '$androidShUnix'"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Get-ChildItem $PrebuiltDir
