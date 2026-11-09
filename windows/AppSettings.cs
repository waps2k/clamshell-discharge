// 설정 (JSON: %LOCALAPPDATA%\ClamshellDischarge\settings.json)

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace ClamshellDischarge;

public sealed class AppSettings
{
    public static string Dir { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClamshellDischarge");
    static string FilePath => Path.Combine(Dir, "settings.json");

    public static AppSettings Shared { get; } = Load();

    /// <summary>설정이 바뀌면 (UI 갱신·엔진 재적용)</summary>
    public static event Action? Changed;

    // 충전 유지
    public bool MaintainEnabled { get; set; } = false;
    public int MaintainLevel { get; set; } = 60;

    // 퇴근 충전
    public bool DepartureEnabled { get; set; } = false;
    public int DepartureMinutes { get; set; } = 18 * 60;
    public int DepartureTarget { get; set; } = 100;
    public int DepartureLead { get; set; } = 90;
    /// <summary>DayOfWeek 값 (0=일 … 6=토)</summary>
    public List<int> DepartureWeekdays { get; set; } = new() { 1, 2, 3, 4, 5 };

    // 출근 충전 (집에서 밤새 전원 연결 → 출근 전에 목표까지)
    public bool CommuteEnabled { get; set; } = false;
    public int CommuteMinutes { get; set; } = 8 * 60;
    public int CommuteTarget { get; set; } = 80;
    public int CommuteLead { get; set; } = 90;
    public List<int> CommuteWeekdays { get; set; } = new() { 1, 2, 3, 4, 5 };

    // 주말 외출 충전 (출근과 시각이 다른 주말용)
    public bool WeekendEnabled { get; set; } = false;
    public int WeekendMinutes { get; set; } = 10 * 60;
    public int WeekendTarget { get; set; } = 80;
    public int WeekendLead { get; set; } = 60;
    public List<int> WeekendWeekdays { get; set; } = new() { 6, 0 };

    /// <summary>지금 충전 출발 시각. null 이면 바로 충전, 미래면 그 시각에 맞춰 늦게 시작</summary>
    public DateTime? OneShotDepartAt { get; set; }

    // 지금 충전 (출장·외출): 0 = 꺼짐. 목표 도달 후 어댑터를 뽑거나 24시간이 지나면 해제
    public int OneShotTarget { get; set; } = 0;
    public DateTime OneShotSince { get; set; } = DateTime.MinValue;

    // 덮개 닫힘 동작
    public bool LidStayAwake { get; set; } = false;
    /// <summary>앱이 바꾸기 전 원래 값 (복원용). -1 = 저장 안 됨</summary>
    public int OriginalLidAc { get; set; } = -1;
    public int OriginalLidDc { get; set; } = -1;

    public string Language { get; set; } = "system";
    public int Band { get; set; } = 3;

    public string DepartureTimeText => $"{DepartureMinutes / 60:00}:{DepartureMinutes % 60:00}";

    public ScheduleValues Schedule(ScheduleKind k) => k switch
    {
        ScheduleKind.Commute => new ScheduleValues(CommuteEnabled, CommuteMinutes, CommuteTarget, CommuteLead, CommuteWeekdays),
        ScheduleKind.Weekend => new ScheduleValues(WeekendEnabled, WeekendMinutes, WeekendTarget, WeekendLead, WeekendWeekdays),
        _ => new ScheduleValues(DepartureEnabled, DepartureMinutes, DepartureTarget, DepartureLead, DepartureWeekdays),
    };

    public void UpdateSchedule(ScheduleKind k, Func<ScheduleValues, ScheduleValues> change) => Update(s =>
    {
        var v = change(s.Schedule(k));
        if (k == ScheduleKind.Commute)
        { s.CommuteEnabled = v.Enabled; s.CommuteMinutes = v.Minutes; s.CommuteTarget = v.Target; s.CommuteLead = v.Lead; s.CommuteWeekdays = v.Weekdays; }
        else if (k == ScheduleKind.Weekend)
        { s.WeekendEnabled = v.Enabled; s.WeekendMinutes = v.Minutes; s.WeekendTarget = v.Target; s.WeekendLead = v.Lead; s.WeekendWeekdays = v.Weekdays; }
        else
        { s.DepartureEnabled = v.Enabled; s.DepartureMinutes = v.Minutes; s.DepartureTarget = v.Target; s.DepartureLead = v.Lead; s.DepartureWeekdays = v.Weekdays; }
    });

    /// <summary>target 까지 충전. hours 시간 뒤 출발이면 그 시각에 맞춰 늦게 시작 (0 = 바로)</summary>
    public void StartOneShot(int target, double hours) => Update(s =>
    {
        s.OneShotTarget = target; s.OneShotSince = DateTime.Now;
        s.OneShotDepartAt = hours > 0 ? DateTime.Now.AddHours(hours) : null;
    });

    public void SetOneShotDeparture(double hours) => Update(s => s.OneShotDepartAt = hours > 0 ? DateTime.Now.AddHours(hours) : null);
    public void CancelOneShot() => Update(s => s.OneShotTarget = 0);

    static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
        }
        catch { /* 손상된 파일은 기본값으로 */ }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
        Changed?.Invoke();
    }

    /// <summary>값을 바꾸고 저장: AppSettings.Shared.Update(s => s.MaintainLevel = 60)</summary>
    public void Update(Action<AppSettings> change)
    {
        change(this);
        Save();
    }
}

public enum ScheduleKind { Commute, Leave, Weekend }

public sealed record ScheduleValues(bool Enabled, int Minutes, int Target, int Lead, List<int> Weekdays)
{
    public string TimeText => $"{Minutes / 60:00}:{Minutes % 60:00}";
}

public static class ScheduleKindText
{
    public static readonly ScheduleKind[] All = { ScheduleKind.Commute, ScheduleKind.Leave, ScheduleKind.Weekend };

    public static string Title(this ScheduleKind k) => k switch
    {
        ScheduleKind.Commute => L10n.Tr("출근 충전"), ScheduleKind.Weekend => L10n.Tr("주말 외출 충전"), _ => L10n.Tr("퇴근 충전"),
    };
    public static string Short(this ScheduleKind k) => k switch
    {
        ScheduleKind.Commute => L10n.Tr("출근"), ScheduleKind.Weekend => L10n.Tr("주말"), _ => L10n.Tr("퇴근"),
    };
    public static string NextLabel(this ScheduleKind k) => k switch
    {
        ScheduleKind.Commute => L10n.Tr("다음 출근 충전"), ScheduleKind.Weekend => L10n.Tr("다음 주말 외출 충전"), _ => L10n.Tr("다음 퇴근 충전"),
    };
    public static int[] Presets(this ScheduleKind k) => k switch
    {
        ScheduleKind.Commute => new[] { 6 * 60 + 30, 7 * 60, 7 * 60 + 30, 8 * 60, 8 * 60 + 30, 9 * 60, 9 * 60 + 30 },
        ScheduleKind.Weekend => new[] { 8 * 60, 9 * 60, 10 * 60, 11 * 60, 12 * 60, 13 * 60, 14 * 60 },
        _ => new[] { 16 * 60 + 30, 17 * 60, 17 * 60 + 30, 18 * 60, 18 * 60 + 30, 19 * 60, 20 * 60 },
    };
}
