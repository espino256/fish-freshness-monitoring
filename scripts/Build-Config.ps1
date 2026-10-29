$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $projectRoot '.env'
$keys = @('FIREBASE_API_KEY', 'FIREBASE_AUTH_DOMAIN', 'FIREBASE_DATABASE_URL', 'FIREBASE_PROJECT_ID', 'FIREBASE_STORAGE_BUCKET', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_APP_ID', 'FIREBASE_IOS_BUNDLE_ID', 'GOOGLE_CLIENT_ID', 'GOOGLE_SERVER_CLIENT_ID')
$optionalKeys = @('FIREBASE_IOS_BUNDLE_ID', 'GOOGLE_CLIENT_ID', 'GOOGLE_SERVER_CLIENT_ID')
$values = @{}
if (Test-Path -LiteralPath $envFile) {
  foreach ($line in Get-Content -LiteralPath $envFile) {
    $trimmed = $line.Trim()
    if (!$trimmed -or $trimmed.StartsWith('#')) { continue }
    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) { throw 'Invalid .env line. Expected KEY=value.' }
    $key = $trimmed.Substring(0, $separator).Trim()
    if ($keys -notcontains $key) { throw 'Unexpected .env key.' }
    $value = $trimmed.Substring($separator + 1).Trim()
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) { $value = $value.Substring(1, $value.Length - 2) }
    $values[$key] = $value
  }
}
foreach ($key in $keys) {
  $fromEnvironment = [Environment]::GetEnvironmentVariable($key)
  if ($null -ne $fromEnvironment) { $values[$key] = $fromEnvironment }
  if ($optionalKeys -notcontains $key -and (!$values[$key] -or $values[$key].Contains('replace-me'))) { throw "Configure $key in .env or the process environment." }
}
if (!$values['FIREBASE_DATABASE_URL'].StartsWith('https://')) { throw 'FIREBASE_DATABASE_URL must use HTTPS.' }
$configDirectory = Join-Path $projectRoot 'config'
New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
$outputFile = Join-Path $configDirectory 'firebase.local.json'
[IO.File]::WriteAllText($outputFile, ($values | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Output 'Created ignored config/firebase.local.json. Configuration values were not printed.'
