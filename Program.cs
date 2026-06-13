using System.Text.RegularExpressions;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace PixivOAuthLogin;

internal static class Program
{
    private const string user_agent = "PixivAndroidApp/5.0.234 (Android 11; Pixel 5)";

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length < 2 || string.IsNullOrWhiteSpace(args[0]) || string.IsNullOrWhiteSpace(args[1]))
        {
            MessageBox.Show("Usage: PixivOAuthLogin <loginUrl> <outputCodeFile> [proxyUrl]", "EzPixivAuth", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        string loginUrl = args[0];
        string outputFile = args[1];
        string? proxyUrl = args.Length > 2 ? args[2] : null;

        ApplicationConfiguration.Initialize();

        using var form = new Form();
        form.Text = "EzPixivAuth - Pixiv Login";
        form.Width = 520;
        form.Height = 720;
        form.StartPosition = FormStartPosition.CenterScreen;

        var webView = new WebView2 { Dock = DockStyle.Fill };
        form.Controls.Add(webView);

        var completion = new TaskCompletionSource<string?>();

        form.FormClosing += (_, e) =>
        {
            if (!completion.Task.IsCompleted)
                completion.TrySetResult(null);
        };

        form.Shown += async (_, _) =>
        {
            try
            {
                var envOptions = new CoreWebView2EnvironmentOptions($"--user-agent={user_agent}");

                if (!string.IsNullOrWhiteSpace(proxyUrl))
                    envOptions.AdditionalBrowserArguments += $" --proxy-server={proxyUrl}";

                string userData = Path.Combine(Path.GetTempPath(), "ezpixivauth-oauth-webview2");
                var env = await CoreWebView2Environment.CreateAsync(null, userData, envOptions);
                await webView.EnsureCoreWebView2Async(env);

                webView.CoreWebView2.Settings.UserAgent = user_agent;
                webView.CoreWebView2.NavigationStarting += (_, e) => tryComplete(e.Uri, completion, form);
                webView.CoreWebView2.SourceChanged += (_, _) =>
                {
                    string? uri = webView.Source?.AbsoluteUri;
                    if (uri != null)
                        tryComplete(uri, completion, form);
                };

                webView.Source = new Uri(loginUrl);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    $"WebView2 failed to initialize: {ex.Message}\n\nInstall WebView2 Runtime:\nhttps://developer.microsoft.com/microsoft-edge/webview2/",
                    "EzPixivAuth",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                completion.TrySetResult(null);
                form.Close();
            }
        };

        Application.Run(form);

        string? code = completion.Task.GetAwaiter().GetResult();

        if (string.IsNullOrWhiteSpace(code))
            return 1;

        File.WriteAllText(outputFile, code);
        return 0;
    }

    private static void tryComplete(string uri, TaskCompletionSource<string?> completion, Form form)
    {
        string? code = extractCode(uri);
        if (code == null || completion.Task.IsCompleted)
            return;

        completion.TrySetResult(code);
        form.BeginInvoke(form.Close);
    }

    private static string? extractCode(string uri)
    {
        if (string.IsNullOrWhiteSpace(uri) || uri.Contains("code_challenge", StringComparison.Ordinal))
            return null;

        var pixivMatch = Regex.Match(uri, @"pixiv://[^?\s]*\?[^\s]*code=([^&\s]+)", RegexOptions.IgnoreCase);
        if (pixivMatch.Success)
            return Uri.UnescapeDataString(pixivMatch.Groups[1].Value);

        var callbackMatch = Regex.Match(uri, @"app-api\.pixiv\.net/web/v1/users/auth/pixiv/callback[^\s]*[?&]code=([^&\s]+)", RegexOptions.IgnoreCase);
        if (callbackMatch.Success)
            return Uri.UnescapeDataString(callbackMatch.Groups[1].Value);

        var genericMatch = Regex.Match(uri, @"[?&]code=([A-Za-z0-9_\-]+)(?:&|$)");
        if (genericMatch.Success)
            return Uri.UnescapeDataString(genericMatch.Groups[1].Value);

        return null;
    }
}
