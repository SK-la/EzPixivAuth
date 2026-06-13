#Requires -Version 5.1
<#
.SYNOPSIS
    EzPixivAuth - one-time Pixiv OAuth helper for Ez2Lazer.

.DESCRIPTION
    Double-click GetPixivRefreshToken.bat. A WebView2 window opens (Pixiv Android user-agent).
    After login, writes pixiv_auth.json into the Ez2Lazer data folder for immediate use.

.PARAMETER DataPath
    Ez2Lazer data directory (same folder as client.realm). Auto-detected when omitted.

.EXAMPLE
    Double-click GetPixivRefreshToken.bat
#>
[CmdletBinding()]
param(
    [string]$DataPath = '',
    [string]$ProxyUrl = ''
)

$ErrorActionPreference = 'Stop'

# PS 5.1 on localized Windows defaults to system ANSI unless the script has a UTF-8 BOM.
# Keep console + file I/O on UTF-8 so paths and messages render correctly everywhere.
try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
    if ($Host.Name -eq 'ConsoleHost') {
        chcp 65001 | Out-Null
    }
}
catch {
    # Some hosts (IDE run configs) reject chcp; user-visible text stays ASCII-only.
}

# Public Pixiv app OAuth client (same as ZipFile/pixiv_auth.py PKCE flow; Android login + this client pair).
$clientId = 'MOBrBDS8blbauoSck0ZfDbtuzpyT'
$clientSecret = 'lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj'
$redirectUri = 'https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback'
$tokenUrl = 'https://oauth.secure.pixiv.net/auth/token'
$userAgent = 'PixivAndroidApp/5.0.234 (Android 11; Pixel 5)'

function Get-StorageIniFullPath {
    param([string]$IniPath)

    if (-not (Test-Path -LiteralPath $IniPath)) {
        return $null
    }

    foreach ($line in Get-Content -LiteralPath $IniPath -Encoding UTF8) {
        if ($line -match '^\s*FullPath\s*=\s*(.+?)\s*$') {
            return $Matches[1].Trim().Trim('"')
        }
    }

    return $null
}

function Test-Ez2LazerDataDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    if (Test-Path -LiteralPath (Join-Path $Path 'client.realm')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Path 'framework.ini')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Path 'pixiv_auth.json')) { return $true }

    return @(Get-ChildItem -LiteralPath $Path -Filter 'client_*.realm' -ErrorAction SilentlyContinue).Count -gt 0
}

function Add-UniquePathCandidate {
    param(
        [System.Collections.Generic.List[string]]$List,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $normalized = [System.IO.Path]::GetFullPath($Path.Trim().Trim('"'))
    }
    catch {
        return
    }

    if ($Seen.Add($normalized)) {
        $List.Add($normalized)
    }
}

function Get-Ez2LazerDataPathCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    if ($env:EZ2LAZER_DATA_PATH) {
        Add-UniquePathCandidate -List $candidates -Seen $seen -Path $env:EZ2LAZER_DATA_PATH
    }

    foreach ($processName in @('Ez2osu!', 'Ez2osu')) {
        foreach ($proc in Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            if ($proc.Path) {
                Add-UniquePathCandidate -List $candidates -Seen $seen -Path (Split-Path -Parent $proc.Path)
            }
        }
    }

    $appData = [Environment]::GetFolderPath('ApplicationData')
    foreach ($dirName in @('osu-Ez2Lazer', 'osu-Ez2Lazer-development')) {
        $configRoot = Join-Path $appData $dirName
        $customPath = Get-StorageIniFullPath -IniPath (Join-Path $configRoot 'storage.ini')
        if ($customPath) {
            Add-UniquePathCandidate -List $candidates -Seen $seen -Path $customPath
        }

        Add-UniquePathCandidate -List $candidates -Seen $seen -Path $configRoot
    }

    return $candidates
}

function Resolve-Ez2LazerDataPath {
    $candidates = Get-Ez2LazerDataPathCandidates

    foreach ($candidate in $candidates) {
        if (Test-Ez2LazerDataDirectory $candidate) {
            return $candidate
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return [Environment]::GetFolderPath('Desktop')
}

function Open-OutputFolder {
    param([string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return
    }

    Start-Process explorer.exe -ArgumentList ("/select,`"$FilePath`"")
}

function New-RandomUrlSafeString {
    param([int]$ByteCount = 32)
    $bytes = New-Object byte[] $ByteCount
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-Sha256Base64Url {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    [Convert]::ToBase64String($hash).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-PixivOAuthLoginExe {
    $candidates = @(
        (Join-Path $PSScriptRoot 'PixivOAuthLogin.exe'),
        (Join-Path $PSScriptRoot 'bin/Release/net8.0-windows/PixivOAuthLogin.exe'),
        (Join-Path $PSScriptRoot 'bin/Release/net8.0-windows/win-x64/PixivOAuthLogin.exe')
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }

    $projectFile = Join-Path $PSScriptRoot 'PixivOAuthLogin.csproj'
    if (-not (Test-Path -LiteralPath $projectFile)) {
        throw 'PixivOAuthLogin.exe not found. Download the full zip from GitHub Releases, or install .NET 8 SDK and retry.'
    }

    Write-Host 'First run: building login helper...' -ForegroundColor Cyan
    & dotnet build $projectFile -c Release --nologo -v q
    if ($LASTEXITCODE -ne 0) {
        throw 'Build failed. Download a prebuilt release, or install .NET 8 SDK.'
    }

    $built = Join-Path $PSScriptRoot 'bin/Release/net8.0-windows/PixivOAuthLogin.exe'
    if (-not (Test-Path -LiteralPath $built)) {
        throw "Not found: $built"
    }

    return $built
}

function Invoke-PixivOAuthLogin {
    param(
        [string]$LoginUrl,
        [string]$ProxyUrl
    )

    $exe = Get-PixivOAuthLoginExe
    $codeFile = Join-Path $env:TEMP ("pixiv-oauth-code-{0}.txt" -f [Guid]::NewGuid().ToString('N'))

    try {
        $args = @($LoginUrl, $codeFile)
        if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
            $args += $ProxyUrl
        }

        Write-Host 'Opening login window - complete Pixiv sign-in there...' -ForegroundColor Yellow
        Write-Host '(Uses Pixiv Android client identity; do not use an external browser.)' -ForegroundColor DarkGray

        $process = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru

        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $codeFile)) {
            throw 'Login was not completed or was cancelled.'
        }

        $code = (Get-Content -LiteralPath $codeFile -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($code)) {
            throw 'No authorization code was received.'
        }

        return $code
    }
    finally {
        Remove-Item -LiteralPath $codeFile -ErrorAction SilentlyContinue
    }
}

function Invoke-PixivTokenRequest {
    param([hashtable]$Body)

    $pairs = foreach ($key in $Body.Keys) {
        '{0}={1}' -f [uri]::EscapeDataString($key), [uri]::EscapeDataString([string]$Body[$key])
    }
    $payload = $pairs -join '&'

    $params = @{
        Uri         = $tokenUrl
        Method      = 'Post'
        ContentType = 'application/x-www-form-urlencoded'
        Headers     = @{
            'User-Agent' = $userAgent
        }
        Body        = $payload
    }

    if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
        $params.Proxy = $ProxyUrl
    }

    try {
        return Invoke-RestMethod @params
    }
    catch {
        $responseBody = $null
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
        }

        if ($responseBody) {
            throw "Pixiv token exchange failed: $responseBody"
        }

        throw
    }
}

function Show-RefreshTokenResult {
    param(
        [string]$AuthFilePath,
        [string]$AccountName,
        [bool]$UsingDesktopFallback
    )

    Write-Host ''
    Write-Host 'Wrote pixiv_auth.json (Ez2Lazer can use it directly).' -ForegroundColor Green
    Write-Host "File: $AuthFilePath" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '[Security] pixiv_auth.json is equivalent to your account credentials. Do not share it or upload to cloud drives or chat groups.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Next: restart Ez2Lazer, select Pixiv menu background, then click Check login.' -ForegroundColor Yellow
    if ($UsingDesktopFallback) {
        Write-Host '(Ez2Lazer data folder not found; file is on Desktop - move it next to client.realm)' -ForegroundColor DarkYellow
    }
    Write-Host ''
    Write-Host 'Opening the folder containing the file...' -ForegroundColor Cyan
    Open-OutputFolder -FilePath $AuthFilePath

    $message = @(
        'Wrote pixiv_auth.json. Ez2Lazer can use it directly.'
        ''
        '[Do not share pixiv_auth.json with anyone]'
        ''
        "File:`n$AuthFilePath"
        ''
        'Opened the folder containing this file.'
    ) -join "`n"

    if ($AccountName) {
        $message = "Signed in as @$AccountName`n`n$message"
    }

    if ($UsingDesktopFallback) {
        $message += "`n`nEz2Lazer data folder not found; file is on Desktop. Move it next to client.realm."
    }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($message, 'EzPixivAuth', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

Write-Host 'EzPixivAuth' -ForegroundColor Cyan

$usingDesktopFallback = $false
if ([string]::IsNullOrWhiteSpace($DataPath)) {
    $DataPath = Resolve-Ez2LazerDataPath
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $usingDesktopFallback = ($DataPath -eq $desktopPath)
}

Write-Host "Ez2Lazer output folder: $DataPath"
if ($usingDesktopFallback) {
    Write-Host '(Ez2Lazer data folder not detected; using Desktop)' -ForegroundColor DarkYellow
}
Write-Host ''

if (-not (Test-Path -LiteralPath $DataPath)) {
    New-Item -ItemType Directory -Path $DataPath | Out-Null
    Write-Host "Created directory: $DataPath"
}

$codeVerifier = New-RandomUrlSafeString
$codeChallenge = Get-Sha256Base64Url -Text $codeVerifier
$loginUrl = 'https://app-api.pixiv.net/web/v1/login?code_challenge={0}&code_challenge_method=S256&client=pixiv-android' -f $codeChallenge

$code = Invoke-PixivOAuthLogin -LoginUrl $loginUrl -ProxyUrl $ProxyUrl

Write-Host ''
Write-Host 'Exchanging authorization code for refresh_token...' -ForegroundColor Yellow

$response = Invoke-PixivTokenRequest -Body @{
    client_id      = $clientId
    client_secret  = $clientSecret
    grant_type     = 'authorization_code'
    code           = $code
    code_verifier  = $codeVerifier
    redirect_uri   = $redirectUri
    include_policy = 'true'
}

if (-not $response.refresh_token) {
    throw "Token response did not include refresh_token.`n$($response | ConvertTo-Json -Depth 4)"
}

$authFile = Join-Path $DataPath 'pixiv_auth.json'
$authPayload = @{ refresh_token = $response.refresh_token }
if ($response.user -and $response.user.account) {
    $authPayload.account = $response.user.account
}

$json = $authPayload | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($authFile, $json, $utf8NoBom)

$account = $null
if ($response.user) {
    $account = $response.user.account
}

Show-RefreshTokenResult -AuthFilePath $authFile -AccountName $account -UsingDesktopFallback $usingDesktopFallback
