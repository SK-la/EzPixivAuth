# EzPixivAuth

Easy create PIXIV `refresh_token` for [Ez2Lazer](https://github.com/SK-la/osu) menu background (Pixiv follow feed).

Source code is fully open so you can audit OAuth handling before logging in.

## Requirements

- Windows 10 / 11
- [.NET 8 Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) (same as Ez2Lazer)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) (usually pre-installed with Edge)

## Usage (low-code)

1. Download **EzPixivAuth-win-x64.zip** from [Releases](https://github.com/SK-la/EzPixivAuth/releases).
2. Extract anywhere.
3. **Double-click `GetPixivRefreshToken.bat`** (no command line needed).
4. Log in inside the WebView2 window.
5. Copy the shown `refresh_token` (also copied to clipboard). A `pixiv_auth.json.template` is saved to your **Ez2Lazer data folder** (`%AppData%\osu-Ez2Lazer`, or the custom path in its `storage.ini`, or the portable install folder if Ez2osu! is running) — same directory as `client.realm`. Falls back to **Desktop** if not found.
6. Explorer opens that folder automatically. **Do not share** the token or JSON with anyone.

Then in Ez2Lazer:
   - **Main menu → Settings → Background → Pixiv** — paste and **Save**, or
   - Rename the template to `pixiv_auth.json` in your osu data folder.

The tool does **not** overwrite your existing `pixiv_auth.json` automatically.

## Troubleshooting

- **Passkey / 通行密钥不可用**：请改用 **邮箱 + 密码** 登录（嵌入式 WebView 不支持通行密钥）。
- **错误 918 / invalid OAuth client**：请使用最新 [Release](https://github.com/SK-la/EzPixivAuth/releases)；旧版 `client_id` 会被 Pixiv 拒绝。
- **登录后换 token 失败**：`code` 有效期很短，请关闭登录窗后尽快完成；若在国内网络环境异常，可配置系统代理后重试。

## Build from source (developers)

```powershell
dotnet build PixivOAuthLogin -c Release
```

Then double-click `GetPixivRefreshToken.bat` in this folder.

## How it works

- PKCE OAuth against Pixiv Android client endpoints (same public `client_id` as Ez2Lazer).
- `PixivOAuthLogin.exe` opens WebView2 with Android User-Agent and captures the authorization `code`.
- PowerShell exchanges the code for `refresh_token` and shows the result.

## License

MIT
