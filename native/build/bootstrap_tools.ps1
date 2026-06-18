function New-BuildLogPath {
  param(
    [string]$LogDir,
    [string]$Triple
  )

  New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
  return Join-Path $LogDir "build-$Triple.$PID.log"
}

function Initialize-BuildLog {
  param([string]$Path)

  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $header = "=== build $(Get-Date -Format o) ==="
  [System.IO.File]::WriteAllText($Path, "$header`r`n")
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$Command,
    [string]$LogFile = '',
    [switch]$Quiet
  )

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    if ($Quiet -and $LogFile) {
      $output = & $Command 2>&1
      foreach ($line in @($output)) {
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
      }
    } else {
      & $Command
    }
    return [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
}

function Invoke-Executable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [string]$LogFile = '',
    [switch]$Quiet
  )

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    if ($Quiet -and $LogFile) {
      $output = & $FilePath @ArgumentList 2>&1
      foreach ($line in @($output)) {
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
      }
    } else {
      & $FilePath @ArgumentList
    }
    return [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
}

function Show-BuildLogTail {
  param([string]$Path, [int]$Lines = 40)
  if (Test-Path -LiteralPath $Path) {
    Write-Host "--- last $Lines lines of $Path ---"
    Get-Content -Path $Path -Tail $Lines | ForEach-Object { Write-Host $_ }
    Write-Host '--- end log tail ---'
  }
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
      Write-Host 'Downloading portable Strawberry Perl...'
      $null = Invoke-NativeCommand -Command { curl.exe -L $perlUrl -o $perlZip }
      if ($LASTEXITCODE -ne 0) { throw "Failed to download Strawberry Perl (exit $LASTEXITCODE)" }
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
  $env:PERL = $perlExe
  return $perlExe
}

function Ensure-JomOnPath {
  param([string]$ToolsDir)

  $jomDest = Join-Path $ToolsDir 'jom'
  $jomExe = Join-Path $jomDest 'jom.exe'
  if (Test-Path -LiteralPath $jomExe) {
    $env:PATH = "$(Split-Path -Parent $jomExe);$env:PATH"
    return $jomExe
  }
  if (Get-Command jom -ErrorAction SilentlyContinue) {
    return (Get-Command jom).Source
  }

  New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
  $jomZip = Join-Path $ToolsDir 'jom.zip'
  $jomUrl = 'https://download.qt.io/official_releases/jom/jom_1_1_5.zip'
  if (-not (Test-Path -LiteralPath $jomZip)) {
    Write-Host 'Downloading jom...'
    $null = Invoke-NativeCommand -Command { curl.exe -L $jomUrl -o $jomZip }
    if ($LASTEXITCODE -ne 0) { throw "Failed to download jom (exit $LASTEXITCODE)" }
  }
  if (Test-Path -LiteralPath $jomDest) {
    Remove-Item -Recurse -Force $jomDest
  }
  New-Item -ItemType Directory -Force -Path $jomDest | Out-Null
  Expand-Archive -Path $jomZip -DestinationPath $jomDest -Force
  if (-not (Test-Path -LiteralPath $jomExe)) {
    throw "jom not found at $jomExe after download"
  }
  $env:PATH = "$(Split-Path -Parent $jomExe);$env:PATH"
  return $jomExe
}

function Ensure-RmShim {
  param([string]$ToolsDir)

  $shimDir = Join-Path $ToolsDir 'shims'
  New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
  $rmCmd = Join-Path $shimDir 'rm.cmd'
  if (-not (Test-Path -LiteralPath $rmCmd)) {
    @'
@echo off
if /I "%~1"=="-f" shift
:loop
if "%~1"=="" exit /b 0
del /f /q "%~1" 2>nul
shift
goto loop
'@ | Set-Content -LiteralPath $rmCmd -Encoding Ascii
  }
  $env:PATH = "$shimDir;$env:PATH"
  return $rmCmd
}

function Ensure-GnuMakeOnPath {
  param([string]$ToolsDir)

  $makeDir = Join-Path $ToolsDir 'make'
  $makeExe = Join-Path $makeDir 'make.exe'
  if (Test-Path -LiteralPath $makeExe) {
    $env:PATH = "$makeDir;$env:PATH"
    return $makeExe
  }
  if (Get-Command make -ErrorAction SilentlyContinue) {
    return (Get-Command make).Source
  }

  New-Item -ItemType Directory -Force -Path $makeDir | Out-Null
  $makeZip = Join-Path $ToolsDir 'make.zip'
  $makeUrl = 'https://downloads.sourceforge.net/project/ezwinports/make-4.4.1-without-guile-w32-bin.zip'
  if (-not (Test-Path -LiteralPath $makeZip)) {
    Write-Host 'Downloading GNU make...'
    $exit = Invoke-NativeCommand -Command { curl.exe -L $makeUrl -o $makeZip }
    if ($exit -ne 0) { throw "Failed to download GNU make (exit $exit)" }
  }
  Expand-Archive -Path $makeZip -DestinationPath $makeDir -Force
  $nested = Get-ChildItem -Path $makeDir -Filter 'make.exe' -Recurse | Select-Object -First 1
  if ($nested -and $nested.DirectoryName -ne $makeDir) {
    Copy-Item $nested.FullName $makeExe -Force
  }
  if (-not (Test-Path -LiteralPath $makeExe)) {
    throw "make.exe not found after download (check $makeDir layout)"
  }
  $env:PATH = "$makeDir;$env:PATH"
  return $makeExe
}

function Convert-ToUnixPath([string]$Path) {
  return ($Path -replace '\\', '/')
}

function Ensure-OpenSslSrc {
  param(
    [string]$RepoRoot,
    [string]$Version,
    [string]$Triple
  )

  $thirdParty = Join-Path $RepoRoot 'native\third_party\openssl'
  if (Test-Path (Join-Path $thirdParty 'Configure')) {
    return $thirdParty
  }

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

function Patch-OpenSslAndroidConfForWindows {
  param([string]$SrcRoot)

  $conf = Join-Path $SrcRoot 'Configurations\15-android.conf'
  if (-not (Test-Path -LiteralPath $conf)) { return }
  $lines = Get-Content -LiteralPath $conf
  if ($lines -match 'OPENSSL_DART_WIN_NDK') { return }

  $ndkPrebuilt = 'm|^\Q$ndk\E[/\\].*[/\\]prebuilt[/\\]([^/\\]+)[/\\]|'
  $patched = foreach ($line in $lines) {
    if ($line -match 'which\("clang"\) =~ m\|\^\$ndk/.*/prebuilt/') {
      $line -replace 'm\|\^\$ndk/.*/prebuilt/\(\[\^/\]\+\)/\|', $ndkPrebuilt
    } elseif ($line -match 'which\("llvm-ar"\) =~ m\|\^\$ndk/.*/prebuilt/') {
      $line -replace 'm\|\^\$ndk/.*/prebuilt/\(\[\^/\]\+\)/\|', $ndkPrebuilt
    } elseif ($line -match 'which\("\$triarch-gcc"\) !~ m\|\^\$ndk/.*/prebuilt/') {
      $line -replace 'm\|\^\$ndk/.*/prebuilt/\(\[\^/\]\+\)/\|', $ndkPrebuilt
    } else {
      $line
    }
  }
  Write-TextLinesNoBom -Path $conf -Lines $patched
}

function Write-TextLinesNoBom {
  param(
    [string]$Path,
    [string[]]$Lines
  )
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($Path, $Lines, $utf8NoBom)
}

function Patch-OpenSslUnixCheckerForWindows {
  param([string]$SrcRoot)

  $checker = Join-Path $SrcRoot 'Configurations\unix-checker.pm'
  if (-not (Test-Path -LiteralPath $checker)) { return }
  $content = Get-Content -LiteralPath $checker -Raw
  if ($content -match 'OPENSSL_DART_WIN_ANDROID') { return }

  $content = $content.Replace(
    "if (rel2abs('.') !~ m|/|) {",
    'if (rel2abs(''.'') !~ m|/| && !$ENV{ANDROID_NDK_ROOT}) { # OPENSSL_DART_WIN_ANDROID'
  )
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($checker, $content, $utf8NoBom)
}

function Patch-OpenSslConfigureWhichForWindows {
  param([string]$SrcRoot)

  $configure = Join-Path $SrcRoot 'Configure'
  if (-not (Test-Path -LiteralPath $configure)) { return }
  $lines = [System.Collections.Generic.List[string]]@(Get-Content -LiteralPath $configure)
  $changed = $false

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'if \(eval \{ require IPC::Cmd; 1; \}\)' -and $lines[$i] -notmatch 'OPENSSL_DART_WIN_WHICH') {
      $lines[$i] = $lines[$i].Replace(
        'if (eval { require IPC::Cmd; 1; }) {',
        'if (0 && eval { require IPC::Cmd; 1; }) { # OPENSSL_DART_WIN_WHICH'
      )
      $changed = $true
    }
    if ($lines[$i] -match '^\s+foreach \(File::Spec->path\(\)\) \{' -and ($i + 1) -lt $lines.Count -and $lines[$i + 1] -match 'my \$fullpath = catfile') {
      $indent = ($lines[$i] -replace '^(\s+).*', '$1')
      $lines[$i] = "${indent}foreach (File::Spec->path()) { # OPENSSL_DART_WIN_EXE"
      for ($j = 0; $j -lt 5; $j++) { $lines.RemoveAt($i + 1) }
      $insert = @(
        "${indent}    my @exts = (`$target{exe_extension});",
        "${indent}    push @exts, '.exe' if (`$^O =~ /^(mswin|MSWin)/x);",
        "${indent}    for my `$ext (@exts) {",
        "${indent}        my `$fullpath = catfile(`$_, ""`$name`$ext"");",
        "${indent}        if (-f `$fullpath and -x `$fullpath) {",
        "${indent}            return `$fullpath;",
        "${indent}        }",
        "${indent}    }",
        "${indent}}"
      )
      for ($j = $insert.Count - 1; $j -ge 0; $j--) {
        $lines.Insert($i + 1, $insert[$j])
      }
      $changed = $true
      break
    }
  }

  if ($changed) {
    Write-TextLinesNoBom -Path $configure -Lines $lines
  }
}

function Complete-LibcryptoSharedLink {
  param(
    [string]$SrcRoot,
    [string]$ToolchainBin,
    [string]$ArchPrefix,
    [int]$ApiLevel,
    [string]$MakeExe,
    [string]$LogFile = ''
  )

  Push-Location $SrcRoot
  try {
    foreach ($lib in @('providers\libcommon.a', 'providers\libdefault.a')) {
      if (-not (Test-Path -LiteralPath $lib)) {
        $depExit = if ($LogFile) {
          Invoke-Executable -FilePath $MakeExe -ArgumentList @($lib) -LogFile $LogFile -Quiet
        } else {
          & $MakeExe $lib
          $LASTEXITCODE
        }
        if ($depExit -ne 0) { return $depExit }
      }
    }

    $objects = Get-ChildItem -Path $SrcRoot -Recurse -Filter 'libcrypto-shlib-*.o' -File
    if (-not $objects) { return 1 }

    $rsp = Join-Path $SrcRoot '_link_objects.rsp'
    $objects | ForEach-Object { ($_.FullName -replace '\\', '/') } | Set-Content -LiteralPath $rsp -Encoding Ascii

    $clang = Join-Path $ToolchainBin "${ArchPrefix}-linux-android${ApiLevel}-clang.cmd"
    $outSo = ($outSoPath = Join-Path $SrcRoot 'libcrypto.so') -replace '\\', '/'
    $libDefault = (Join-Path $SrcRoot 'providers\libdefault.a') -replace '\\', '/'
    $libCommon = (Join-Path $SrcRoot 'providers\libcommon.a') -replace '\\', '/'
    $rspUnix = $rsp -replace '\\', '/'
    $args = @("@$rspUnix", $libDefault, $libCommon, '-shared', '-o', $outSo, '-ldl', '-pthread')

    if ($LogFile) {
      return (Invoke-Executable -FilePath $clang -ArgumentList $args -LogFile $LogFile -Quiet)
    }
    & $clang @args
    return $LASTEXITCODE
  } finally {
    Pop-Location
  }
}
