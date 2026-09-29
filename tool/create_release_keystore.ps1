#Requires -Version 5.1
<#
.SYNOPSIS
  Crée le keystore release Android Lynkstor + android/key.properties

.DESCRIPTION
  - Génère kumba_release.jks (hors git, déjà ignoré)
  - Écrit android/key.properties (hors git)
  - Sauvegarde un mémo local (à copier hors machine) : secrets/keystore-backup.txt

  Ne jamais committer .jks, key.properties, ni le mémo de mots de passe.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$android = Join-Path $root "android"
$jksPath = Join-Path $android "kumba_release.jks"
$propsPath = Join-Path $android "key.properties"
$secretsDir = Join-Path $root "secrets"
$backupPath = Join-Path $secretsDir "keystore-backup.txt"
$alias = "kumba_release_key"

Write-Host ""
Write-Host "=== Lynkstor — Keystore release Android ===" -ForegroundColor Cyan
Write-Host "Projet : $root"
Write-Host ""

if (Test-Path $jksPath) {
    Write-Host "ATTENTION : $jksPath existe déjà." -ForegroundColor Yellow
    $overwrite = Read-Host "Écraser ? (oui/NON)"
    if ($overwrite -ne "oui") {
        Write-Host "Annulé. Rien n'a été modifié."
        exit 0
    }
    Remove-Item $jksPath -Force
}

# keytool (JDK / Android Studio)
$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    $candidates = @(
        "$env:JAVA_HOME\bin\keytool.exe",
        "$env:LOCALAPPDATA\Android\Sdk\jbr\bin\keytool.exe",
        "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe",
        "C:\Program Files\Java\*\bin\keytool.exe"
    )
    foreach ($c in $candidates) {
        $resolved = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) {
            $keytool = $resolved.FullName
            break
        }
    }
}
if (-not $keytool) {
    Write-Host "keytool introuvable. Installez un JDK 17+ ou Android Studio, puis relancez." -ForegroundColor Red
    exit 1
}

function New-StrongPassword([int]$len = 24) {
    $chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%+=_"
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $len
    $rng.GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

$useCustom = Read-Host "Mots de passe personnalisés ? (o/N)"
if ($useCustom -eq "o" -or $useCustom -eq "O") {
    $storePass = Read-Host "storePassword (min 8 car.)"
    $keyPass = Read-Host "keyPassword (min 8 car., souvent identique)"
    if ($storePass.Length -lt 8 -or $keyPass.Length -lt 8) {
        Write-Host "Mots de passe trop courts." -ForegroundColor Red
        exit 1
    }
} else {
    $storePass = New-StrongPassword 28
    $keyPass = $storePass
    Write-Host "Mots de passe forts générés automatiquement." -ForegroundColor Green
}

$cn = Read-Host "Nom organisation / commerce (CN) [Lynkstor]"
if ([string]::IsNullOrWhiteSpace($cn)) { $cn = "Lynkstor" }
$ou = "Mobile"
$o = $cn
$l = "Douala"
$st = "Littoral"
$c = "CM"

$dname = "CN=$cn, OU=$ou, O=$o, L=$l, ST=$st, C=$c"
Write-Host "Génération du keystore..." -ForegroundColor Cyan

& $keytool -genkeypair `
    -v `
    -storetype JKS `
    -keystore $jksPath `
    -alias $alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -storepass $storePass `
    -keypass $keyPass `
    -dname $dname

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $jksPath)) {
    Write-Host "Échec keytool." -ForegroundColor Red
    exit 1
}

# storeFile relatif à android/app/ (file() dans build.gradle.kts)
# build.gradle.kts : storeFile = file(keystoreProperties["storeFile"])
# depuis app/ → ../kumba_release.jks pointe vers android/kumba_release.jks
@"
storePassword=$storePass
keyPassword=$keyPass
keyAlias=$alias
storeFile=../kumba_release.jks
"@ | Set-Content -Path $propsPath -Encoding UTF8 -NoNewline

if (-not (Test-Path $secretsDir)) {
    New-Item -ItemType Directory -Path $secretsDir | Out-Null
}

$when = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
@"
# MÉMO KEYSTORE LYNKSTOR — CONFIDENTIEL — NE PAS COMMITTER
# Créé : $when
# Conservez une copie hors PC (coffre, USB chiffré, password manager).

applicationId=com.kumba.kumba_business
alias=$alias
storeFile=android/kumba_release.jks
storePassword=$storePass
keyPassword=$keyPass

# Perdre ce fichier + le .jks = impossible de mettre à jour l'app sur Play Store
# avec le même package.
"@ | Set-Content -Path $backupPath -Encoding UTF8

Write-Host ""
Write-Host "OK — Keystore créé." -ForegroundColor Green
Write-Host "  JKS          : $jksPath"
Write-Host "  key.properties : $propsPath"
Write-Host "  Mémo backup  : $backupPath"
Write-Host ""
Write-Host "Prochaine étape :" -ForegroundColor Cyan
Write-Host "  powershell -File tool/build_release_apk.ps1"
Write-Host "  (ou) flutter build apk --release"
Write-Host ""
Write-Host "COPIEZ secrets/keystore-backup.txt hors de cette machine, puis verrouillez-le." -ForegroundColor Yellow
Write-Host ""
