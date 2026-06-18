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
. (Join-Path $ScriptDir 'bootstrap_tools.ps1')
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
  $tarballDir = Join-Path $RepoRoot 'native\out\_src'
  $work = Join-Path $tarballDir $Triple
  New-Item -ItemType Directory -Force -Path $work, $tarballDir | Out-Null
  $tarball = "openssl-$Version.tar.gz"
  $url = "https://github.com/openssl/openssl/releases/download/openssl-$Version/$tarball"
  $tarPath = Join-Path $tarballDir $tarball
  if (-not (Test-Path $tarPath)) {
    $exit = Invoke-NativeCommand -Command { curl.exe -L $url -o $tarPath }
    if ($exit -ne 0) { throw "Failed to download OpenSSL source (exit $exit)" }
  }
  $extracted = Join-Path $work "openssl-$Version"
  if (Test-Path (Join-Path $extracted 'Configure')) { return $extracted }
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
  throw 'vcvars not found'
}

$src = Ensure-OpenSslSrc
$arch = if ($Triple -eq 'windows-arm64') { 'arm64' } else { 'x64' }
$vcEnv = Get-VcVarsEnv $arch
foreach ($k in $vcEnv.Keys) { Set-Item -Path "env:$k" -Value $vcEnv[$k] }

$toolsDir = Join-Path $RepoRoot 'native\out\_bootstrap-tools'
$perl = Resolve-PerlExe -ToolsDir $toolsDir
Ensure-JomOnPath -ToolsDir $toolsDir | Out-Null
Write-Host "Using perl: $perl"

$logDir = Join-Path $RepoRoot 'native\out'
$logFile = New-BuildLogPath -LogDir $logDir -Triple $Triple

Push-Location $src
$configureArgs = @('Configure', $Config, 'no-unit-test', 'no-makedepend', 'no-ssl', 'no-apps', 'no-asm', '/FS')
if ($QuietMode) {
  Write-Host "Configuring OpenSSL for $Triple (quiet; full log: $logFile)"
  Initialize-BuildLog -Path $logFile
  $cfgExit = Invoke-Executable -FilePath $perl -ArgumentList $configureArgs -LogFile $logFile -Quiet
  if ($cfgExit -ne 0) {
    Show-BuildLogTail -Path $logFile
    throw "OpenSSL Configure failed (exit $cfgExit)"
  }
  Write-Host 'Compiling libcrypto with jom ...'
  $jomExe = (Get-Command jom).Source
  $jomExit = Invoke-Executable -FilePath $jomExe -ArgumentList @('-j', $env:NUMBER_OF_PROCESSORS) -LogFile $logFile -Quiet
  if ($jomExit -ne 0) {
    Show-BuildLogTail -Path $logFile
    throw "jom build failed (exit $jomExit)"
  }
  Write-Host "Build finished. Log: $logFile"
} else {
  & $perl @configureArgs
  if ($LASTEXITCODE -ne 0) { throw "OpenSSL Configure failed (exit $LASTEXITCODE)" }
  if (-not (Get-Command jom -ErrorAction SilentlyContinue)) { throw 'jom required on PATH' }
  jom -j $env:NUMBER_OF_PROCESSORS
  if ($LASTEXITCODE -ne 0) { throw "jom build failed (exit $LASTEXITCODE)" }
}
Pop-Location

$dll = Get-ChildItem -Path $src -Filter 'libcrypto*.dll' | Select-Object -First 1
if (-not $dll) { throw 'libcrypto dll not found' }

New-Item -ItemType Directory -Force -Path $OutDir, $PrebuiltDir | Out-Null
Copy-Item $dll.FullName (Join-Path $PrebuiltDir $dll.Name) -Force
Copy-Item $dll.FullName (Join-Path $OutDir $dll.Name) -Force
Get-ChildItem $PrebuiltDir
