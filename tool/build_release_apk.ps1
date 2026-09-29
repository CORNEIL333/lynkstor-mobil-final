#Requires -Version 5.1
<#
.SYNOPSIS
  Build APK (et optionnellement AAB) release Lynkstor avec verifications P0.
  NOTE: ce fichier doit rester en ASCII pur - Windows PowerShell 5.1 lit les
  .ps1 sans BOM en ANSI; les accents/em-dashes UTF-8 cassent le parseur.

.PARAMETER Bundle
  Aussi construire l'AAB Play Store.

.PARAMETER SkipTests
  Ne pas executer la porte flutter test (a n'utiliser que si les echecs sont
  connus et etrangers au build).

.PARAMETER AllowDebugSigning
  Autorise le build meme sans key.properties (signature debug - pilote uniquement).
#>
param(
    [switch]$Bundle,
    [switch]$SkipTests,
    [switch]$AllowDebugSigning
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$propsPath = Join-Path $root "android\key.properties"
$jksHint = Join-Path $root "android\kumba_release.jks"
$apkPath = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
$aabPath = Join-Path $root "build\app\outputs\bundle\release\app-release.aab"
$outDir = Join-Path $root "build\release-artifacts"

Write-Host ""
Write-Host "=== Lynkstor - Build release ===" -ForegroundColor Cyan
Write-Host "Dossier : $root"
Write-Host ""

$hasKeystore = (Test-Path $propsPath)
if (-not $hasKeystore) {
    Write-Host "key.properties ABSENT - signature DEBUG (pas pour Play Store)." -ForegroundColor Yellow
    Write-Host "  Creer le keystore :  powershell -File tool/create_release_keystore.ps1"
    if (-not $AllowDebugSigning) {
        Write-Host ""
        Write-Host "Refus du build non signe release. Relancez avec -AllowDebugSigning pour un pilote." -ForegroundColor Red
        exit 2
    }
    Write-Host "Continuation avec -AllowDebugSigning..." -ForegroundColor Yellow
} else {
    Write-Host "Signature release : key.properties present." -ForegroundColor Green
    if (-not (Test-Path $jksHint)) {
        Write-Host "Avertissement : android/kumba_release.jks introuvable - verifiez storeFile." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "1) flutter pub get..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "2) flutter test (smoke)..." -ForegroundColor Cyan
if ($SkipTests) {
    Write-Host "Porte de tests IGNOREE (-SkipTests)." -ForegroundColor Yellow
} else {
    flutter test
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Tests echoues - build annule." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "3) flutter build apk --release (arm64 seul)..." -ForegroundColor Cyan
# arm64 seul : la cible materielle est 64 bits; diviser par ~3 le poids des .so.
flutter build apk --release --target-platform android-arm64
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Bundle) {
    Write-Host ""
    Write-Host "4) flutter build appbundle --release..." -ForegroundColor Cyan
    flutter build appbundle --release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

function Get-Sha256([string]$path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = Join-Path $outDir "build-report-$stamp.txt"

$apkInfo = Get-Item $apkPath
$apkSha = Get-Sha256 $apkPath
Copy-Item $apkPath (Join-Path $outDir "lynkstor-$stamp-release.apk") -Force

$lines = @(
    "Lynkstor Business - rapport build release",
    "Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Signed   : $(if ($hasKeystore) { 'RELEASE keystore' } else { 'DEBUG (pilote)' })",
    "",
    "APK",
    "  Path   : $apkPath",
    "  SizeMB : $([math]::Round($apkInfo.Length / 1MB, 2))",
    "  SHA256 : $apkSha",
    "  Copy   : build/release-artifacts/lynkstor-$stamp-release.apk"
)

if ($Bundle -and (Test-Path $aabPath)) {
    $aabInfo = Get-Item $aabPath
    $aabSha = Get-Sha256 $aabPath
    Copy-Item $aabPath (Join-Path $outDir "lynkstor-$stamp-release.aab") -Force
    $lines += @(
        "",
        "AAB",
        "  Path   : $aabPath",
        "  SizeMB : $([math]::Round($aabInfo.Length / 1MB, 2))",
        "  SHA256 : $aabSha"
    )
}

$lines += @(
    "",
    "Install pilote :",
    "  adb install -r build/app/outputs/flutter-apk/app-release.apk",
    "",
    "Checklist terrain : docs/FIELD_CHECKLIST.md"
)

$lines | Set-Content -Path $report -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "OK - Artefacts dans build/release-artifacts/" -ForegroundColor Green
Write-Host "Rapport : $report"
Write-Host ""
