// 주기 작업: 배터리 읽기, 기록, 충전 유지 / 퇴근 충전 적용, 덮개 닫힘 동작

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace ClamshellDischarge;

public enum Mode { Off, Maintain, Departure, Commute, OneShot, Unavailable }

public sealed record Sample(DateTime Date, int Percent, double Soh, int Cycles, bool Limited, bool Charging);

public sealed class Engine
{
    public static Engine Shared { get; } = new();

    public IChargeController Controller { get; private set; } = new NoController("");
    public BatteryInfo Snapshot { get; private set; } = new();
    public List<Sample> Samples { get; } = History.Load();
    public Mode Mode { get; private set; } = Mode.Off;
    public int? Target { get; private set; }
    public int? AppliedLimit { get; private set; }
    public DateTime? NextDeparture { get; private set; }
    public DateTime? NextCommute { get; private set; }
    public string LastError { get; private set; } = "";

    public event Action? Updated;

    AppSettings S => AppSettings.Shared;
    DateTime lastSample = DateTime.MinValue;
    int? lastApplied = -1;

    public void Start()
    {
        Controller = ChargeControl.Detect();
        AppliedLimit = Controller.CurrentLimit();
        ApplyLid();
        Tick();
    }

    // ── 일정 (출근·퇴근) ──

    public DateTime? NextTime(ScheduleKind k, DateTime now)
    {
        var v = S.Schedule(k);
        if (!v.Enabled || v.Weekdays.Count == 0) return null;
        for (int d = 0; d < 8; d++)
        {
            var day = now.Date.AddDays(d);
            if (!v.Weekdays.Contains((int)day.DayOfWeek)) continue;
            var t = day.AddMinutes(v.Minutes);
            if (t.AddMinutes(30) > now) return t;
        }
        return null;
    }

    public bool InWindow(ScheduleKind k, DateTime now)
    {
        var t = NextTime(k, now);
        return t is DateTime x && now >= x.AddMinutes(-S.Schedule(k).Lead) && now <= x.AddMinutes(30);
    }

    public ScheduleKind? ActiveSchedule(DateTime now)
    {
        ScheduleKind? best = null;
        foreach (var k in new[] { ScheduleKind.Commute, ScheduleKind.Leave })
            if (InWindow(k, now) && (best == null || S.Schedule(k).Target > S.Schedule(best.Value).Target)) best = k;
        return best;
    }

    public DateTime? Departure(DateTime now) => NextTime(ScheduleKind.Leave, now);

    // ── 주기 작업 ──

    public void Tick()
    {
        var now = DateTime.Now;
        Snapshot = Battery.Read();
        NextDeparture = NextTime(ScheduleKind.Leave, now);
        NextCommute = NextTime(ScheduleKind.Commute, now);
        Record();
        UpdateOneShot();

        if (Controller.Kind == ControlKind.None) { Mode = Mode.Unavailable; Target = null; Updated?.Invoke(); return; }

        int? want = null;
        if (S.OneShotTarget > 0) { Mode = Mode.OneShot; want = S.OneShotTarget; }
        else if (ActiveSchedule(now) is ScheduleKind k)
        {
            Mode = k == ScheduleKind.Commute ? Mode.Commute : Mode.Departure;
            want = S.Schedule(k).Target;
        }
        else if (S.MaintainEnabled)
        {
            Mode = Mode.Maintain;
            want = Controller.Kind == ControlKind.Conservation ? Controller.FixedLevel : S.MaintainLevel;
        }
        else Mode = Mode.Off;
        Target = want;

        int? limit = want is int w && w < 100 ? w : null;
        if (limit != lastApplied)
        {
            if (Controller.Apply(limit, S.Band)) { lastApplied = limit; LastError = ""; }
            else LastError = Controller.Detail;
        }
        AppliedLimit = Controller.CurrentLimit() ?? limit;
        Updated?.Invoke();
    }

    /// <summary>팝업이 열려 있는 동안 자주 호출: 표시용 값만 갱신</summary>
    public void RefreshLive() => Snapshot = Battery.Read();

    /// <summary>설정 변경 직후: 다음 Tick 에서 반드시 다시 적용</summary>
    public void Reapply() { lastApplied = -1; ApplyLid(); Tick(); }

    // 지금 충전 자동 해제: 목표에 닿은 뒤 어댑터를 뽑았거나(가지고 나감) 24시간이 지나면
    bool oneShotReached;
    void UpdateOneShot()
    {
        if (S.OneShotTarget <= 0) { oneShotReached = false; return; }
        if ((DateTime.Now - S.OneShotSince).TotalHours > 24) { S.CancelOneShot(); return; }
        if (Snapshot.Percent >= Math.Min(S.OneShotTarget, 100) - 1) oneShotReached = true;
        if (oneShotReached && !Snapshot.PowerOnline) { oneShotReached = false; S.CancelOneShot(); }
    }

    void Record()
    {
        if ((DateTime.Now - lastSample).TotalSeconds < 55 || !Snapshot.Present) return;
        lastSample = DateTime.Now;
        var s = new Sample(DateTime.Now, Snapshot.Percent, Snapshot.Soh, Snapshot.Cycles,
            AppliedLimit is int l && Snapshot.Percent >= l - 1 && !Snapshot.Charging, Snapshot.Charging);
        Samples.Add(s);
        History.Append(s);
        var cutoff = DateTime.Now.AddDays(-History.KeepDays);
        if (Samples.Count > 0 && Samples[0].Date < cutoff)
        {
            Samples.RemoveAll(x => x.Date < cutoff);
            History.Rewrite(Samples);
        }
    }

    // ── 덮개 닫힘 동작 (powercfg LIDACTION) ──
    // 켜면: 전원 연결 시 아무것도 안 함(0), 배터리일 때 절전(1). 끄면 원래 값으로 복원.

    void ApplyLid()
    {
        try
        {
            if (S.LidStayAwake)
            {
                if (S.OriginalLidAc < 0 || S.OriginalLidDc < 0)
                {
                    var (ac, dc) = Lid.Read();
                    S.OriginalLidAc = ac; S.OriginalLidDc = dc;
                    S.Save();
                }
                Lid.Set(0, 1);
            }
            else if (S.OriginalLidAc >= 0 && S.OriginalLidDc >= 0)
            {
                Lid.Set(S.OriginalLidAc, S.OriginalLidDc);
                S.OriginalLidAc = -1; S.OriginalLidDc = -1;
                S.Save();
            }
        }
        catch (Exception e) { LastError = e.Message; }
    }

    public string Diagnostics()
    {
        var (man, model, family) = Battery.SystemModel();
        var b = Snapshot;
        var (ac, dc) = Lid.Read();
        return string.Join(Environment.NewLine, new[]
        {
            $"Clamshell Discharge for Windows {typeof(Engine).Assembly.GetName().Version}",
            $"OS: {Environment.OSVersion}",
            $"System: {man} | {model} | {family}",
            $"Controller: {Controller.GetType().Name} ({Controller.Kind}) — {Controller.Detail}",
            $"Current limit: {Controller.CurrentLimit()?.ToString() ?? "none"}",
            $"Mode: {Mode}, target: {Target?.ToString() ?? "-"}, last error: {LastError}",
            $"Battery: {b.Percent}% remaining {b.RemainingMWh} / full {b.FullMWh} / design {b.DesignMWh} mWh, cycles {b.Cycles}",
            $"Power online {b.PowerOnline}, charging {b.Charging} ({b.ChargeRateMW} mW), discharging {b.Discharging} ({b.DischargeRateMW} mW), {b.VoltageMV} mV",
            $"Battery: {b.Manufacturer} {b.Name}",
            $"LIDACTION AC={ac} DC={dc}",
        });
    }
}

public static class History
{
    public static double KeepDays => 90;
    static string FilePath => Path.Combine(AppSettings.Dir, "history.csv");

    public static List<Sample> Load()
    {
        var list = new List<Sample>();
        try
        {
            if (!File.Exists(FilePath)) return list;
            var cutoff = DateTime.Now.AddDays(-KeepDays);
            foreach (var line in File.ReadAllLines(FilePath))
            {
                var f = line.Split(',');
                if (f.Length < 6 || !long.TryParse(f[0], out var t)) continue;
                var date = DateTimeOffset.FromUnixTimeSeconds(t).LocalDateTime;
                if (date < cutoff) continue;
                list.Add(new Sample(date, int.Parse(f[1]), double.Parse(f[2], CultureInfo.InvariantCulture),
                    int.Parse(f[3]), f[4] == "1", f[5] == "1"));
            }
        }
        catch { }
        return list;
    }

    static string Line(Sample s) => string.Format(CultureInfo.InvariantCulture, "{0},{1},{2:F2},{3},{4},{5}",
        new DateTimeOffset(s.Date).ToUnixTimeSeconds(), s.Percent, s.Soh, s.Cycles, s.Limited ? 1 : 0, s.Charging ? 1 : 0);

    public static void Append(Sample s)
    {
        try { Directory.CreateDirectory(AppSettings.Dir); File.AppendAllText(FilePath, Line(s) + "\n"); } catch { }
    }

    public static void Rewrite(List<Sample> all)
    {
        try { File.WriteAllLines(FilePath, all.Select(Line)); } catch { }
    }
}

public static class Lid
{
    const string Sub = "SUB_BUTTONS", Setting = "LIDACTION";

    /// <summary>현재 전원 계획의 덮개 닫힘 동작 (0=아무것도 안 함, 1=절전, 2=최대 절전, 3=종료)</summary>
    public static (int Ac, int Dc) Read()
    {
        var o = Run($"/query SCHEME_CURRENT {Sub} {Setting}");
        var vals = Regex.Matches(o, @":\s*0x([0-9a-fA-F]+)\s*$", RegexOptions.Multiline)
            .Select(m => Convert.ToInt32(m.Groups[1].Value, 16)).ToList();
        // 출력 끝의 두 값이 AC, DC 순서
        return vals.Count >= 2 ? (vals[^2], vals[^1]) : (1, 1);
    }

    public static void Set(int ac, int dc)
    {
        Run($"/setacvalueindex SCHEME_CURRENT {Sub} {Setting} {ac}");
        Run($"/setdcvalueindex SCHEME_CURRENT {Sub} {Setting} {dc}");
        Run("/setactive SCHEME_CURRENT");
    }

    static string Run(string args)
    {
        try
        {
            var p = Process.Start(new ProcessStartInfo("powercfg.exe", args)
            {
                RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true,
            });
            if (p == null) return "";
            var o = p.StandardOutput.ReadToEnd();
            p.WaitForExit(5000);
            return o;
        }
        catch { return ""; }
    }
}
