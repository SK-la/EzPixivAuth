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
5. Copy the shown `refresh_token` (also copied to clipboard), then in Ez2Lazer:
   - **Main menu → Settings → Background → Pixiv** — paste and **Save**, or
   - Rename `%AppData%\osu\pixiv_auth.json.template` to `pixiv_auth.json`.

The tool does **not** overwrite your existing `pixiv_auth.json` automatically.

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
