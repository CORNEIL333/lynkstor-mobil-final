# Seeds / resets the fixture that tool/verify_neon_backend.mjs needs.
#
# Idempotent, and scoped to E2E identifiers only (LYNK-E2E-AUTO, the fixed
# b000.../a000... seed rows) : it never touches a real merchant's data.
#
# The E2E run CONSUMES the activation code and LOGS IN as an admin to issue a
# license, so both must exist. Credentials are never hardcoded here: pass
#   $Env:E2E_ADMIN_USERNAME / $Env:E2E_ADMIN_PASSWORD   (min 12 chars)
# and the script (re)hashes them with pbkdf2-sha256, exactly like the gateway
# verifies them. Without them, only the code is (re)seeded and the existing
# staff row is left untouched.
#
# Usage:  powershell -File tool/seed_e2e_demo.ps1
param(
  [string]$Code = "LYNK-E2E-AUTO",
  [string]$Instance = "production",
  [string]$Role = "neondb_owner"
)

$ErrorActionPreference = "Stop"

$STAFF = "b0000000-0000-0000-0000-000000000001"
$PLAN  = "a0000000-0000-0000-0000-000000000001"

if ($Code -notmatch '^[A-Z0-9\-]{6,32}$') {
  throw "Refus : '$Code' n'est pas un code E2E (MAJUSCULES, chiffres, tirets ; 6 a 32)."
}
if ($Code -eq "LYNK-TEST-2026") {
  throw "Refus : LYNK-TEST-2026 est le code de demonstration, pas un code E2E."
}

$sql = @"
SET search_path TO lynkstor,public;
-- Plan de reference du code d'activation (seed fixe, non ecrase).
INSERT INTO plans (id,name,price_fcfa,billing_period,max_devices,features,is_active)
VALUES ('$PLAN','STARTER',15000,'monthly',3,'{}'::jsonb,true)
ON CONFLICT (id) DO NOTHING;
"@

$adminUser = $Env:E2E_ADMIN_USERNAME
$adminPass = $Env:E2E_ADMIN_PASSWORD

if ($adminPass) {
  if ($adminPass.Length -lt 12) { throw "E2E_ADMIN_PASSWORD trop court (minimum 12 caracteres)." }
  if (-not $adminUser) { throw "E2E_ADMIN_USERNAME requis quand E2E_ADMIN_PASSWORD est fourni." }
  if ($adminUser -notmatch '^[a-z0-9\-_.]{3,32}$') { throw "E2E_ADMIN_USERNAME invalide." }

  # Hache ici, jamais en clair : pbkdf2-sha256$210000$salt$hash (format gateway).
  $salt = [byte[]]::new(16)
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
  $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
    $adminPass, $salt, 210000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
  $hash = $kdf.GetBytes(32)
  $saltHex = ($salt | ForEach-Object { $_.ToString('x2') }) -join ''
  $hashHex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
  $ph = 'pbkdf2-sha256$210000$' + $saltHex + '$' + $hashHex

  $sql += @"

-- Compte admin E2E : re-cree ou met a jour le credential, jamais de mot de passe en dur.
INSERT INTO staff_accounts (id,full_name,email,username,phone,password_hash,role,status)
VALUES ('$STAFF','E2E Agent','e2e@lynkstor.invalid','$adminUser','','$ph','super_admin','active')
ON CONFLICT (id) DO UPDATE
   SET username = EXCLUDED.username,
       email    = EXCLUDED.email,
       password_hash = EXCLUDED.password_hash,
       role     = EXCLUDED.role,
       status   = 'active';
"@
  Write-Host "Credential E2E rehashe pour l'utilisateur '$adminUser' (mot de passe non affiche)."
} else {
  Write-Warning "Aucun E2E_ADMIN_PASSWORD : aucun credential ecrit. Le run E2E echouera a l'emission de licence tant que E2E_ADMIN_USERNAME/E2E_ADMIN_PASSWORD ne sont pas fournis."
}

# /register consomme le code a chaque run : on le remet disponible.
$sql += @"

DELETE FROM registration_codes WHERE code = '$Code';
INSERT INTO registration_codes (id,code,business_name,owner_phone,assigned_staff,plan_id,status)
VALUES (gen_random_uuid(),'$Code','E2E Shop','+2250700000001','$STAFF','$PLAN','available');
SELECT 'e2e_seeded' AS status,
       (SELECT status FROM registration_codes WHERE code = '$Code') AS code_status,
       (SELECT username FROM staff_accounts  WHERE id   = '$STAFF') AS staff_username,
       (SELECT role     FROM staff_accounts  WHERE id   = '$STAFF') AS staff_role;
"@

# `neon psql` bruit la sortie stderr sous PowerShell 5.1.
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$out = $sql | neon psql $Instance --role-name $Role 2>&1 |
  Select-String -NotMatch "node\.exe|Au caract|CategoryInfo|FullyQualified|~~~~|Connecting|falling back|SSL|Type '\.help|neondb=>|^SET$"
$ErrorActionPreference = $prev

$out
if ($LASTEXITCODE -ne 0) { throw "neon psql a echoue (exit $LASTEXITCODE)." }
