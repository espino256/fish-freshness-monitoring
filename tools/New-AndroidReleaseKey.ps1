[CmdletBinding()]
param()

# First release only. Never use this to replace a key for an existing app.
$ErrorActionPreference = 'Stop'
$androidDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\android'))
$keyFile = Join-Path $androidDirectory 'app\aquasense-release.jks'
$propertiesFile = Join-Path $androidDirectory 'key.properties'
foreach ($target in @($keyFile, $propertiesFile)) {
    if (Test-Path -LiteralPath $target) {
        throw 'Signing files already exist. Reuse or restore your existing signing setup; no files were overwritten.'
    }
}

$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytoolCommand) {
    throw 'keytool is unavailable. Add your installed JDK bin directory to PATH and retry.'
}

function Protect-SigningFile([string]$Path) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    # Codex may create files as a sandbox identity while Gradle runs as the
    # project owner. Preserve that owner's access without granting all users.
    $projectOwner = (Get-Acl -LiteralPath $androidDirectory).Owner
    # Change only the DACL; copying an existing full security descriptor can
    # require SeSecurityPrivilege unnecessarily on restricted Windows accounts.
    $security = New-Object Security.AccessControl.FileSecurity
    $security.SetAccessRuleProtection($true, $false)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        $identity, [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow)
    $security.AddAccessRule($rule)
    $ownerRule = New-Object Security.AccessControl.FileSystemAccessRule(
        $projectOwner, [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow)
    $security.AddAccessRule($ownerRule)
    [IO.File]::SetAccessControl($Path, $security)
}

$randomBytes = New-Object byte[] 32
$generator = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
$signingPassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$previousPassword = [Environment]::GetEnvironmentVariable('AQUASENSE_NEW_RELEASE_PASSWORD', 'Process')

try {
    # CreateNew refuses to overwrite even if another process creates the file
    # after the initial existence check. Secure it before writing credentials.
    $stream = [IO.File]::Open($propertiesFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        Protect-SigningFile $propertiesFile
        $contents = "# Local signing secrets. Never commit or share this file.`n" +
            "storeFile=aquasense-release.jks`nstorePassword=$signingPassword`n" +
            "keyAlias=aquasense-release`nkeyPassword=$signingPassword`n"
        $encoded = [Text.Encoding]::UTF8.GetBytes($contents)
        $stream.Write($encoded, 0, $encoded.Length)
    } finally { $stream.Dispose() }

    # Keep passwords out of the command line and console output.
    [Environment]::SetEnvironmentVariable('AQUASENSE_NEW_RELEASE_PASSWORD', $signingPassword, 'Process')
    & $keytoolCommand.Source -genkeypair -keystore $keyFile -storetype JKS `
        -alias aquasense-release -keyalg RSA -keysize 3072 -validity 10000 `
        -dname 'CN=AquaSense' -storepass:env AQUASENSE_NEW_RELEASE_PASSWORD `
        -keypass:env AQUASENSE_NEW_RELEASE_PASSWORD -noprompt
    if ($LASTEXITCODE -ne 0) {
        throw 'keytool failed. The local properties file was retained for recovery; do not overwrite existing signing files.'
    }
    Protect-SigningFile $keyFile
    Write-Host 'Created android/app/aquasense-release.jks and android/key.properties.'
    Write-Host 'Back up both files securely. Future APK updates must use this same key.'
    Write-Host 'Run: flutter build apk --release'
} finally {
    [Environment]::SetEnvironmentVariable('AQUASENSE_NEW_RELEASE_PASSWORD', $previousPassword, 'Process')
    $signingPassword = $null
    $contents = $null
    $encoded = $null
    [Array]::Clear($randomBytes, 0, $randomBytes.Length)
}
