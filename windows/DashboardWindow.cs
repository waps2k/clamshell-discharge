// 대시보드: 상태 카드, 용량 막대, 충전량 그래프, 일별 SOH 그래프

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace ClamshellDischarge;

public sealed class DashboardWindow : Window
{
    const double W = 680;
    int rangeHours = 24;
    Engine E => Engine.Shared;

    public DashboardWindow()
    {
        Title = L10n.Tr("Clamshell Discharge — 배터리 대시보드");
        Width = W + 60; Height = 820;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Theme.Background;
        E.Updated += () => Dispatcher.Invoke(() => { if (IsVisible) Rebuild(); });
        AppSettings.Changed += () => Dispatcher.Invoke(() => { if (IsVisible) Rebuild(); });
        Rebuild();
    }

    public void Rebuild()
    {
        Title = L10n.Tr("Clamshell Discharge — 배터리 대시보드");
        Background = Theme.Background;
        var b = E.Snapshot;
        var root = Ui.V(14,
            Cards(b),
            Ui.Card(Ui.CapacityBar(b, W - 24), 12),
            Ui.Card(ChargeChart(), 12),
            Ui.Card(SohChart(), 12));
        root.Margin = new Thickness(24);
        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    UIElement Cards(BatteryInfo b)
    {
        UIElement Card(string title, string value, string sub, Brush? tint = null)
        {
            var v = Ui.V(3, Ui.Text(title, 11.5, Theme.Secondary), Ui.Text(value, 22, tint, FontWeights.SemiBold), Ui.Text(sub, 11, Theme.Secondary));
            var c = Ui.Card(v, 12); c.Width = (W - 36) / 4; return c;
        }
        var st = StateText.Of(E);
        string modeText = E.Mode switch
        {
            Mode.Maintain => L10n.Tr("유지 모드"),
            Mode.Departure => L10n.Tr("퇴근 충전"),
            Mode.Unavailable => L10n.Tr("지원 안 됨 (모니터링만)"),
            _ => L10n.Tr("일반 충전"),
        };
        int cyclePct = b.Cycles * 100 / 1000;
        return Ui.H(12,
            Card(L10n.Tr("충전량"), $"{b.Percent}%", StateText.Label(st, E)),
            Card(L10n.Tr("배터리 성능 (SOH)"), $"{b.Soh:F1}%", $"{b.FullMWh:N0} / {b.DesignMWh:N0} mWh", b.Soh >= 85 ? Theme.Green : b.Soh >= 80 ? Theme.Orange : Theme.Red),
            Card(L10n.Tr("사이클"), $"{b.Cycles}", L10n.Tr("설계 %@회 기준 %@%", 1000, cyclePct)),
            Card(L10n.Tr("상태"), modeText, E.Target is int t ? L10n.Tr("목표 %@%", t) : E.Controller.Name));
    }

    UIElement ChargeChart()
    {
        var ranges = new[] { (6, "6시간"), (24, "24시간"), (24 * 7, "7일"), (24 * 30, "30일") };
        var picker = Ui.H(4, ranges.Select(r => (UIElement)Ui.Chip(L10n.Tr(r.Item2), rangeHours == r.Item1, () => { rangeHours = r.Item1; Rebuild(); })).ToArray());
        var header = Ui.Spread(Ui.Text(L10n.Tr("충전량"), 15, null, FontWeights.SemiBold), picker);

        var from = DateTime.Now.AddHours(-rangeHours);
        var data = E.Samples.Where(s => s.Date >= from).ToList();
        if (data.Count < 2) return Ui.V(8, header, Ui.Text(L10n.Tr("기록이 쌓이는 중입니다 (1분마다 저장)"), 13, Theme.Secondary));

        double cw = W - 70, ch = 200;
        var canvas = new Canvas { Width = cw + 40, Height = ch + 22 };
        // 가로 눈금
        foreach (var y in new[] { 0, 25, 50, 75, 100 })
        {
            double py = ch - ch * y / 100.0;
            var line = new Line { X1 = 0, X2 = cw, Y1 = py, Y2 = py, Stroke = Theme.Divider, StrokeThickness = 1 };
            canvas.Children.Add(line);
            var lbl = Ui.Text($"{y}", 10.5, Theme.Secondary); Canvas.SetLeft(lbl, cw + 6); Canvas.SetTop(lbl, py - 8); canvas.Children.Add(lbl);
        }
        double span = Math.Max(1, (DateTime.Now - from).TotalSeconds);
        double X(DateTime d) => cw * (d - from).TotalSeconds / span;
        double Y(int p) => ch - ch * p / 100.0;

        var pts = new PointCollection(data.Select(s => new Point(X(s.Date), Y(s.Percent))));
        var area = new PointCollection(pts) { new Point(pts[^1].X, ch), new Point(pts[0].X, ch) };
        canvas.Children.Add(new Polygon { Points = area, Fill = new LinearGradientBrush(((SolidColorBrush)Theme.WithAlpha(Theme.Green, 0.35)).Color, ((SolidColorBrush)Theme.WithAlpha(Theme.Green, 0.03)).Color, 90) });
        canvas.Children.Add(new Polyline { Points = pts, Stroke = Theme.Green, StrokeThickness = 2 });

        void Rule(int v, Brush br, string label)
        {
            canvas.Children.Add(new Line { X1 = 0, X2 = cw, Y1 = Y(v), Y2 = Y(v), Stroke = br, StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 4, 3 } });
            var t = Ui.Text(label, 10.5, br); Canvas.SetLeft(t, 2); Canvas.SetTop(t, Y(v) - 16); canvas.Children.Add(t);
        }
        var S = AppSettings.Shared;
        if (S.MaintainEnabled) Rule(E.Controller.Kind == ControlKind.Conservation ? E.Controller.FixedLevel : S.MaintainLevel, Theme.Blue, L10n.Tr("유지 %@%", S.MaintainLevel));
        if (S.DepartureEnabled) Rule(S.DepartureTarget, Theme.Orange, L10n.Tr("퇴근 목표 %@%", S.DepartureTarget));

        // 시간 축 라벨 (시작, 중간, 끝)
        foreach (var frac in new[] { 0.0, 0.5, 1.0 })
        {
            var d = from.AddSeconds(span * frac);
            var lbl = Ui.Text(rangeHours <= 24 ? L10n.Time(d) : d.ToString("M/d", L10n.Culture), 10.5, Theme.Secondary);
            Canvas.SetLeft(lbl, Math.Min(cw - 40, cw * frac)); Canvas.SetTop(lbl, ch + 4); canvas.Children.Add(lbl);
        }
        return Ui.V(10, header, canvas);
    }

    UIElement SohChart()
    {
        var header = Ui.Spread(Ui.Text(L10n.Tr("배터리 성능 (SOH)"), 15, null, FontWeights.SemiBold),
            Ui.Text(L10n.Tr("현재 최대 용량 ÷ 설계 용량 · 80% 미만이면 교체 고려"), 11, Theme.Secondary));
        var days = E.Samples.Where(s => s.Soh > 0).GroupBy(s => s.Date.Date)
            .Select(g => (Day: g.Key, Soh: g.Average(x => x.Soh))).OrderBy(x => x.Day).ToList();
        if (days.Count == 0) return Ui.V(8, header, Ui.Text(L10n.Tr("기록이 쌓이는 중입니다"), 13, Theme.Secondary));

        double cw = W - 70, ch = 140;
        double lo = Math.Max(0, Math.Min(70, days.Min(d => d.Soh) - 5));
        double Y(double v) => ch - ch * (v - lo) / (100 - lo);
        var canvas = new Canvas { Width = cw + 40, Height = ch + 22 };
        foreach (var v in new[] { lo, 80, 100 })
        {
            var line = new Line { X1 = 0, X2 = cw, Y1 = Y(v), Y2 = Y(v), Stroke = v == 80 ? Theme.WithAlpha(Theme.Red, 0.6) : Theme.Divider, StrokeThickness = 1 };
            if (v == 80) line.StrokeDashArray = new DoubleCollection { 3, 3 };
            canvas.Children.Add(line);
            var t = Ui.Text($"{v:0}", 10.5, Theme.Secondary); Canvas.SetLeft(t, cw + 6); Canvas.SetTop(t, Y(v) - 8); canvas.Children.Add(t);
        }
        double X(int i) => days.Count == 1 ? cw / 2 : cw * i / (days.Count - 1);
        if (days.Count > 1)
            canvas.Children.Add(new Polyline { Points = new PointCollection(days.Select((d, i) => new Point(X(i), Y(d.Soh)))), Stroke = Theme.Purple, StrokeThickness = 2 });
        for (int i = 0; i < days.Count; i++)
        {
            var dot = new Ellipse { Width = 8, Height = 8, Fill = Theme.Purple };
            Canvas.SetLeft(dot, X(i) - 4); Canvas.SetTop(dot, Y(days[i].Soh) - 4); canvas.Children.Add(dot);
            if (days.Count <= 14)
            {
                var t = Ui.Text($"{days[i].Soh:F1}", 10, Theme.Secondary); Canvas.SetLeft(t, X(i) - 12); Canvas.SetTop(t, Y(days[i].Soh) - 20); canvas.Children.Add(t);
                var d = Ui.Text(days[i].Day.ToString("M/d", L10n.Culture), 10.5, Theme.Secondary); Canvas.SetLeft(d, Math.Min(cw - 30, Math.Max(0, X(i) - 12))); Canvas.SetTop(d, ch + 4); canvas.Children.Add(d);
            }
        }
        return Ui.V(10, header, canvas);
    }
}
