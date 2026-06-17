param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('windows-x64', 'windows-arm64')]
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
$OpenSslSrc = Join-Path $RepoRoot 'native\third_party\openssl'
$OutDir = if ($OutDir) { $OutDir } else { Join-Path $RepoRoot "native\out\$Version\$Triple" }
$PrebuiltDir = if ($PrebuiltDir) { $PrebuiltDir } else { Join-Path $RepoRoot "native\prebuilt\$Version\$Triple" }

$Config = switch ($Triple) {
  'windows-x64' { 'VC-WIN64A' }
  'windows-arm64' { 'VC-WIN64-ARM' }
}

function Ensure-OpenSslSrc {
  if (Test-Path (Join-Path $OpenSslSrc 'Configure')) { return $OpenSslSrc }
  $work = Join-Path $RepoRoot 'native\out\_src'
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  $tarball = "openssl-$Version.tar.gz"
  $url = "https://github.com/openssl/openssl/releases/download/openssl-$Version/$tarball"
  $tarPath = Join-Path $work $tarball
  if (-not (Test-Path $tarPath)) {
    curl.exe -L $url -o $tarPath
  }
  $extracted = Join-Path $work "openssl-$Version"
  if (-not (Test-Path $extracted)) {
    tar -xzf $tarPath -C $work
  }
  return $extracted
}

function Resolve-PerlExe {
  param([string]$ToolsDir)

  if ($env:PERL -and (Test-Path -LiteralPath $env:PERL)) {
    return $env:PERL
  }
  foreach ($candidate in @(
      'C:\Strawberry\perl\bin\perl.exe',
      'C:\strawberry\perl\bin\perl.exe'
    )) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  $cmd = Get-Command perl -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notmatch '\\Git\\') {
    return $cmd.Source
  }

  New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
  $perlDest = Join-Path $ToolsDir 'perl'
  $perlExe = Join-Path $perlDest 'perl\bin\perl.exe'
  if (-not (Test-Path -LiteralPath $perlExe)) {
    $perlZip = Join-Path $ToolsDir 'perl.zip'
    $perlUrl = 'https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54021_64bit_UCRT/strawberry-perl-5.40.2.1-64bit-portable.zip'
    if (-not (Test-Path -LiteralPath $perlZip)) {
      Write-Host "Downloading portable Strawberry Perl..."
      curl.exe -L $perlUrl -o $perlZip
    }
    if (Test-Path -LiteralPath $perlDest) {
      Remove-Item -Recurse -Force $perlDest
    }
    New-Item -ItemType Directory -Force -Path $perlDest | Out-Null
    Expand-Archive -Path $perlZip -DestinationPath $perlDest -Force
  }
  if (-not (Test-Path -LiteralPath $perlExe)) {
    throw "perl not found at $perlExe after download (check $perlDest layout)"
  }
  return $perlExe
}

function Ensure-JomOnPath {
  param([string]$ToolsDir)

  if (Get-Command jom -ErrorAction SilentlyContinue) { return }
  New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
  $jomDest = Join-Path $ToolsDir 'jom'
  $jomExe = Join-Path $jomDest 'jom.exe'
  if (-not (Test-Path -LiteralPath $jomExe)) {
    $jomZip = Join-Path $ToolsDir 'jom.zip'
    $jomUrl = 'https://download.qt.io/official_releases/jom/jom_1_1_5.zip'
    if (-not (Test-Path -LiteralPath $jomZip)) {
      Write-Host "Downloading jom..."
      curl.exe -L $jomUrl -o $jomZip
    }
    if (Test-Path -LiteralPath $jomDest) {
      Remove-Item -Recurse -Force $jomDest
    }
    New-Item -ItemType Directory -Force -Path $jomDest | Out-Null
    Expand-Archive -Path $jomZip -DestinationPath $jomDest -Force
  }
  if (-not (Test-Path -LiteralPath $jomExe)) {
    throw "jom not found at $jomExe after download"
  }
  $env:PATH = "$(Split-Path -Parent $jomExe);$env:PATH"
}

function Get-VcVarsEnv([string]$Arch) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $names = if ($Arch -eq 'arm64') { @('vcvarsamd64_arm64.bat', 'vcvarsarm64.bat', 'vcvars64.bat') } else { @('vcvars64.bat') }
  foreach ($n in $names) {
    $p = Join-Path $install "VC\Auxiliary\Build\$n"
    if (Test-Path $p) {
      $lines = cmd /c "call `"$p`" >nul && set"
      $env = @{}
      foreach ($line in $lines) {
        $i = $line.IndexOf('=')
        if ($i -gt 0) { $env[$line.Substring(0, $i)] = $line.Substring($i + 1) }
      }
      return $env
    }
  }
  throw "vcvars not found"
}

$src = Ensure-OpenSslSrc
$arch = if ($Triple -eq 'windows-arm64') { 'arm64' } else { 'x64' }
$vcEnv = Get-VcVarsEnv $arch
foreach ($k in $vcEnv.Keys) { Set-Item -Path "env:$k" -Value $vcEnv[$k] }

$toolsDir = Join-Path $RepoRoot 'native\out\_bootstrap-tools'
$perl = Resolve-PerlExe -ToolsDir $toolsDir
Ensure-JomOnPath -ToolsDir $toolsDir
Write-Host "Using perl: $perl"

$logDir = Join-Path $RepoRoot 'native\out'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir "build-$Triple.log"

function Show-BuildLogTail {
  param([string]$Path, [int]$Lines = 40)
  if (Test-Path -LiteralPath $Path) {
    Write-Host "--- last $Lines lines of $Path ---"
    Get-Content -Path $Path -Tail $Lines | ForEach-Object { Write-Host $_ }
    Write-Host '--- end log tail ---'
  }
}

Push-Location $src
$args = @('Configure', $Config, 'no-unit-test', 'no-makedepend', 'no-ssl', 'no-apps', 'no-asm', '/FS')
if ($QuietMode) {
  Write-Host "Configuring OpenSSL for $Triple (quiet; full log: $logFile)"
  "" | Set-Content -Path $logFile -Encoding UTF8
  & $perl @args *>> $logFile 2>&1
  if ($LASTEXITCODE -ne 0) {
    Show-BuildLogTail -Path $logFile
    throw "OpenSSL Configure failed (exit $LASTEXITCODE)"
  }
  Write-Host "Compiling libcrypto with jom ..."
  & jom -j $env:NUMBER_OF_PROCESSORS *>> $logFile 2>&1
  if ($LASTEXITCODE -ne 0) {
    Show-BuildLogTail -Path $logFile
    throw "jom build failed (exit $LASTEXITCODE)"
  }
  Write-Host "Build finished. Log: $logFile"
} else {
  & $perl @args
  if (-not (Get-Command jom -ErrorAction SilentlyContinue)) { throw 'jom required on PATH' }
  & jom -j $env:NUMBER_OF_PROCESSORS
}
Pop-Location

$dll = Get-ChildItem -Path $src -Filter 'libcrypto*.dll' | Select-Object -First 1
if (-not $dll) { throw 'libcrypto dll not found' }

New-Item -ItemType Directory -Force -Path $OutDir, $PrebuiltDir | Out-Null
Copy-Item $dll.FullName (Join-Path $PrebuiltDir $dll.Name) -Force
Copy-Item $dll.FullName (Join-Path $OutDir $dll.Name) -Force
Get-ChildItem $PrebuiltDir
