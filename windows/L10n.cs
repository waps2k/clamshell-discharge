// 다국어: macOS 판과 같은 표(한국어 원문이 키)를 쓰고, Windows 전용 문구는 Extra 에 둔다.
// 사용: L10n.Tr("목표 %@%", 80)  →  "Target 80%" (영어일 때)

using System;
using System.Collections.Generic;
using System.Globalization;

namespace ClamshellDischarge;

public static partial class L10n
{
    public static readonly (string Code, string Name)[] Languages =
    {
        ("system", "System"), ("ko", "한국어"), ("en", "English"), ("ja", "日本語"), ("zh-Hans", "简体中文"),
    };

    public static string Current
    {
        get
        {
            var pref = AppSettings.Shared.Language;
            if (pref != "system") return pref;
            var sys = CultureInfo.CurrentUICulture.Name;
            if (sys.StartsWith("ko")) return "ko";
            if (sys.StartsWith("ja")) return "ja";
            if (sys.StartsWith("zh")) return "zh-Hans";
            return "en";
        }
    }

    public static CultureInfo Culture => Current switch
    {
        "ko" => new CultureInfo("ko-KR"),
        "ja" => new CultureInfo("ja-JP"),
        "zh-Hans" => new CultureInfo("zh-CN"),
        _ => new CultureInfo("en-US"),
    };

    public static string Tr(string key, params object[] args)
    {
        var template = Lookup(key);
        if (args.Length == 0) return template;
        var a = Array.ConvertAll(args, x => Convert.ToString(x, CultureInfo.InvariantCulture) ?? "");
        if (template.Contains("$@"))
        {
            for (int i = 0; i < a.Length; i++) template = template.Replace($"%{i + 1}$@", a[i]);
            return template;
        }
        foreach (var s in a)
        {
            int idx = template.IndexOf("%@", StringComparison.Ordinal);
            if (idx < 0) break;
            template = template.Substring(0, idx) + s + template.Substring(idx + 2);
        }
        return template;
    }

    static string Lookup(string key)
    {
        var lang = Current;
        if (lang == "ko") return key;
        if (!Extra.TryGetValue(key, out var row) && !Shared.TryGetValue(key, out row)) return key;
        return lang switch { "ja" => row[1], "zh-Hans" => row[2], _ => row[0] };
    }

    public static string Time(DateTime t) => t.ToString("t", Culture);
    public static string WeekdayTime(DateTime t) => t.ToString("ddd ", Culture) + t.ToString("t", Culture);

    // Windows 전용 문구 : [English, 日本語, 简体中文]
    private static readonly Dictionary<string, string[]> Extra = new()
    {
        ["충전 제어"] = new[] { "Charge control", "充電制御", "充电控制" },
        ["지원 안 됨 (모니터링만)"] = new[] { "Not supported (monitoring only)", "非対応(モニタリングのみ)", "不支持(仅监控)" },
        ["ThinkPad 충전 임계값"] = new[] { "ThinkPad charge thresholds", "ThinkPad 充電しきい値", "ThinkPad 充电阈值" },
        ["보존 모드 (약 %@%, 고정)"] = new[] { "Conservation mode (~%@%, fixed)", "節約モード(約%@%・固定)", "养护模式(约 %@%，固定)" },
        ["덮개 닫아도 동작 (전원 연결 시)"] = new[] { "Stay awake with lid closed (on power)", "蓋を閉じても動作(電源接続時)", "合盖继续运行(接电源时)" },
        ["관리자 권한으로 실행해야 합니다"] = new[] { "Run as administrator", "管理者として実行してください", "请以管理员身份运行" },
        ["한도 %@%"] = new[] { "Limit %@%", "上限 %@%", "上限 %@%" },
        ["한도 없음"] = new[] { "No limit", "上限なし", "无上限" },
        ["보존 모드 켜짐"] = new[] { "Conservation on", "節約モード オン", "养护模式开启" },
        ["보존 모드 꺼짐"] = new[] { "Conservation off", "節約モード オフ", "养护模式关闭" },
        ["이 기기는 정해진 수준(약 %@%)으로만 유지할 수 있습니다."] = new[] { "This device can only hold a fixed level (~%@%).", "この機種は決まったレベル(約%@%)でのみ維持できます。", "此设备只能保持在固定水平(约 %@%)。" },
        ["충전 중지 상태"] = new[] { "Charging paused", "充電停止中", "已暂停充电" },
        ["진단 정보 복사"] = new[] { "Copy diagnostics", "診断情報をコピー", "复制诊断信息" },
        ["진단 정보를 클립보드에 복사했습니다."] = new[] { "Diagnostics copied to the clipboard.", "診断情報をクリップボードにコピーしました。", "诊断信息已复制到剪贴板。" },
        ["열기"] = new[] { "Open", "開く", "打开" },
        ["열화로 %@% (%@ mWh) 감소"] = new[] { "%@% lost to wear (%@ mWh)", "劣化で%@%低下 (%@ mWh)", "老化损失 %@% (%@ mWh)" },
        ["이미 실행 중입니다."] = new[] { "Already running.", "すでに実行中です。", "已在运行。" },
    };
}
