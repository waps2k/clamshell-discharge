// macOS 판과 같은 모양을 WPF 코드로 그리는 작은 부품들 (XAML 없이)

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Microsoft.Win32;

namespace ClamshellDischarge;

public static class Theme
{
    public static bool Dark
    {
        get
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                return (k?.GetValue("AppsUseLightTheme") as int? ?? 1) == 0;
            }
            catch { return false; }
        }
    }

    static SolidColorBrush B(byte r, byte g, byte b, byte a = 255) { var x = new SolidColorBrush(Color.FromArgb(a, r, g, b)); x.Freeze(); return x; }

    public static Brush Background => Dark ? B(32, 32, 32) : B(243, 243, 243);
    public static Brush Card => Dark ? B(44, 44, 44) : B(255, 255, 255);
    public static Brush Fore => Dark ? B(240, 240, 240) : B(26, 26, 26);
    public static Brush Secondary => Dark ? B(160, 160, 160) : B(110, 110, 110);
    public static Brush Faint => Dark ? B(255, 255, 255, 28) : B(0, 0, 0, 20);
    public static Brush Divider => Dark ? B(255, 255, 255, 36) : B(0, 0, 0, 30);
    public static Brush Accent => B(0, 120, 212);
    public static Brush Green => B(52, 199, 89);
    public static Brush Blue => B(10, 132, 255);
    public static Brush Orange => B(255, 149, 0);
    public static Brush Red => B(255, 59, 48);
    public static Brush Teal => B(48, 176, 199);
    public static Brush Purple => B(175, 82, 222);

    public static Brush Level(int pct) => pct <= 10 ? Red : pct <= 20 ? Orange : Green;
    public static Brush WithAlpha(Brush b, double a) { var c = ((SolidColorBrush)b).Color; return B(c.R, c.G, c.B, (byte)(a * 255)); }

    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI, Malgun Gothic, Yu Gothic UI, Microsoft YaHei UI");
}

public static class Ui
{
    public static TextBlock Text(string s, double size = 13, Brush? color = null, FontWeight? weight = null) => new()
    {
        Text = s, FontSize = size, Foreground = color ?? Theme.Fore, FontWeight = weight ?? FontWeights.Normal,
        FontFamily = Theme.Font, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis,
    };

    public static StackPanel V(double spacing, params UIElement[] items) => Stack(Orientation.Vertical, spacing, items);
    public static StackPanel H(double spacing, params UIElement[] items) => Stack(Orientation.Horizontal, spacing, items);

    static StackPanel Stack(Orientation o, double spacing, UIElement[] items)
    {
        var p = new StackPanel { Orientation = o };
        for (int i = 0; i < items.Length; i++)
        {
            if (items[i] is FrameworkElement fe && i > 0)
                fe.Margin = o == Orientation.Vertical ? new Thickness(fe.Margin.Left, spacing, fe.Margin.Right, fe.Margin.Bottom)
                                                       : new Thickness(spacing, fe.Margin.Top, fe.Margin.Right, fe.Margin.Bottom);
            p.Children.Add(items[i]);
        }
        return p;
    }

    /// <summary>왼쪽 요소 + 오른쪽 요소 (사이 공간 채움)</summary>
    public static Grid Spread(UIElement left, UIElement right)
    {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(left, 0); Grid.SetColumn(right, 1);
        g.Children.Add(left); g.Children.Add(right);
        return g;
    }

    public static Grid Row(string k, string v, Brush? tint = null) =>
        Spread(Text(k, 13, Theme.Secondary), Text(v, 13, tint));

    /// <summary>─── 제목 ─── 구분선 + 내용</summary>
    public static StackPanel Section(string title, UIElement content)
    {
        var line = new Grid { Margin = new Thickness(0, 4, 0, 6) };
        line.ColumnDefinitions.Add(new ColumnDefinition());
        line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        line.ColumnDefinitions.Add(new ColumnDefinition());
        var l = new Rectangle { Height = 1, Fill = Theme.Divider, VerticalAlignment = VerticalAlignment.Center };
        var r = new Rectangle { Height = 1, Fill = Theme.Divider, VerticalAlignment = VerticalAlignment.Center };
        var t = Text(title, 11.5, Theme.Secondary); t.Margin = new Thickness(8, 0, 8, 0);
        Grid.SetColumn(l, 0); Grid.SetColumn(t, 1); Grid.SetColumn(r, 2);
        line.Children.Add(l); line.Children.Add(t); line.Children.Add(r);
        return V(0, line, content);
    }

    public static Border Card(UIElement child, double pad = 10) => new()
    {
        Child = child, Background = Theme.Faint, CornerRadius = new CornerRadius(8), Padding = new Thickness(pad),
    };

    static Border Clickable(Border b, Action onClick)
    {
        b.Cursor = Cursors.Hand;
        b.MouseLeftButtonUp += (_, e) => { onClick(); e.Handled = true; };
        return b;
    }

    /// <summary>켜짐이 항상 강조색으로 보이는 스위치</summary>
    public static Border Switch(bool on, Action<bool> changed, bool enabled = true)
    {
        var knob = new Ellipse { Width = 16, Height = 16, Fill = Brushes.White, HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left, Margin = new Thickness(2) };
        var b = new Border
        {
            Width = 36, Height = 20, CornerRadius = new CornerRadius(10), Child = knob,
            Background = on ? Theme.Accent : Theme.WithAlpha(Theme.Secondary, 0.35), Opacity = enabled ? 1 : 0.45,
        };
        return enabled ? Clickable(b, () => changed(!on)) : b;
    }

    /// <summary>라벨 + 오른쪽 보조 문구 + 스위치</summary>
    public static Grid ToggleRow(string label, string sub, bool on, Action<bool> changed, bool enabled = true)
    {
        var right = H(10, Text(sub, 13, Theme.Secondary), Switch(on, changed, enabled));
        return Spread(Text(label, 14), right);
    }

    /// <summary>누르면 메뉴가 열리는 칩/버튼 (클릭 처리기를 따로 달면 Handled 때문에 실행되지 않으므로 여기서 한 번에)</summary>
    public static Border WithMenu(Border b, ContextMenu menu)
    {
        b.ContextMenu = menu;
        b.Cursor = Cursors.Hand;
        b.MouseLeftButtonUp += (_, e) => { menu.PlacementTarget = b; menu.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom; menu.IsOpen = true; e.Handled = true; };
        return b;
    }

    public static Border ChipNoAction(string title, bool selected = false, bool compact = false) => new()
    {
        Background = selected ? Theme.Accent : Theme.WithAlpha(Theme.Secondary, 0.2),
        CornerRadius = new CornerRadius(11), Padding = new Thickness(compact ? 7 : 11, 3, compact ? 7 : 11, 3),
        MinWidth = compact ? 26 : 44,
        Child = new TextBlock
        {
            Text = title, FontSize = 12, FontFamily = Theme.Font, HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = selected ? Brushes.White : Theme.Fore, FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal,
        },
    };

    public static Border ButtonNoAction(string title) => new()
    {
        Background = Theme.WithAlpha(Theme.Secondary, 0.2), CornerRadius = new CornerRadius(6), Padding = new Thickness(12, 5, 12, 5),
        Child = Text(title, 13),
    };

    public static Border Chip(string title, bool selected, Action onClick, bool compact = false) => Clickable(new Border
    {
        Background = selected ? Theme.Accent : Theme.WithAlpha(Theme.Secondary, 0.2),
        CornerRadius = new CornerRadius(11), Padding = new Thickness(compact ? 7 : 11, 3, compact ? 7 : 11, 3),
        MinWidth = compact ? 26 : 44,
        Child = new TextBlock
        {
            Text = title, FontSize = 12, FontFamily = Theme.Font, HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = selected ? Brushes.White : Theme.Fore, FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal,
        },
    }, onClick);

    public static Border CircleButton(string glyph, Action onClick) => Clickable(new Border
    {
        Width = 22, Height = 22, CornerRadius = new CornerRadius(11), Background = Theme.WithAlpha(Theme.Secondary, 0.2),
        Child = new TextBlock { Text = glyph, FontSize = 13, FontWeight = FontWeights.Bold, Foreground = Theme.Fore, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, -1, 0, 0) },
    }, onClick);

    public static Border Button(string title, Action onClick) => Clickable(new Border
    {
        Background = Theme.WithAlpha(Theme.Secondary, 0.2), CornerRadius = new CornerRadius(6), Padding = new Thickness(12, 5, 12, 5),
        Child = Text(title, 13),
    }, onClick);

    public static Slider Slider(int value, int min, int max, int step, Action<int> changed)
    {
        var s = new Slider
        {
            Minimum = min, Maximum = max, Value = value, TickFrequency = step, IsSnapToTickEnabled = true,
            TickPlacement = System.Windows.Controls.Primitives.TickPlacement.BottomRight, Foreground = Theme.Secondary,
        };
        // 드래그가 끝났을 때만 저장 (매번 저장하면 화면이 다시 그려져 드래그가 끊김)
        s.PreviewMouseLeftButtonUp += (_, _) => changed((int)s.Value);
        s.KeyUp += (_, _) => changed((int)s.Value);
        return s;
    }

    public static Border Legend(Brush c, string t) => new()
    {
        Child = H(4, new Rectangle { Width = 9, Height = 9, RadiusX = 2, RadiusY = 2, Fill = c }, Text(t, 11)),
    };

    // ── 배터리 그림 ──
    public static Grid BatteryGlyph(int pct, string glyph, double width = 104)
    {
        double h = width * 0.5;
        var g = new Grid { Width = width + 9, Height = h };
        var body = new Border
        {
            Width = width, Height = h, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(h * 0.22),
            BorderBrush = Theme.WithAlpha(Theme.Secondary, 0.7), BorderThickness = new Thickness(3), Padding = new Thickness(5),
        };
        var inner = new Grid();
        inner.Children.Add(new Border
        {
            Width = Math.Max(h * 0.2, (width - 16) * pct / 100.0), HorizontalAlignment = HorizontalAlignment.Left,
            CornerRadius = new CornerRadius(h * 0.14), Background = Theme.Level(pct),
        });
        if (!string.IsNullOrEmpty(glyph))
            inner.Children.Add(new TextBlock { Text = glyph, FontFamily = new FontFamily("Segoe UI Emoji, Segoe UI Symbol"), FontSize = h * 0.38, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        body.Child = inner;
        g.Children.Add(body);
        g.Children.Add(new Border { Width = 6, Height = h * 0.32, CornerRadius = new CornerRadius(2), Background = Theme.WithAlpha(Theme.Secondary, 0.7), HorizontalAlignment = HorizontalAlignment.Right });
        return g;
    }

    // ── 용량 막대: 설계(전체) 안에 완충 용량, 그 안에 현재 ──
    public static StackPanel CapacityBar(BatteryInfo b, double width)
    {
        double design = Math.Max(b.DesignMWh, 1);
        double wFull = width * Math.Min(b.FullMWh, b.DesignMWh) / design;
        double wCur = width * Math.Min(b.RemainingMWh, b.FullMWh) / design;
        int chargePct = b.FullMWh > 0 ? (int)Math.Round(b.RemainingMWh * 100.0 / b.FullMWh) : b.Percent;
        var fill = Theme.Level(chargePct);

        var canvas = new Canvas { Width = width, Height = 16, ClipToBounds = false };
        void Rect(double x, double w, Brush br) { var r = new Rectangle { Width = Math.Max(0, w), Height = 16, RadiusX = 5, RadiusY = 5, Fill = br }; Canvas.SetLeft(r, x); canvas.Children.Add(r); }
        Rect(0, width, Theme.Faint);
        // 열화로 잃은 부분 빗금
        var hatch = new DrawingBrush(new GeometryDrawing(null, new Pen(Theme.WithAlpha(Theme.Secondary, 0.45), 1.5), Geometry.Parse("M0,8 L8,0")))
        { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 6, 6), ViewportUnits = BrushMappingMode.Absolute };
        Rect(wFull, width - wFull, hatch);
        Rect(0, wFull, Theme.WithAlpha(fill, 0.25));
        Rect(0, wCur, fill);
        var edge = new Rectangle { Width = 2, Height = 22, Fill = Theme.WithAlpha(Theme.Fore, 0.55) };
        Canvas.SetLeft(edge, wFull - 1); Canvas.SetTop(edge, -3); canvas.Children.Add(edge);

        int lost = Math.Max(0, 100 - (int)Math.Round(b.Soh));
        return V(6,
            Spread(Text(L10n.Tr("용량"), 13, Theme.Secondary),
                   H(4, Text($"{b.RemainingMWh:N0}", 13, null, FontWeights.SemiBold), Text($"/ {b.FullMWh:N0} mWh", 13, Theme.Secondary))),
            canvas,
            H(10, Legend(fill, L10n.Tr("현재 %@%", chargePct)), Legend(Theme.WithAlpha(fill, 0.3), L10n.Tr("최대 %@", b.FullMWh.ToString("N0"))),
                  Legend(Theme.WithAlpha(Theme.Secondary, 0.4), L10n.Tr("설계 %@", b.DesignMWh.ToString("N0")))),
            Spread(H(0, Text(L10n.Tr("배터리 성능(SOH) "), 11.5, Theme.Secondary), Text($"{b.Soh:F1}%", 11.5, b.Soh >= 80 ? Theme.Fore : Theme.Orange, FontWeights.SemiBold)),
                   Text(L10n.Tr("열화로 %@% (%@ mWh) 감소", lost, (b.DesignMWh - b.FullMWh).ToString("N0")), 11.5, Theme.Secondary)));
    }

    // ── 사용 기록 막대 (최근 4시간, 5분 단위) ──
    public static Border UsageBars(IReadOnlyList<Sample> samples, double width, double height = 64)
    {
        const int count = 48;
        var start = DateTime.Now.AddMinutes(-5 * count);
        var groups = samples.Where(s => s.Date >= start)
            .GroupBy(s => Math.Min(count - 1, (int)((s.Date - start).TotalMinutes / 5)))
            .ToDictionary(g => g.Key, g => g.ToList());
        var canvas = new Canvas { Width = width, Height = height };
        double w = width / count;
        for (int i = 0; i < count; i++)
        {
            var bg = new Rectangle { Width = Math.Max(1, w - 2), Height = height, RadiusX = 1.5, RadiusY = 1.5, Fill = Theme.Faint };
            Canvas.SetLeft(bg, i * w); canvas.Children.Add(bg);
            if (!groups.TryGetValue(i, out var g)) continue;
            var last = g[^1];
            Brush color = g.Any(x => x.Limited) ? Theme.Blue : g.Any(x => x.Charging) ? Theme.Green : Theme.WithAlpha(Theme.Level(last.Percent), 0.75);
            double h = height * last.Percent / 100.0;
            var r = new Rectangle { Width = Math.Max(1, w - 2), Height = h, RadiusX = 1.5, RadiusY = 1.5, Fill = color };
            Canvas.SetLeft(r, i * w); Canvas.SetTop(r, height - h); canvas.Children.Add(r);
        }
        return Card(canvas, 6);
    }
}
