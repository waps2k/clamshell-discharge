// 제조사별 충전 제어. 실행 시 기기를 감지해 하나를 고른다.
//
// Lenovo ThinkPad : 시작/중지 임계값 (Lenovo PM 드라이버 \\.\IBMPmDrv + PWRMGRV 레지스트리)
//   프로토콜 출처: wesmar/lbm (MIT) README "Implementation" 절 — ThinkPad T14 에서 검증됨
// Lenovo IdeaPad/Yoga/Legion : 보존 모드 (Energy Management 드라이버 \\.\EnergyDrv)
//   임계값은 펌웨어 고정 (대략 2021년 이전 60%, 이후 80%)
//   프로토콜 출처: dara-oladapo/power-helper (MIT) WindowsBatteryConservationController

using System;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;
using System.ServiceProcess;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace ClamshellDischarge;

public enum ControlKind { None, Threshold, Conservation }

public interface IChargeController
{
    ControlKind Kind { get; }
    string Name { get; }
    /// <summary>사용 불가 이유 또는 상세 정보 (진단용)</summary>
    string Detail { get; }
    /// <summary>Conservation 일 때 대략적인 고정 유지 수준</summary>
    int FixedLevel { get; }
    /// <summary>현재 적용된 중지 수준 (null = 한도 없음). 알 수 없으면 null.</summary>
    int? CurrentLimit();
    /// <summary>중지 수준 적용. null 이면 한도 해제(정상 충전).</summary>
    bool Apply(int? stopPercent, int band);
}

public static class ChargeControl
{
    public static IChargeController Detect()
    {
        var (man, model, family) = Battery.SystemModel();
        var up = man.ToUpperInvariant();
        if (up.Contains("LENOVO"))
        {
            var name = $"{model} {family}".ToUpperInvariant();
            bool thinkpad = name.Contains("THINKPAD");
            if (thinkpad)
            {
                var tp = new LenovoThinkPadController();
                if (tp.Available) return tp;
            }
            var cons = new LenovoConservationController(model);
            if (cons.Available) return cons;
            if (!thinkpad)
            {
                // 이름에 ThinkPad 가 없어도 PM 드라이버가 있으면 임계값 방식 시도
                var tp = new LenovoThinkPadController();
                if (tp.Available) return tp;
            }
            return new NoController($"Lenovo {model}: {cons.Detail}");
        }
        return new NoController($"{man} {model}: not implemented yet");
    }
}

public sealed class NoController : IChargeController
{
    public NoController(string detail) { Detail = detail; }
    public ControlKind Kind => ControlKind.None;
    public string Name => L10n.Tr("지원 안 됨 (모니터링만)");
    public string Detail { get; }
    public int FixedLevel => 0;
    public int? CurrentLimit() => null;
    public bool Apply(int? stopPercent, int band) => false;
}

// ───────────────────────── Lenovo ThinkPad ─────────────────────────

public sealed class LenovoThinkPadController : IChargeController
{
    const string DevicePath = @"\\.\IBMPmDrv";
    const string ServiceName = "IBMPMDRV";
    const string RegRoot = @"SOFTWARE\WOW6432Node\Lenovo\PWRMGRV\ConfKeys\Data";

    const uint IoctlSelectMode = 0x22261C;   // 0 = 자동(한도 없음), 0x101 = 배터리1 임계값 모드
    const uint IoctlSetStart = 0x222630;     // 0x100 | start
    const uint IoctlSetStop = 0x222638;      // 0x100 | stop
    const uint Rejected = 0x80000000;

    public ControlKind Kind => ControlKind.Threshold;
    public string Name => L10n.Tr("ThinkPad 충전 임계값");
    public string Detail { get; private set; } = "";
    public int FixedLevel => 0;
    public bool Available { get; }

    public LenovoThinkPadController()
    {
        try
        {
            using var h = Native.OpenDevice(DevicePath);
            if (h.IsInvalid) { EnsureServiceStarted(); }
            using var h2 = Native.OpenDevice(DevicePath);
            Available = !h2.IsInvalid;
            Detail = Available ? "IBMPmDrv ok" : $"IBMPmDrv not available (error {Marshal.GetLastWin32Error()})";
        }
        catch (Exception e) { Detail = e.Message; }
    }

    public int? CurrentLimit()
    {
        try
        {
            using var key = BatteryKey(false);
            if (key == null) return null;
            var ctl = key.GetValue("ChargeStopControl") as int? ?? 0;
            var stop = key.GetValue("ChargeStopPercentage") as int? ?? 0;
            return ctl == 1 && stop is > 0 and < 100 ? stop : null;
        }
        catch { return null; }
    }

    public bool Apply(int? stopPercent, int band)
    {
        if (!Available) return false;
        try
        {
            using var h = Native.OpenDevice(DevicePath);
            if (h.IsInvalid) return false;
            bool ok;
            if (stopPercent is int stop && stop < 100)
            {
                stop = Math.Clamp(stop, 20, 99);
                int start = Math.Clamp(stop - Math.Max(1, band), 0, stop - 1);
                WriteRegistry(true, start, stop);
                ok = Send(h, IoctlSelectMode, 0x101)
                     && Send(h, IoctlSetStop, 0x100u | (uint)stop)
                     && Send(h, IoctlSetStart, 0x100u | (uint)start);
            }
            else
            {
                // 해제: 임계값을 0 으로 지운 뒤 자동 모드 (EC 가 마지막 중지값을 붙잡고 있으므로)
                WriteRegistry(false, 0, 100);
                ok = Send(h, IoctlSetStop, 0x100u) && Send(h, IoctlSetStart, 0x100u) && Send(h, IoctlSelectMode, 0);
            }
            Native.BroadcastSettingChange();
            return ok;
        }
        catch (Exception e) { Detail = e.Message; return false; }
    }

    static bool Send(SafeFileHandle h, uint ioctl, uint payload)
    {
        bool r = Native.DeviceIoControl(h, ioctl, ref payload, 4, out uint result, 4, out _, IntPtr.Zero);
        return r && (result & Rejected) == 0;
    }

    static RegistryKey? BatteryKey(bool writable)
    {
        using var data = Registry.LocalMachine.OpenSubKey(RegRoot, writable);
        if (data == null) return null;
        foreach (var name in data.GetSubKeyNames())
        {
            var k = data.OpenSubKey(name, writable);
            if (k?.GetValue("ChargeStartPercentage") != null) return k;
            k?.Dispose();
        }
        return null;
    }

    static void WriteRegistry(bool enable, int start, int stop)
    {
        try
        {
            using var k = BatteryKey(true);
            if (k == null) return;
            k.SetValue("ChargeStartControl", enable ? 1 : 0, RegistryValueKind.DWord);
            k.SetValue("ChargeStopControl", enable ? 1 : 0, RegistryValueKind.DWord);
            k.SetValue("ChargeStartPercentage", start, RegistryValueKind.DWord);
            k.SetValue("ChargeStopPercentage", stop, RegistryValueKind.DWord);
        }
        catch { /* 레지스트리가 없어도 드라이버 쪽 적용은 시도 */ }
    }

    static void EnsureServiceStarted()
    {
        try
        {
            using var sc = new ServiceController(ServiceName);
            if (sc.Status != ServiceControllerStatus.Running)
            {
                sc.Start();
                sc.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(5));
            }
        }
        catch { }
    }
}

// ──────────────────── Lenovo IdeaPad / Yoga / Legion ────────────────────

public sealed class LenovoConservationController : IChargeController
{
    const string DevicePath = @"\\.\EnergyDrv";
    const uint IoctlChargeMode = 0x831020F8;
    const uint Query = 0xFF, SetNormal = 0x05, SetConservation = 0x03, Prepare = 0x08;
    const uint ConservationBit = 0x20;

    public ControlKind Kind => ControlKind.Conservation;
    public string Name => L10n.Tr("보존 모드 (약 %@%, 고정)", FixedLevel);
    public string Detail { get; private set; } = "";
    public int FixedLevel { get; }
    public bool Available { get; }

    public LenovoConservationController(string model)
    {
        // 2022년 이후 모델은 대체로 80%, 이전은 60% (펌웨어 고정, 정확한 값은 기종마다 다름)
        FixedLevel = 80;
        try
        {
            using var h = Native.OpenDevice(DevicePath);
            if (h.IsInvalid) { Detail = "EnergyDrv not installed"; return; }
            Available = SendQuery(h, out var state);
            Detail = Available ? $"EnergyDrv state 0x{state:X}" : "EnergyDrv present, conservation not exposed";
        }
        catch (Exception e) { Detail = e.Message; }
    }

    public bool IsOn()
    {
        try
        {
            using var h = Native.OpenDevice(DevicePath);
            return !h.IsInvalid && SendQuery(h, out var s) && (s & ConservationBit) != 0;
        }
        catch { return false; }
    }

    public int? CurrentLimit() => IsOn() ? FixedLevel : null;

    public bool Apply(int? stopPercent, int band)
    {
        if (!Available) return false;
        bool want = stopPercent is int s && s < 100 && s <= FixedLevel + 5;
        if (want == IsOn()) return true;
        try
        {
            using var h = Native.OpenDevice(DevicePath);
            if (h.IsInvalid) return false;
            return want ? Send(h, Prepare) && Send(h, SetConservation) : Send(h, SetNormal) && Send(h, Prepare);
        }
        catch (Exception e) { Detail = e.Message; return false; }
    }

    static bool Send(SafeFileHandle h, uint code) => Native.DeviceIoControl(h, IoctlChargeMode, ref code, 4, out _, 4, out _, IntPtr.Zero);

    static bool SendQuery(SafeFileHandle h, out uint state)
    {
        uint code = Query;
        return Native.DeviceIoControl(h, IoctlChargeMode, ref code, 4, out state, 4, out _, IntPtr.Zero);
    }
}

// ───────────────────────── Win32 ─────────────────────────

static class Native
{
    const uint GenericRead = 0x80000000, GenericWrite = 0x40000000, ShareRW = 0x3, OpenExisting = 3;

    public static SafeFileHandle OpenDevice(string path) =>
        CreateFile(path, GenericRead | GenericWrite, ShareRW, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DeviceIoControl(SafeFileHandle h, uint code, ref uint inBuf, uint inSize,
        out uint outBuf, uint outSize, out uint returned, IntPtr overlapped);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);

    public static void BroadcastSettingChange()
    {
        const uint WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 0x2;
        try { SendMessageTimeout((IntPtr)0xFFFF, WM_SETTINGCHANGE, UIntPtr.Zero, "Environment", SMTO_ABORTIFHUNG, 1000, out _); } catch { }
    }
}
