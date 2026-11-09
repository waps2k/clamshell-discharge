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

    // 덮개 닫힘 동작
    public bool LidStayAwake { get; set; } = false;
    /// <summary>앱이 바꾸기 전 원래 값 (복원용). -1 = 저장 안 됨</summary>
    public int OriginalLidAc { get; set; } = -1;
    public int OriginalLidDc { get; set; } = -1;

    public string Language { get; set; } = "system";
    public int Band { get; set; } = 3;

    public string DepartureTimeText => $"{DepartureMinutes / 60:00}:{DepartureMinutes % 60:00}";

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
