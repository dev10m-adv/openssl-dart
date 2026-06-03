param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('windows-x64', 'windows-arm64')]
  [string]$Triple,

  [string]$OutDir = '',
  [string]$PrebuiltDir = ''
)

$ErrorActionPreference = 'Stop'
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

Push-Location $src
$args = @('Configure', $Config, 'no-unit-test', 'no-makedepend', 'no-ssl', 'no-apps', 'no-asm', '/FS')
& perl @args
if (-not (Get-Command jom -ErrorAction SilentlyContinue)) { throw 'jom required on PATH' }
& jom -j $env:NUMBER_OF_PROCESSORS
Pop-Location

$dll = Get-ChildItem -Path $src -Filter 'libcrypto*.dll' | Select-Object -First 1
if (-not $dll) { throw 'libcrypto dll not found' }

New-Item -ItemType Directory -Force -Path $OutDir, $PrebuiltDir | Out-Null
Copy-Item $dll.FullName (Join-Path $PrebuiltDir $dll.Name) -Force
Copy-Item $dll.FullName (Join-Path $OutDir $dll.Name) -Force
Get-ChildItem $PrebuiltDir
