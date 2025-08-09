<#
Build DocLedger for Windows (PowerShell)

Usage examples (run in PowerShell on Windows):
  .\scripts\build_windows.ps1
  .\scripts\build_windows.ps1 -Msix

What this does:
  - Ensures prerequisites are installed (Git, Flutter, VS Build Tools with C++ Desktop workload, Windows SDK)
  - Enables Windows desktop, runs doctor, restores packages
  - Builds Windows Release EXE
  - Optionally creates an MSIX if configured
#>

[CmdletBinding()]
param(
  [switch]$Msix,
  # When provided, the script will attempt to install missing prerequisites via winget.
  # When omitted, the script will only verify and stop with guidance if something is missing.
  [switch]$InstallPrereqs
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Test-CommandExists([string]$cmd) {
  return $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Ensure-Winget() {
  if (-not (Test-CommandExists 'winget')) {
    Write-Warn 'winget not found. Install "App Installer" from Microsoft Store, then re-run this script.'
    throw 'winget not available'
  }
}

function Winget-InstallIfMissing([string]$id, [string]$name) {
  try {
    $installed = winget list --id $id -e 2>$null | Select-String $id -Quiet
    if ($installed) {
      Write-Info "$name already installed."
      return
    }
  } catch { }
  Write-Info "Installing $name via winget..."
  winget install --id $id -e --accept-package-agreements --accept-source-agreements --silent | Out-Null
}

function Ensure-Git([bool]$allowInstall) {
  if (Test-CommandExists 'git') { Write-Info 'Git found.'; return }
  if ($allowInstall) {
    Ensure-Winget
    Winget-InstallIfMissing -id 'Git.Git' -name 'Git'
  } else {
    Write-Err 'Git is not installed. Re-run with -InstallPrereqs to install automatically, or install Git manually.'
    throw 'Missing Git'
  }
}

function Ensure-Flutter([bool]$allowInstall) {
  if (Test-CommandExists 'flutter') { Write-Info 'Flutter found.'; return }
  if ($allowInstall) {
    Ensure-Winget
    Write-Info 'Installing Flutter (stable) via winget...'
    winget install --id Flutter.Flutter -e --accept-package-agreements --accept-source-agreements | Out-Null
    Write-Warn 'Flutter was installed. Open a NEW PowerShell window so PATH updates apply, then re-run this script.'
    throw 'Flutter just installed; please re-run in a new shell'
  } else {
    Write-Err 'Flutter is not available in PATH. Re-run with -InstallPrereqs to install automatically, or install Flutter and reopen PowerShell.'
    throw 'Missing Flutter'
  }
}

function Ensure-VSBuildToolsNativeDesktop([bool]$allowInstall) {
  # Check for Visual Studio with Native Desktop workload
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (Test-Path $vswhere) {
    $installations = & $vswhere -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath 2>$null
    if ($LASTEXITCODE -eq 0 -and $installations) {
      Write-Info 'Visual Studio with Native Desktop workload found.'
      return
    }
  }

  if ($allowInstall) {
    Ensure-Winget
    Write-Info 'Installing Visual Studio 2022 Build Tools with Native Desktop workload (this may take a while)...'
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-package-agreements --accept-source-agreements --override "--quiet --norestart --wait --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended" | Out-Null
    Write-Warn 'VS Build Tools installed/updated. If this was a fresh install, restart PowerShell before building.'
  } else {
    Write-Err "Visual Studio Build Tools with 'Desktop development with C++' workload not detected. Re-run with -InstallPrereqs or install via VS Installer."
    throw 'Missing VS Build Tools'
  }
}

function Ensure-CMakeNinja([bool]$allowInstall) {
  # Usually provided by VS workload, but install if missing
  if (-not (Test-CommandExists 'cmake')) {
    if ($allowInstall) { Winget-InstallIfMissing -id 'Kitware.CMake' -name 'CMake' }
    else { Write-Err 'CMake not found. Re-run with -InstallPrereqs or install manually.'; throw 'Missing CMake' }
  }
  if (-not (Test-CommandExists 'ninja')) {
    if ($allowInstall) { Winget-InstallIfMissing -id 'Ninja-build.Ninja' -name 'Ninja' }
    else { Write-Err 'Ninja not found. Re-run with -InstallPrereqs or install manually.'; throw 'Missing Ninja' }
  }
}

# Resolve repo root (script may be run from anywhere)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot
Write-Info "Repo root: $repoRoot"

# Ensure prerequisites (verify or install depending on -InstallPrereqs)
$allowInstall = [bool]$InstallPrereqs
if ($allowInstall) { Write-Info 'InstallPrereqs enabled: missing tools will be installed automatically.' }
else { Write-Info 'Verification mode: prerequisites must already be installed.' }

Ensure-Git -allowInstall:$allowInstall
Ensure-Flutter -allowInstall:$allowInstall
Ensure-VSBuildToolsNativeDesktop -allowInstall:$allowInstall
Ensure-CMakeNinja -allowInstall:$allowInstall

# Enable Windows desktop and fetch dependencies
Write-Info 'Enabling Windows desktop support'
flutter config --enable-windows-desktop | Out-Null

Write-Info 'Running flutter doctor'
flutter doctor -v

Write-Info 'Resolving dependencies'
flutter pub get

# Build Windows release
Write-Info 'Building Windows (Release)'
flutter build windows --release

$exePath = Join-Path $repoRoot 'build/windows/x64/runner/Release/doc_ledger.exe'
if (Test-Path $exePath) {
  Write-Info "Build complete: $exePath"
} else {
  Write-Warn 'Build finished but executable not found at expected path. Check build output directories.'
}

if ($Msix) {
  Write-Info 'MSIX packaging requested'
  # Only proceed if msix_config is present in pubspec.yaml
  $pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
  if ($pubspec -match 'msix_config:') {
    try {
      Write-Info 'Creating MSIX package'
      dart pub get
      dart run msix:create
    } catch {
      Write-Warn "MSIX packaging failed. Ensure 'msix' is added as a dev dependency and a valid msix_config exists in pubspec.yaml."
    }
  } else {
    Write-Warn 'No msix_config found in pubspec.yaml. Skipping MSIX packaging.'
  }
}

Write-Info 'Done.'


