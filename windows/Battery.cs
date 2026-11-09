// 배터리 정보 (WMI root\wmi + Win32_Battery + PowerStatus)
// Windows 는 용량을 mWh 로 보고한다 (macOS 는 mAh).

using System;
using System.Linq;
using System.Management;
using System.Windows.Forms;

namespace ClamshellDischarge;

public sealed class BatteryInfo
{
    public DateTime Date = DateTime.Now;
    public bool Present;
    public int Percent;
    public int RemainingMWh;
    public int FullMWh;
    public int DesignMWh;
    public int Cycles;
    public bool PowerOnline;      // 어댑터 연결
    public bool Charging;
    public bool Discharging;
    public int ChargeRateMW;      // 충전 중 +
    public int DischargeRateMW;   // 방전 중 +
    public int VoltageMV;
    public int? MinutesRemaining; // 배터리 사용 시 남은 시간
    public string Name = "";
    public string Manufacturer = "";

    /// <summary>State of Health: 완충 용량 ÷ 설계 용량</summary>
    public double Soh => DesignMWh > 0 ? FullMWh * 100.0 / DesignMWh : 0;

    /// <summary>배터리 입출력 전력 (W): +충전 / -방전</summary>
    public double BatteryWatts => Charging ? ChargeRateMW / 1000.0 : -DischargeRateMW / 1000.0;

    public int? MinutesToFull => Charging && ChargeRateMW > 0 && FullMWh > RemainingMWh
        ? (int)((FullMWh - RemainingMWh) * 60.0 / ChargeRateMW) : null;

    public int? MinutesTo(int target)
    {
        if (!Charging || ChargeRateMW <= 0 || FullMWh <= 0 || target <= Percent) return null;
        double need = (target - Percent) / 100.0 * FullMWh;
        return (int)(need * 60 / ChargeRateMW);
    }
}

public static class Battery
{
    public static BatteryInfo Read()
    {
        var b = new BatteryInfo();
        try
        {
            var ps = SystemInformation.PowerStatus;
            b.Present = ps.BatteryChargeStatus != BatteryChargeStatus.NoSystemBattery;
            b.Percent = (int)Math.Round(ps.BatteryLifePercent * 100);
            b.PowerOnline = ps.PowerLineStatus == PowerLineStatus.Online;
            if (ps.BatteryLifeRemaining > 0) b.MinutesRemaining = ps.BatteryLifeRemaining / 60;
        }
        catch { }

        try
        {
            var scope = new ManagementScope(@"root\wmi");
            b.DesignMWh = First(scope, "BatteryStaticData", "DesignedCapacity");
            b.FullMWh = First(scope, "BatteryFullChargedCapacity", "FullChargedCapacity");
            b.Cycles = First(scope, "BatteryCycleCount", "CycleCount");
            using var s = new ManagementObjectSearcher(scope, new ObjectQuery("SELECT * FROM BatteryStatus"));
            foreach (ManagementObject o in s.Get())
            {
                b.RemainingMWh = ToInt(o["RemainingCapacity"]);
                b.ChargeRateMW = ToInt(o["ChargeRate"]);
                b.DischargeRateMW = ToInt(o["DischargeRate"]);
                b.VoltageMV = ToInt(o["Voltage"]);
                b.Charging = o["Charging"] is bool c && c;
                b.Discharging = o["Discharging"] is bool d && d;
                if (o["PowerOnline"] is bool p) b.PowerOnline = p;
                break;
            }
            using var sd = new ManagementObjectSearcher(scope, new ObjectQuery("SELECT DeviceName, ManufactureName FROM BatteryStaticData"));
            foreach (ManagementObject o in sd.Get())
            {
                b.Name = (o["DeviceName"] as string)?.Trim() ?? "";
                b.Manufacturer = (o["ManufactureName"] as string)?.Trim() ?? "";
                break;
            }
        }
        catch { /* 일부 기종은 root\wmi 배터리 클래스가 없음 */ }

        if (b.FullMWh > 0 && b.RemainingMWh > 0 && b.Percent == 0)
            b.Percent = (int)Math.Round(b.RemainingMWh * 100.0 / b.FullMWh);
        return b;
    }

    static int First(ManagementScope scope, string cls, string prop)
    {
        try
        {
            using var s = new ManagementObjectSearcher(scope, new ObjectQuery($"SELECT {prop} FROM {cls}"));
            foreach (ManagementObject o in s.Get()) return ToInt(o[prop]);
        }
        catch { }
        return 0;
    }

    static int ToInt(object? v)
    {
        try { return v == null ? 0 : Convert.ToInt32(v); } catch { return 0; }
    }

    /// <summary>제조사 / 모델 (예: "LENOVO", "ThinkPad X1 Carbon Gen 11")</summary>
    public static (string Manufacturer, string Model, string Family) SystemModel()
    {
        string man = "", model = "", family = "";
        try
        {
            using var s = new ManagementObjectSearcher("SELECT Manufacturer, Model, SystemFamily FROM Win32_ComputerSystem");
            foreach (ManagementObject o in s.Get())
            {
                man = (o["Manufacturer"] as string ?? "").Trim();
                model = (o["Model"] as string ?? "").Trim();
                family = (o["SystemFamily"] as string ?? "").Trim();
            }
            // Lenovo 는 Model 이 기계 타입 코드(예: 21HM...)라서 Version 에 제품명이 들어 있음
            using var p = new ManagementObjectSearcher("SELECT Version FROM Win32_ComputerSystemProduct");
            foreach (ManagementObject o in p.Get())
            {
                var ver = (o["Version"] as string ?? "").Trim();
                if (!string.IsNullOrEmpty(ver) && man.ToUpperInvariant().Contains("LENOVO")) model = ver;
            }
        }
        catch { }
        return (man, model, family);
    }
}
