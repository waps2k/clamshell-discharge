// 트레이 아이콘을 누르면 뜨는 메인 화면 (macOS 판 팝오버와 같은 2열 구성)

using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace ClamshellDischarge;

public enum ChargeState { Charging, Limited, OnBattery, Full, PluggedIdle }

public static class StateText
{
    public static ChargeState Of(Engine e)
    {
        var b = e.Snapshot;
        if (!b.PowerOnline) return ChargeState.OnBattery;
        if (b.Charging) return ChargeState.Charging;
        if (e.AppliedLimit is int l && b.Percent >= l - AppSettings.Shared.Band - 1) return ChargeState.Limited;
        if (b.Percent >= 99) return ChargeState.Full;
        return ChargeState.PluggedIdle;
    }

    public static string Label(ChargeState s, Engine e) => s switch
    {
        ChargeState.Charging => L10n.Tr("충전 중"),
        ChargeState.Limited => L10n.Tr("충전 중지 상태") + (e.AppliedLimit is int l ? " · " + L10n.Tr("한도 %@%", l) : ""),
        ChargeState.OnBattery => L10n.Tr("배터리 사용 중"),
        ChargeState.Full => L10n.Tr("충전 완료"),
        _ => L10n.Tr("전원 연결됨 · 충전 대기"),
    };

    public static Brush Color(ChargeState s) => s switch
    {
        ChargeState.Charging or ChargeState.Full => Theme.Green,
        ChargeState.Limited => Theme.Blue,
        ChargeState.PluggedIdle => Theme.Teal,
        _ => Theme.Secondary,
    };

    public static string Glyph(ChargeState s) => s switch
    {
        ChargeState.Charging => "⚡",
        ChargeState.Limited => "⛵",
        ChargeState.Full => "✓",
        ChargeState.PluggedIdle => "🔌",
        _ => "",
    };

    public static string Minutes(int m) => m >= 60 ? L10n.Tr("%@시간 %@분", m / 60, m % 60) : L10n.Tr("%@분", m);
}

public sealed class PopupWindow : Window
{
    const double Col = 300;
    readonly DispatcherTimer live = new() { Interval = TimeSpan.FromSeconds(3) };
    readonly Action openDashboard;
    readonly Action quit;
    Engine E => Engine.Shared;
    AppSettings S => AppSettings.Shared;

    public PopupWindow(Action openDashboard, Action quit)
    {
        this.openDashboard = openDashboard;
        this.quit = quit;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;
        Deactivated += (_, _) => Hide();
        live.Tick += (_, _) => { if (System.Windows.Input.Mouse.Captured == null) { E.RefreshLive(); Rebuild(); } };
        IsVisibleChanged += (_, _) => { if (IsVisible) live.Start(); else live.Stop(); };
        E.Updated += () => Dispatcher.Invoke(() => { if (IsVisible) Rebuild(); });
        AppSettings.Changed += () => Dispatcher.Invoke(() => { if (IsVisible) Rebuild(); });
    }

    public void ShowNearTray()
    {
        E.RefreshLive();
        Rebuild();
        Show();
        UpdateLayout();
        var wa = SystemParameters.WorkArea;
        Left = wa.Right - ActualWidth - 12;
        Top = wa.Bottom - ActualHeight - 12;
        Activate();
    }

    void Rebuild()
    {
        var b = E.Snapshot;
        var st = StateText.Of(E);

        var left = Ui.V(10,
            Header(b, st),
            Ui.Section(L10n.Tr("사용 기록"), Ui.V(6,
                Ui.UsageBars(E.Samples, Col - 12),
                Ui.Spread(Ui.H(10, Ui.Legend(Theme.Green, L10n.Tr("충전")), Ui.Legend(Theme.Blue, L10n.Tr("유지")), Ui.Legend(Theme.WithAlpha(Theme.Green, 0.75), L10n.Tr("배터리"))),
                          Ui.Text(L10n.Tr("최근 4시간"), 11, Theme.Secondary)))),
            Ui.Section(L10n.Tr("세부 사항"), Details(b, st)),
            Ui.Section(L10n.Tr("배터리"), Ui.V(8,
                Ui.CapacityBar(b, Col),
                Stats(b))));
        left.Width = Col;

        var right = Ui.V(10, Ui.Section(L10n.Tr("모드"), Controls()));
        right.Width = Col;

        var cols = Ui.H(16, left, new Border { Width = 1, Background = Theme.Divider }, right);
        cols.Margin = new Thickness(16, 14, 16, 10);

        var root = Ui.V(0, cols, new Border { Height = 1, Background = Theme.Divider }, Footer());
        Content = new Border
        {
            Child = root, Background = Theme.Background, CornerRadius = new CornerRadius(10),
            BorderBrush = Theme.Divider, BorderThickness = new Thickness(1),
        };
    }

    UIElement Header(BatteryInfo b, ChargeState st)
    {
        var pct = Ui.H(2, Ui.Text($"{b.Percent}", 38, null, FontWeights.Bold), Ui.Text("%", 18, Theme.Secondary));
        var top = Ui.H(16, Ui.BatteryGlyph(b.Percent, StateText.Glyph(st)), pct);
        top.HorizontalAlignment = HorizontalAlignment.Center;
        var badge = new Border
        {
            Background = Theme.WithAlpha(StateText.Color(st), 0.15), CornerRadius = new CornerRadius(12),
            Padding = new Thickness(12, 4, 12, 4), HorizontalAlignment = HorizontalAlignment.Center,
            Child = Ui.Text(StateText.Label(st, E), 13, StateText.Color(st), FontWeights.SemiBold),
        };
        var items = new System.Collections.Generic.List<UIElement> { top, badge };
        if (S.OneShotTarget > 0 && E.Mode != Mode.OneShot && E.OneShotStartAt is DateTime os)
        {
            var tb = Ui.Text(L10n.Tr("지금 충전 예약 · %@부터", L10n.Time(os)), 11.5, Theme.Secondary); tb.HorizontalAlignment = HorizontalAlignment.Center;
            items.Add(tb);
        }
        else if (E.Target is int t)
        {
            var sub = E.Mode switch
            {
                Mode.Departure => L10n.Tr("퇴근 충전 · 목표 %@%", t),
                Mode.Commute => L10n.Tr("출근 충전 · 목표 %@%", t),
                Mode.Weekend => L10n.Tr("주말 외출 충전 · 목표 %@%", t),
                Mode.OneShot => L10n.Tr("지금 충전 · 목표 %@%", t),
                _ => L10n.Tr("유지 %@%", t),
            };
            var tb = Ui.Text(sub, 11.5, Theme.Secondary); tb.HorizontalAlignment = HorizontalAlignment.Center;
            items.Add(tb);
        }
        return Ui.V(8, items.ToArray());
    }

    UIElement Details(BatteryInfo b, ChargeState st)
    {
        var rows = new System.Collections.Generic.List<UIElement>
        {
            Ui.Row(L10n.Tr("공급원"), b.PowerOnline ? L10n.Tr("전원 연결") : L10n.Tr("배터리 전원")),
        };
        if (st == ChargeState.Charging)
        {
            rows.Add(Ui.Row(L10n.Tr("완충까지"), b.MinutesToFull is int m ? StateText.Minutes(m) : L10n.Tr("계산 중")));
            if (E.Target is int t && t < 100 && b.MinutesTo(t) is int mt) rows.Add(Ui.Row(L10n.Tr("%@%까지", t), StateText.Minutes(mt)));
        }
        else if (st == ChargeState.OnBattery)
            rows.Add(Ui.Row(L10n.Tr("남은 사용 시간"), b.MinutesRemaining is int m ? StateText.Minutes(m) : L10n.Tr("계산 중")));
        else rows.Add(Ui.Row(L10n.Tr("충전"), L10n.Tr("대기")));
        // 가장 가까운 일정 하나만
        if (E.NextTimes.Count > 0)
        {
            var (k, t0) = E.NextTimes.OrderBy(x => x.Value).Select(x => (x.Key, x.Value)).First();
            rows.Add(Ui.Row(k.NextLabel(), $"{L10n.WeekdayTime(t0)} · {S.Schedule(k).Target}%"));
        }
        return Ui.V(5, rows.ToArray());
    }

    UIElement Stats(BatteryInfo b)
    {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        var l = Ui.V(5, Ui.Row(L10n.Tr("배터리"), $"{b.BatteryWatts:+0.0;-0.0;0.0} W"), Ui.Row(L10n.Tr("사이클"), $"{b.Cycles}"));
        var r = Ui.V(5, Ui.Row(L10n.Tr("전압"), $"{b.VoltageMV / 1000.0:F2} V"), Ui.Row("SOH", $"{b.Soh:F1}%", b.Soh >= 80 ? null : Theme.Orange));
        Grid.SetColumn(l, 0); Grid.SetColumn(r, 2);
        g.Children.Add(l); g.Children.Add(r);
        return Ui.V(5, g, Ui.Row(L10n.Tr("충전 제어"), E.Controller.Name));
    }

    UIElement Controls()
    {
        var c = E.Controller;
        var items = new System.Collections.Generic.List<UIElement>();
        bool can = c.Kind != ControlKind.None;

        // 충전 유지
        string levelText = c.Kind == ControlKind.Conservation ? $"~{c.FixedLevel}%" : $"{S.MaintainLevel}%";
        items.Add(Ui.ToggleRow(L10n.Tr("충전 유지"), levelText, S.MaintainEnabled, on => S.Update(s => s.MaintainEnabled = on), can));
        if (S.MaintainEnabled && c.Kind == ControlKind.Threshold)
        {
            var slider = Ui.Slider(S.MaintainLevel, 60, 100, 5, v => S.Update(s => s.MaintainLevel = v));
            var row = S.MaintainLevel != 60 ? (UIElement)Ui.Spread(slider, Ui.Chip(L10n.Tr("추천 60"), false, () => S.Update(s => s.MaintainLevel = 60))) : slider;
            items.Add(row);
        }
        else if (S.MaintainEnabled && c.Kind == ControlKind.Conservation)
            items.Add(Ui.Text(L10n.Tr("이 기기는 정해진 수준(약 %@%)으로만 유지할 수 있습니다.", c.FixedLevel), 11.5, Theme.Secondary));

        // 일정 충전 (출근·퇴근): 켜진 일정의 줄을 누르면 편집 칸 펼치기/접기
        foreach (var k in ScheduleKindText.All)
        {
            var v = S.Schedule(k);
            var label = Ui.Text(k.Title() + (v.Enabled ? (expanded == k ? "  ▴" : "  ▾") : ""), 14);
            label.Cursor = v.Enabled ? System.Windows.Input.Cursors.Hand : null;
            label.MouseLeftButtonUp += (_, _) => { if (v.Enabled) { expanded = expanded == k ? null : k; Rebuild(); } };
            items.Add(Ui.Spread(label, Ui.H(10, Ui.Text($"{v.TimeText} · {v.Target}%", 13, Theme.Secondary),
                Ui.Switch(v.Enabled, on => { if (on) expanded = k; S.UpdateSchedule(k, x => x with { Enabled = on }); }, can))));
            if (v.Enabled && expanded == k) items.Add(ScheduleEditor(k));
        }

        // 지금 충전 (출장·외출)
        if (can) items.Add(OneShotRow());

        // 덮개 닫힘
        items.Add(Ui.ToggleRow(L10n.Tr("덮개 닫아도 동작 (전원 연결 시)"), "", S.LidStayAwake, on => { S.Update(s => s.LidStayAwake = on); E.Reapply(); }));

        if (!can) items.Add(Ui.Text(L10n.Tr("충전 제어") + ": " + c.Name, 11.5, Theme.Orange));
        if (!string.IsNullOrEmpty(E.LastError)) items.Add(Ui.Text(E.LastError, 11, Theme.Orange));

        var dash = Ui.Button(L10n.Tr("대시보드"), openDashboard);
        dash.HorizontalAlignment = HorizontalAlignment.Right;
        items.Add(dash);
        return Ui.V(10, items.ToArray());
    }

    ScheduleKind? expanded;
    double departIn;   // 지금 충전: 출발까지 시간 (0 = 바로)

    UIElement ScheduleEditor(ScheduleKind k)
    {
        var v = S.Schedule(k);
        void Set(Func<ScheduleValues, ScheduleValues> f) => S.UpdateSchedule(k, f);

        var presetTimes = k.Presets();
        var presets = new ContextMenu();
        foreach (var m in presetTimes)
        {
            var mi = new MenuItem { Header = $"{m / 60:00}:{m % 60:00}" };
            mi.Click += (_, _) => Set(x => x with { Minutes = m });
            presets.Items.Add(mi);
        }
        var timeLabel = Ui.WithMenu(Ui.ChipNoAction(v.TimeText), presets);

        var leadMenu = new ContextMenu();
        foreach (var m in new[] { 30, 60, 90, 120, 180 })
        {
            var mi = new MenuItem { Header = L10n.Tr("%@분 전부터 충전", m) };
            mi.Click += (_, _) => Set(x => x with { Lead = m });
            leadMenu.Items.Add(mi);
        }
        var lead = Ui.WithMenu(Ui.ChipNoAction(L10n.Tr("%@분 전 시작", v.Lead) + " ▾"), leadMenu);

        UIElement Label(string t) { var x = Ui.Text(t, 13, Theme.Secondary); x.Width = 46; return x; }

        var timeRow = Ui.Spread(Ui.H(8, Label(k.Short()),
                Ui.CircleButton("−", () => Set(x => x with { Minutes = (x.Minutes - 15 + 1440) % 1440 })), timeLabel,
                Ui.CircleButton("+", () => Set(x => x with { Minutes = (x.Minutes + 15) % 1440 }))), lead);

        var targetRow = Ui.Spread(Ui.H(6, Label(L10n.Tr("목표")),
                Ui.Chip("80%", v.Target == 80, () => Set(x => x with { Target = 80 })),
                Ui.Chip("90%", v.Target == 90, () => Set(x => x with { Target = 90 })),
                Ui.Chip("100%", v.Target == 100, () => Set(x => x with { Target = 100 }))),
            Ui.Text($"{v.Target}%", 15, null, FontWeights.SemiBold));

        var slider = Ui.Slider(v.Target, 60, 100, 5, t => Set(x => x with { Target = t }));
        slider.Margin = new Thickness(52, 0, 0, 0);

        var days = new[] { (1, "월"), (2, "화"), (3, "수"), (4, "목"), (5, "금"), (6, "토"), (0, "일") };
        var dayRow = Ui.H(4, new UIElement[] { Label(L10n.Tr("요일")) }.Concat(days.Select(d =>
            (UIElement)Ui.Chip(L10n.Tr(d.Item2), v.Weekdays.Contains(d.Item1), () => Set(x =>
            {
                var w = new System.Collections.Generic.List<int>(x.Weekdays);
                if (!w.Remove(d.Item1)) w.Add(d.Item1);
                return x with { Weekdays = w };
            }), true))).ToArray());

        UIElement summary = E.NextTime(k, DateTime.Now) is DateTime t0
            ? Ui.Text("🕓 " + L10n.Tr("%@부터 충전 → %@까지 %@%", L10n.Time(t0.AddMinutes(-v.Lead)), L10n.WeekdayTime(t0), v.Target), 11.5, Theme.Secondary)
            : Ui.Text(L10n.Tr("요일을 하나 이상 선택하세요"), 11.5, Theme.Orange);

        return Ui.Card(Ui.V(9, timeRow, targetRow, slider, dayRow, summary));
    }

    UIElement OneShotRow()
    {
        int t = S.OneShotTarget;
        var head = Ui.Spread(Ui.Text("🧳 " + L10n.Tr("지금 충전 (출장·외출)"), 14),
            Ui.H(6,
                Ui.Chip("80%", t == 80, () => { if (t == 80) S.CancelOneShot(); else S.StartOneShot(80, departIn); }),
                Ui.Chip("100%", t == 100, () => { if (t == 100) S.CancelOneShot(); else S.StartOneShot(100, departIn); })));

        // 출발 시각: 늦게 나가면 그 시각에 맞춰 늦게 충전 (높은 %로 오래 머물지 않게)
        double shown = t <= 0 ? departIn : S.OneShotDepartAt is DateTime d0 ? Math.Clamp(Math.Round((d0 - DateTime.Now).TotalHours), 1, 3) : 0;
        var departRow = Ui.H(5, new UIElement[] { Ui.Text(L10n.Tr("출발"), 12, Theme.Secondary) }
            .Concat(new[] { 0.0, 1, 2, 3 }.Select(h => (UIElement)Ui.Chip(h == 0 ? L10n.Tr("지금") : L10n.Tr("%@시간 후", (int)h), shown == h, () =>
            {
                departIn = h;
                if (S.OneShotTarget > 0) S.SetOneShotDeparture(h); else Rebuild();
            }, true))).ToArray());
        if (t <= 0) return Ui.V(6, head, departRow);
        var b = E.Snapshot;
        string status = S.OneShotDepartAt is DateTime dep && E.OneShotStartAt is DateTime st && E.Mode != Mode.OneShot && b.Percent < t - 1
            ? L10n.Tr("%@ 출발 · %@부터 충전", L10n.Time(dep), L10n.Time(st))
            : b.Percent >= t - 1 ? L10n.Tr("충전 완료")
            : b.MinutesTo(t) is int m ? L10n.Tr("%@%까지", t) + " " + StateText.Minutes(m) : L10n.Tr("목표 %@%", t);
        return Ui.V(6, head, departRow,
            Ui.Spread(Ui.Text(status, 12, b.Percent >= t - 1 ? Theme.Green : Theme.Secondary), Ui.Chip(L10n.Tr("해제"), false, () => S.CancelOneShot())),
            Ui.Text(L10n.Tr("목표에 도달한 뒤 어댑터를 뽑으면 자동으로 해제됩니다 (최대 24시간)"), 11, Theme.Secondary));
    }

    UIElement Footer()
    {
        var langMenu = new ContextMenu();
        foreach (var (code, name) in L10n.Languages)
        {
            var mi = new MenuItem { Header = code == "system" ? L10n.Tr("시스템 설정 따름") : name, IsChecked = S.Language == code };
            mi.Click += (_, _) => { S.Update(s => s.Language = code); };
            langMenu.Items.Add(mi);
        }
        var lang = Ui.WithMenu(Ui.ButtonNoAction("🌐 " + L10n.Tr("언어")), langMenu);

        var login = Ui.H(6, Ui.Switch(AutoStart.Enabled, on => { AutoStart.Set(on); Rebuild(); }), Ui.Text(L10n.Tr("로그인 시 자동 실행"), 12, Theme.Secondary));
        var diag = Ui.Button(L10n.Tr("진단 정보 복사"), () =>
        {
            try { Clipboard.SetText(E.Diagnostics()); MessageBox.Show(L10n.Tr("진단 정보를 클립보드에 복사했습니다."), "Clamshell Discharge"); } catch { }
        });
        var ver = Ui.Text("v" + (typeof(PopupWindow).Assembly.GetName().Version?.ToString(3) ?? ""), 11, Theme.Secondary);
        var donate = Ui.Button("☕ " + L10n.Tr("후원하기"), Program.OpenDonate);
        var bar = Ui.Spread(Ui.H(10, lang, login), Ui.H(10, ver, donate, diag, Ui.Button(L10n.Tr("종료"), quit)));
        bar.Margin = new Thickness(16, 8, 16, 8);
        return bar;
    }
}
