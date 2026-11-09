// 시작점: 트레이 아이콘, 팝업, 대시보드, 주기 작업

using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace ClamshellDischarge;

public static class Program
{
    static Forms.NotifyIcon? tray;
    static PopupWindow? popup;
    static DashboardWindow? dashboard;
    static Icon? lastIcon;

    [STAThread]
    public static void Main(string[] args)
    {
        // 자체 점검 (CI 용): UI 없이 배터리 읽기·기기 감지·번역·진단을 돌려 파일로 남기고 종료
        int st = Array.IndexOf(args, "--selftest");
        if (st >= 0)
        {
            var path = st + 1 < args.Length ? args[st + 1] : "selftest.txt";
            var e = Engine.Shared;
            e.Start();
            var lines = e.Diagnostics() + Environment.NewLine +
                        $"L10n en: {Lang("en", "목표 %@%", 80)} | ja: {Lang("ja", "%@시간 %@분", 1, 5)} | zh: {Lang("zh-Hans", " · 지금 속도로 %@%까지 약 %@분", 80, 42)}";
            System.IO.File.WriteAllText(path, lines);
            return;
        }

        using var mutex = new Mutex(true, "ClamshellDischarge.SingleInstance", out bool first);
        if (!first) { MessageBox.Show(L10n.Tr("이미 실행 중입니다."), "Clamshell Discharge"); return; }

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var engine = Engine.Shared;
        engine.Start();

        popup = new PopupWindow(OpenDashboard, Quit);
        tray = new Forms.NotifyIcon { Visible = true, Text = "Clamshell Discharge" };
        tray.MouseUp += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left)
            {
                if (popup.IsVisible) popup.Hide(); else popup.ShowNearTray();
            }
        };
        tray.ContextMenuStrip = BuildMenu();
        UpdateTray();

        engine.Updated += () => app.Dispatcher.Invoke(UpdateTray);
        AppSettings.Changed += () => { engine.Reapply(); };

        // 30초마다 제어 로직, 깨어난 뒤에도 바로 한 번
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        timer.Tick += (_, _) => engine.Tick();
        timer.Start();
        Microsoft.Win32.SystemEvents.PowerModeChanged += (_, e) =>
        {
            if (e.Mode != Microsoft.Win32.PowerModes.Suspend) app.Dispatcher.BeginInvoke(() => engine.Reapply());
        };

        if (Array.IndexOf(args, "--show") >= 0) app.Dispatcher.BeginInvoke(() => popup.ShowNearTray());
        app.Run();
    }

    static string Lang(string code, string key, params object[] a)
    {
        var prev = AppSettings.Shared.Language;
        AppSettings.Shared.Language = code;
        var r = L10n.Tr(key, a);
        AppSettings.Shared.Language = prev;
        return r;
    }

    static Forms.ContextMenuStrip BuildMenu()
    {
        var m = new Forms.ContextMenuStrip();
        m.Opening += (_, _) =>
        {
            m.Items.Clear();
            m.Items.Add(L10n.Tr("열기"), null, (_, _) => popup?.ShowNearTray());
            m.Items.Add(L10n.Tr("배터리 대시보드…"), null, (_, _) => OpenDashboard());
            m.Items.Add(new Forms.ToolStripSeparator());
            m.Items.Add(L10n.Tr("종료"), null, (_, _) => Quit());
        };
        m.Items.Add("…");
        return m;
    }

    static void OpenDashboard()
    {
        popup?.Hide();
        if (dashboard == null || !dashboard.IsLoaded) dashboard = new DashboardWindow();
        dashboard.Rebuild();
        dashboard.Show();
        dashboard.Activate();
    }

    static void Quit()
    {
        // 종료할 때 한도를 남겨 두지 않음: 정상 충전으로 되돌리고 덮개 설정 복원
        try
        {
            Engine.Shared.Controller.Apply(null, AppSettings.Shared.Band);
            if (AppSettings.Shared.LidStayAwake && AppSettings.Shared.OriginalLidAc >= 0)
                Lid.Set(AppSettings.Shared.OriginalLidAc, AppSettings.Shared.OriginalLidDc);
        }
        catch { }
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        Application.Current.Shutdown();
    }

    // ── 트레이 아이콘: 배터리 모양 + 숫자, 상태별 색 ──

    static void UpdateTray()
    {
        if (tray == null) return;
        var e = Engine.Shared;
        var st = StateText.Of(e);
        int pct = e.Snapshot.Percent;
        var icon = DrawIcon(pct, st);
        tray.Icon = icon;
        lastIcon?.Dispose();
        lastIcon = icon;
        var tip = $"{pct}% · {StateText.Label(st, e)}";
        tray.Text = tip.Length > 63 ? tip[..63] : tip;
    }

    static Icon DrawIcon(int pct, ChargeState st)
    {
        int size = 32;
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            var color = st switch
            {
                ChargeState.Charging or ChargeState.Full => Color.FromArgb(52, 199, 89),
                ChargeState.Limited => Color.FromArgb(10, 132, 255),
                ChargeState.PluggedIdle => Color.FromArgb(48, 176, 199),
                _ => pct <= 20 ? Color.FromArgb(255, 149, 0) : Color.White,
            };
            using var outline = new Pen(Color.White, 2);
            g.DrawRectangle(outline, 1, 6, 26, 20);
            g.FillRectangle(Brushes.White, 28, 12, 3, 8);
            int w = Math.Max(2, (int)(22 * pct / 100.0));
            using (var fill = new SolidBrush(Color.FromArgb(110, color))) g.FillRectangle(fill, 3, 8, w, 16);
            string text = pct >= 100 ? "F" : pct.ToString();
            using var font = new Font("Segoe UI", text.Length > 1 ? 13 : 15, System.Drawing.FontStyle.Bold, GraphicsUnit.Pixel);
            var sz = g.MeasureString(text, font);
            using var tb = new SolidBrush(Color.White);
            g.DrawString(text, font, tb, (28 - sz.Width) / 2 + 1, (32 - sz.Height) / 2);
        }
        var h = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(h).Clone();
        DestroyIcon(h);
        return icon;
    }

    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);
}

/// <summary>로그인 시 자동 실행: 작업 스케줄러 (관리자 권한으로 실행되도록 '가장 높은 수준의 권한')</summary>
public static class AutoStart
{
    const string TaskName = "ClamshellDischarge";

    public static bool Enabled => Run("/query /tn " + TaskName) == 0;

    public static void Set(bool on)
    {
        if (on)
        {
            var exe = Environment.ProcessPath ?? "";
            Run($"/create /tn {TaskName} /tr \"\\\"{exe}\\\"\" /sc onlogon /rl highest /f");
        }
        else Run($"/delete /tn {TaskName} /f");
    }

    static int Run(string args)
    {
        try
        {
            var p = Process.Start(new ProcessStartInfo("schtasks.exe", args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
            if (p == null) return -1;
            p.WaitForExit(5000);
            return p.ExitCode;
        }
        catch { return -1; }
    }
}
