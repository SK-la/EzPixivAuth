#Requires -Version 5.1
<#
.SYNOPSIS
    EzPixivAuth — one-time Pixiv OAuth helper for Ez2Lazer.

.DESCRIPTION
    Double-click GetPixivRefreshToken.bat. A WebView2 window opens (Pixiv Android user-agent).
    After login, shows your refresh_token and writes a template JSON file. Paste the token
    into Ez2Lazer settings, or rename the template to pixiv_auth.json.

.PARAMETER DataPath
    osu data directory. Defaults to %AppData%/osu.

.EXAMPLE
    Double-click GetPixivRefreshToken.bat
#>
[CmdletBinding()]
param(
    [string]$DataPath = (Join-Path $env:APPDATA 'osu'),
    [string]$ProxyUrl = ''
)

$ErrorActionPreference = 'Stop'

$clientId = 'MOBrBDS8blbauo1uch9Z4AXbbf'
$clientSecret = 'ttIDt8NdJJMxTCWRMTtPArt'
$redirectUri = 'https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback'
$tokenUrl = 'https://oauth.secure.pixiv.net/auth/token'
$userAgent = 'PixivAndroidApp/5.0.234 (Android 11; Pixel 5)'

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
        (Join-Path $PSScriptRoot 'PixivOAuthLogin/bin/Release/net8.0-windows/PixivOAuthLogin.exe')
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }

    $projectDir = Join-Path $PSScriptRoot 'PixivOAuthLogin'
    if (-not (Test-Path -LiteralPath $projectDir)) {
        throw '未找到 PixivOAuthLogin.exe。请从 GitHub Releases 下载完整 zip，或安装 .NET 8 SDK 后重试。'
    }

    Write-Host '首次运行，正在编译登录助手...' -ForegroundColor Cyan
    & dotnet build $projectDir -c Release --nologo -v q
    if ($LASTEXITCODE -ne 0) {
        throw '编译失败。请从 Releases 下载预编译包，或安装 .NET 8 SDK。'
    }

    $built = Join-Path $projectDir 'bin/Release/net8.0-windows/PixivOAuthLogin.exe'
    if (-not (Test-Path -LiteralPath $built)) {
        throw "未找到 $built"
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

        Write-Host '正在打开登录窗口，请在窗口内完成 Pixiv 登录...' -ForegroundColor Yellow
        Write-Host '（使用 Pixiv Android 客户端身份，勿用外部浏览器。）' -ForegroundColor DarkGray

        $process = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru

        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $codeFile)) {
            throw '登录未完成或已取消。'
        }

        $code = (Get-Content -LiteralPath $codeFile -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($code)) {
            throw '未获取到 authorization code。'
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
            'User-Agent'     = $userAgent
            'App-OS'         = 'android'
            'App-OS-Version' = '11'
            'App-Version'    = '5.0.234'
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
        [string]$RefreshToken,
        [string]$TemplatePath,
        [string]$AccountName
    )

    Set-Clipboard -Value $RefreshToken

    Write-Host ''
    Write-Host '======== refresh_token ========' -ForegroundColor Green
    Write-Host $RefreshToken
    Write-Host '===============================' -ForegroundColor Green
    Write-Host ''
    Write-Host "已复制到剪贴板。" -ForegroundColor Cyan
    Write-Host "模板文件: $TemplatePath" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '下一步（任选其一）：' -ForegroundColor Yellow
    Write-Host '  1. 打开 Ez2Lazer → 主菜单背景 → Pixiv → 粘贴 token 并保存'
    Write-Host '  2. 将模板文件重命名为 pixiv_auth.json（放在同一 osu 数据目录）'
    Write-Host ''

    $message = "refresh_token 已复制到剪贴板。`n`n模板：`n$TemplatePath"
    if ($AccountName) {
        $message = "已登录 @$AccountName`n`n$message"
    }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($message, 'EzPixivAuth', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

Write-Host 'EzPixivAuth' -ForegroundColor Cyan
Write-Host "Data path: $DataPath"
Write-Host ''

if (-not (Test-Path -LiteralPath $DataPath)) {
    New-Item -ItemType Directory -Path $DataPath | Out-Null
    Write-Host "Created data directory: $DataPath"
}

$codeVerifier = New-RandomUrlSafeString
$codeChallenge = Get-Sha256Base64Url -Text $codeVerifier
$loginUrl = 'https://app-api.pixiv.net/web/v1/login?code_challenge={0}&code_challenge_method=S256&client=pixiv-android' -f $codeChallenge

$code = Invoke-PixivOAuthLogin -LoginUrl $loginUrl -ProxyUrl $ProxyUrl

Write-Host ''
Write-Host '正在换取 refresh_token...' -ForegroundColor Yellow

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

$templateFile = Join-Path $DataPath 'pixiv_auth.json.template'
$json = @{ refresh_token = $response.refresh_token } | ConvertTo-Json
Set-Content -LiteralPath $templateFile -Value $json -Encoding UTF8

$account = $null
if ($response.user) {
    $account = $response.user.account
}

Show-RefreshTokenResult -RefreshToken $response.refresh_token -TemplatePath $templateFile -AccountName $account
