# One-shot : SQL (via MCP/dashboard déjà fait) + seed + function + secrets
# Prérequis : CLI connecté avec le compte PROPRIÉTAIRE du projet wtbmwquovcizrtggkkzn
# et SUPABASE_SERVICE_ROLE_KEY dans deploy/secrets.local.env

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$ref = "wtbmwquovcizrtggkkzn"

Write-Host "== 1) Link projet =="
npx supabase link --project-ref $ref

Write-Host "== 2) Push migrations =="
npx supabase db push --yes

Write-Host "== 3) Secrets Edge Functions =="
# Charge secrets.local.env si présent
$sec = Join-Path $PSScriptRoot "secrets.local.env"
if (Test-Path $sec) {
  Get-Content $sec | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
    $k,$v = $_.Split('=',2)
    [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), "Process")
  }
}

if (-not $env:ADMIN_API_KEY) { $env:ADMIN_API_KEY = "lynkstor-admin-$(Get-Random)" }
if (-not $env:ADMIN_USER) { $env:ADMIN_USER = "admin" }
# Pas de mot de passe par defaut : un secret fige dans le script finit tot ou
# tard dans le depot. Definir ADMIN_PASSWORD (secrets.local.env ou env).
if (-not $env:ADMIN_PASSWORD) {
  Write-Error "ADMIN_PASSWORD manquant - definissez-le dans deploy/secrets.local.env ou la variable d'environnement."
  exit 1
}
if (-not $env:WEBHOOK_SECRET) { $env:WEBHOOK_SECRET = "lynkstor-webhook-$(Get-Random)" }

npx supabase secrets set `
  "ADMIN_API_KEY=$($env:ADMIN_API_KEY)" `
  "ADMIN_USER=$($env:ADMIN_USER)" `
  "ADMIN_PASSWORD=$($env:ADMIN_PASSWORD)" `
  "WEBHOOK_SECRET=$($env:WEBHOOK_SECRET)" `
  --project-ref $ref

Write-Host "== 4) Deploy function =="
npx supabase functions deploy lynkstor-api --project-ref $ref --no-verify-jwt

Write-Host "== 5) Seed data =="
Set-Location (Join-Path $Root "server")
node apply_remote.js

Write-Host "== 6) Health check =="
$h = @{
  apikey = $env:SUPABASE_ANON_KEY
  Authorization = "Bearer $($env:SUPABASE_ANON_KEY)"
}
try {
  Invoke-RestMethod -Uri "https://$ref.supabase.co/functions/v1/lynkstor-api/health" -Headers $h
} catch {
  Write-Host "Health: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "OK. Admin login: $($env:ADMIN_USER) / $($env:ADMIN_PASSWORD)"
Write-Host "Codes test: DEMO0001 DEMO0002 AGENT001 (après seed)"
Write-Host "ADMIN_API_KEY: $($env:ADMIN_API_KEY)"
