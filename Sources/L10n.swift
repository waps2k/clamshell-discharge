// 다국어 지원: 한국어(원문, 키) · English · 日本語 · 简体中文
//
// 코드에서는 tr("목표 \(t)%") 처럼 한국어 원문을 그대로 쓴다.
// 보간 부분은 %@ 로 바뀌어 키가 되고("목표 %@%"), 아래 표에서 번역을 찾아 값을 채운다.
// 번역에서 순서를 바꿔야 하면 %1$@, %2$@ 처럼 위치를 지정한다.

import Foundation

struct LocStr: ExpressibleByStringInterpolation {
    var key: String
    var args: [String]

    init(stringLiteral value: String) { key = value; args = [] }
    init(stringInterpolation s: Interp) { key = s.key; args = s.args }

    struct Interp: StringInterpolationProtocol {
        var key = ""
        var args: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) { key += "%@"; args.append("\(value)") }
    }
}

/// 한국어 원문(보간 포함)을 현재 언어로
func tr(_ s: LocStr) -> String { L10n.format(L10n.lookup(s.key), s.args) }

/// 변수에 담긴 한국어 원문을 현재 언어로 (enum rawValue 등)
func trKey(_ key: String) -> String { L10n.lookup(key) }

/// 선택한 언어 형식으로 날짜·시각 표시
extension Date {
    var tTime: String { formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)) }
    var tDateTime: String { formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)) }
    var tWeekdayTime: String { formatted(Date.FormatStyle().weekday(.abbreviated).hour().minute().locale(L10n.locale)) }
}

enum L10n {
    /// 선택 가능한 언어 (코드, 표시 이름)
    static let languages: [(code: String, name: String)] = [
        ("system", "System"), ("ko", "한국어"), ("en", "English"), ("ja", "日本語"), ("zh-Hans", "简体中文"),
    ]

    /// 설정값("system" 이면 시스템 언어)을 실제 언어 코드로
    static var current: String {
        let pref = UserDefaults.standard.string(forKey: "language") ?? "system"
        if pref != "system" { return pref }
        let sys = Locale.preferredLanguages.first ?? "en"
        if sys.hasPrefix("ko") { return "ko" }
        if sys.hasPrefix("ja") { return "ja" }
        if sys.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    static var locale: Locale {
        Locale(identifier: current == "zh-Hans" ? "zh_Hans" : current)
    }

    static func lookup(_ key: String) -> String {
        let lang = current
        if lang == "ko" { return key }
        guard let row = table[key] else { return key }
        switch lang {
        case "ja": return row[1]
        case "zh-Hans": return row[2]
        default: return row[0]
        }
    }

    static func format(_ template: String, _ args: [String]) -> String {
        guard !args.isEmpty else { return template }
        var out = template
        if out.contains("$@") {
            for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "%\(i + 1)$@", with: a) }
            return out
        }
        for a in args {
            guard let r = out.range(of: "%@") else { break }
            out.replaceSubrange(r, with: a)
        }
        return out
    }

    // 키(한국어) : [English, 日本語, 简体中文]
    static let table: [String: [String]] = [
        // 공통 상태
        "충전 중": ["Charging", "充電中", "充电中"],
        "방전 중": ["Discharging", "放電中", "放电中"],
        "충전 안 함": ["Not charging", "充電なし", "未充电"],
        "충전 완료": ["Charged", "充電完了", "已充满"],
        "배터리 사용 중": ["On battery", "バッテリー使用中", "正在使用电池"],
        "방전 중 · 유지 모드": ["Discharging · maintain", "放電中 · 維持モード", "放电中 · 保持模式"],
        "방전 중 · 수동 방전": ["Discharging · manual", "放電中 · 手動放電", "放电中 · 手动放电"],
        "전원 연결됨 · 충전 대기": ["Plugged in · waiting", "電源接続 · 充電待機", "已接电源 · 等待充电"],
        "일반 충전": ["Normal charging", "通常充電", "正常充电"],
        "유지 모드": ["Maintain mode", "維持モード", "保持模式"],
        "퇴근 충전": ["Leave charge", "退勤前充電", "下班前充电"],
        "수동 방전 중": ["Manual discharging", "手動放電中", "手动放电中"],
        "battery CLI 권한 없음": ["No battery CLI permission", "battery CLI の権限なし", "无 battery CLI 权限"],
        "%@시간 %@분": ["%@h %@m", "%@時間%@分", "%@小时%@分"],
        "%@분": ["%@ min", "%@分", "%@分钟"],

        // 일정 충전 (출근·퇴근) · 지금 충전
        "출근": ["Commute", "出勤", "上班"],
        "출근 충전": ["Commute charge", "出勤前充電", "上班前充电"],
        "출근 충전 · 목표 %@%": ["Commute charge · target %@%", "出勤前充電 · 目標 %@%", "上班前充电 · 目标 %@%"],
        "출근 시각": ["Commute time", "出勤時刻", "上班时间"],
        "출근 시각 전에 목표까지 충전합니다. 집에서 전원을 계속 연결해 둘 때 유용합니다.": [
            "Charges to the target before your commute time. Useful when it stays plugged in at home.",
            "出勤時刻の前に目標まで充電します。自宅で電源をつないだままにするときに便利です。",
            "在上班时间前充电到目标。适合在家一直接着电源时使用。"],
        "다음 출근 충전": ["Next commute charge", "次の出勤前充電", "下次上班前充电"],
        "출근 충전 (%@ 까지 %@%)": ["Commute charge (%2$@% by %1$@)", "出勤前充電 (%@までに%@%)", "上班前充电 (%@ 前 %@%)"],
        "충전 시작": ["Charging starts", "充電開始", "开始充电"],
        "지금 충전": ["Charge now", "今すぐ充電", "立即充电"],
        "지금 충전 (출장·외출)": ["Charge now (trip)", "今すぐ充電(出張・外出)", "立即充电(出差·外出)"],
        "지금 충전 · 목표 %@%": ["Charge now · target %@%", "今すぐ充電 · 目標 %@%", "立即充电 · 目标 %@%"],
        "해제": ["Cancel", "解除", "取消"],
        "목표에 도달한 뒤 어댑터를 뽑으면 자동으로 해제됩니다 (최대 24시간)": [
            "Turns off when you unplug after reaching the target (max 24 h).",
            "目標到達後にアダプタを外すと自動で解除されます(最大24時間)。",
            "达到目标后拔下适配器会自动取消(最长 24 小时)。"],
        "macOS 충전 한도가 설정돼 있으면 그 이상은 충전되지 않습니다": [
            "Won't charge past the macOS charge limit if one is set.",
            "macOSの充電上限が設定されている場合、それ以上は充電されません。",
            "如设置了 macOS 充电上限，不会超过该上限。"],

        // 주말 외출 충전 · 출발 시각
        "주말": ["Weekend", "週末", "周末"],
        "주말 외출 충전": ["Weekend outing charge", "週末外出前充電", "周末外出前充电"],
        "주말 외출 충전 · 목표 %@%": ["Weekend outing charge · target %@%", "週末外出前充電 · 目標 %@%", "周末外出前充电 · 目标 %@%"],
        "주말 외출 시각": ["Weekend leave time", "週末の外出時刻", "周末外出时间"],
        "주말 외출 시각 전에 목표까지 충전합니다. 출근과 시각이 다를 때 씁니다.": [
            "Charges to the target before your weekend outing. Use it when the time differs from your commute.",
            "週末の外出時刻の前に目標まで充電します。出勤と時刻が違うときに使います。",
            "在周末外出时间前充电到目标。适用于与上班时间不同的情况。"],
        "다음 주말 외출 충전": ["Next weekend outing charge", "次の週末外出前充電", "下次周末外出前充电"],
        "주말 외출 충전 (%@ 까지 %@%)": ["Weekend outing charge (%2$@% by %1$@)", "週末外出前充電 (%@までに%@%)", "周末外出前充电 (%@ 前 %@%)"],
        "출발": ["Leave", "出発", "出发"],
        "지금": ["Now", "今", "现在"],
        "%@시간 후": ["In %@ h", "%@時間後", "%@ 小时后"],
        "%@ 출발 · %@부터 충전": ["Leaving %@ · charging from %@", "%@出発 · %@から充電", "%@ 出发 · %@ 开始充电"],
        "지금 충전 예약 · %@부터": ["Charge now scheduled · from %@", "今すぐ充電を予約 · %@から", "已预约立即充电 · %@ 开始"],

        "후원하기": ["Support on Ko-fi", "Ko-fiで支援する", "在 Ko-fi 上赞助"],

        // 팝오버
        "사용 기록": ["Usage history", "使用履歴", "使用记录"],
        "세부 사항": ["Details", "詳細", "详情"],
        "배터리": ["Battery", "バッテリー", "电池"],
        "모드": ["Modes", "モード", "模式"],
        "퇴근 충전 · 목표 %@%": ["Leave charge · target %@%", "退勤前充電 · 目標 %@%", "下班前充电 · 目标 %@%"],
        "유지 모드 · %@~%@%": ["Maintain · %@–%@%", "維持モード · %@〜%@%", "保持模式 · %@~%@%"],
        "충전": ["Charging", "充電", "充电"],
        "유지(어댑터 차단)": ["Maintain", "維持(アダプタ遮断)", "保持(断开适配器)"],
        "최근 4시간": ["Last 4 hours", "直近4時間", "最近 4 小时"],
        "공급원": ["Power source", "電源", "电源"],
        "어댑터 %@W (차단 중)": ["Adapter %@W (blocked)", "アダプタ %@W(遮断中)", "适配器 %@W(已断开)"],
        "어댑터 %@W": ["Adapter %@W", "アダプタ %@W", "适配器 %@W"],
        "배터리 전원": ["Battery", "バッテリー電源", "电池供电"],
        "완충까지": ["Until full", "満充電まで", "充满还需"],
        "계산 중": ["Calculating", "計算中", "计算中"],
        "%@%까지": ["To %@%", "%@%まで", "到 %@%"],
        "대기": ["Waiting", "待機", "等待"],
        "남은 사용 시간": ["Time remaining", "残り使用時間", "剩余使用时间"],
        "다음 퇴근 충전": ["Next leave charge", "次の退勤前充電", "下次下班前充电"],
        "어댑터": ["Adapter", "アダプタ", "适配器"],
        "전류": ["Current", "電流", "电流"],
        "전압": ["Voltage", "電圧", "电压"],
        "온도": ["Temp", "温度", "温度"],
        "사이클": ["Cycles", "サイクル", "循环"],
        "macOS 판정": ["macOS condition", "macOS判定", "macOS 判定"],
        "충전 유지": ["Maintain charge", "充電維持", "充电保持"],
        "추천 60": ["Rec. 60", "おすすめ60", "推荐60"],
        "적용": ["Apply", "適用", "适用"],
        "항상": ["Always", "常に", "始终"],
        "덮개 닫혔을 때만": ["Lid closed only", "蓋を閉じたときのみ", "仅合盖时"],
        "전원 연결 시 화면 켜두기": ["Keep display on while plugged in", "電源接続中は画面をつけたまま", "接电源时保持屏幕常亮"],
        "전원 연결 시 화면 켜두기 (화면 자동 꺼짐 방지)": ["Keep display on while plugged in (no automatic display sleep)", "電源接続中は画面をつけたまま(自動消灯しない)", "接电源时保持屏幕常亮(不自动关闭显示器)"],
        "자동 업무 모드": ["Auto work mode", "自動作業モード", "自动工作模式"],
        "클램쉘": ["Clamshell", "クラムシェル", "合盖"],
        "블루투스 입력으로 화면 켜기": ["Bluetooth wake", "Bluetooth入力で画面をオン", "蓝牙输入唤醒屏幕"],
        "권한 필요": ["Permission needed", "権限が必要", "需要权限"],
        "입력 모니터링 권한을 허용해야 동작합니다.": ["Requires Input Monitoring permission.", "入力監視の許可が必要です。", "需要“输入监控”权限。"],
        "설정 열기": ["Open Settings", "設定を開く", "打开设置"],
        "대시보드": ["Dashboard", "ダッシュボード", "仪表盘"],
        "%@% 까지": ["To %@%", "%@%まで", "到 %@%"],
        "수동 방전": ["Manual discharge", "手動放電", "手动放电"],
        "권한 설정 (최초 1회)…": ["Set up permission (once)…", "権限設定(初回のみ)…", "设置权限(仅一次)…"],
        "클램쉘 잠자기 제어(수동 방전·자동 업무 모드)에 필요합니다.": ["Needed to control clamshell sleep (manual discharge, auto work mode).", "クラムシェルのスリープ制御(手動放電・自動作業モード)に必要です。", "用于控制合盖睡眠(手动放电、自动工作模式)。"],
        "목표": ["Target", "目標", "目标"],
        "바꾸면 바로 적용됩니다 (다시 시작 불필요)": ["Applies immediately (no restart)", "変更はすぐ反映(再開不要)", "立即生效(无需重新开始)"],
        "중지": ["Stop", "停止", "停止"],
        "퇴근": ["Leave", "退勤", "下班"],
        "%@분 전부터 충전": ["Charge from %@ min before", "%@分前から充電", "提前 %@ 分钟开始充电"],
        "%@분 전 시작": ["%@ min before", "%@分前開始", "提前 %@ 分钟"],
        "요일": ["Days", "曜日", "星期"],
        "월": ["Mo", "月", "一"],
        "화": ["Tu", "火", "二"],
        "수": ["We", "水", "三"],
        "목": ["Th", "木", "四"],
        "금": ["Fr", "金", "五"],
        "토": ["Sa", "土", "六"],
        "일": ["Su", "日", "日"],
        "%@부터 충전 → %@까지 %@%": ["Charge from %1$@ → %3$@% by %2$@", "%@から充電 → %@までに%@%", "%@ 开始充电 → %@ 前达到 %@%"],
        "요일을 하나 이상 선택하세요": ["Select at least one day", "曜日を1つ以上選択してください", "请至少选择一天"],
        "로그 보기": ["Show log", "ログを表示", "查看日志"],
        "로그인 시 자동 실행": ["Open at login", "ログイン時に起動", "登录时启动"],
        "덮개 닫힌 채 모니터/어댑터를 뽑으면 자동 중지 후 잠자기": ["Unplug monitor/adapter with lid closed → stops and sleeps", "蓋を閉じたままモニタ/アダプタを外すと停止してスリープ", "合盖时拔掉显示器/适配器会停止并睡眠"],
        "종료": ["Quit", "終了", "退出"],
        "언어": ["Language", "言語", "语言"],
        "시스템 설정 따름": ["System default", "システム設定に従う", "跟随系统"],

        // 용량 막대
        "용량": ["Capacity", "容量", "容量"],
        "현재 %@%": ["Now %@%", "現在 %@%", "当前 %@%"],
        "최대 %@": ["Max %@", "最大 %@", "最大 %@"],
        "설계 %@": ["Design %@", "設計 %@", "设计 %@"],
        "배터리 성능(SOH) ": ["Battery health (SOH) ", "バッテリー状態(SOH) ", "电池健康度(SOH) "],
        "열화로 %@% (%@ mAh) 감소": ["%@% lost to wear (%@ mAh)", "劣化で%@%低下 (%@ mAh)", "老化损失 %@% (%@ mAh)"],

        // 대시보드
        "6시간": ["6 hours", "6時間", "6小时"],
        "24시간": ["24 hours", "24時間", "24小时"],
        "7일": ["7 days", "7日", "7天"],
        "30일": ["30 days", "30日", "30天"],
        "충전량": ["Charge", "充電量", "电量"],
        "배터리 성능 (SOH)": ["Battery health (SOH)", "バッテリー状態 (SOH)", "电池健康度 (SOH)"],
        "설계 %@회 기준 %@%": ["%2$@% of %1$@ rated cycles", "設計%@回の%@%", "设计 %@ 次的 %@%"],
        "상태": ["Status", "状態", "状态"],
        "목표 %@%": ["Target %@%", "目標 %@%", "目标 %@%"],
        " · 어댑터 차단": [" · adapter blocked", " · アダプタ遮断", " · 已断开适配器"],
        "배터리 사용": ["On battery", "バッテリー使用", "使用电池"],
        "꽂힘 · 배터리 사용(세일링)": ["Plugged · on battery (sailing)", "接続中 · バッテリー使用(セーリング)", "已接电源 · 使用电池(航行)"],
        "충전 중 %@mA": ["Charging %@ mA", "充電中 %@mA", "充电中 %@mA"],
        "꽂힘 · 충전 안 함": ["Plugged · not charging", "接続中 · 充電なし", "已接电源 · 未充电"],
        "기록이 쌓이는 중입니다 (1분마다 저장)": ["Collecting data (saved every minute)", "記録を収集中です(1分ごとに保存)", "正在记录(每分钟保存)"],
        "기록이 쌓이는 중입니다": ["Collecting data", "記録を収集中です", "正在记录"],
        "시간": ["Time", "時刻", "时间"],
        "유지": ["Maintain", "維持", "保持"],
        "유지 %@%": ["Maintain %@%", "維持 %@%", "保持 %@%"],
        "퇴근 목표 %@%": ["Leave target %@%", "退勤目標 %@%", "下班目标 %@%"],
        "현재 최대 용량 ÷ 설계 용량 · 80% 미만이면 교체 고려": ["Current max ÷ design capacity · consider replacing below 80%", "現在の最大容量 ÷ 設計容量 · 80%未満なら交換を検討", "当前最大容量 ÷ 设计容量 · 低于 80% 时考虑更换"],
        "날짜": ["Date", "日付", "日期"],
        "기준": ["Threshold", "基準", "基准"],
        "충전 유지 모드": ["Charge maintain mode", "充電維持モード", "充电保持模式"],
        "전원이 연결된 동안 배터리를 설정한 수준 근처로 유지합니다. 목표에 닿으면 어댑터를 차단해 배터리로 쓰다가, %@% 내려오면 다시 충전합니다.": [
            "While plugged in, keeps the battery near the set level. At the target the adapter is blocked and the Mac runs on battery; charging resumes after it drops %@%.",
            "電源接続中、バッテリーを設定レベル付近に保ちます。目標に達するとアダプタを遮断してバッテリーで動作し、%@%下がると再び充電します。",
            "接通电源时将电池保持在设定水平附近。达到目标后断开适配器改用电池供电，下降 %@% 后重新充电。"],
        "유지 수준": ["Maintain level", "維持レベル", "保持水平"],
        "추천": ["Recommended", "おすすめ", "推荐"],
        "추천값 60%": ["Recommended 60%", "おすすめ 60%", "推荐 60%"],
        "덮개가 닫혀 있을 때(클램쉘)만 적용": ["Only when the lid is closed (clamshell)", "蓋を閉じているとき(クラムシェル)のみ", "仅在合盖时"],
        "자동 업무 모드 (전원 연결 시 덮개 닫아도 동작, 배터리면 잠자기)": ["Auto work mode (stay awake with lid closed on power, sleep on battery)", "自動作業モード(電源接続時は蓋を閉じても動作、バッテリー時はスリープ)", "自动工作模式(接电源时合盖继续运行，用电池时睡眠)"],
        "퇴근 시각 전에 유지 모드를 잠시 멈추고 목표까지 충전합니다. 퇴근 후 30분이 지나면 다시 유지 모드로 돌아갑니다.": [
            "Pauses maintain mode before your leave time and charges to the target. Maintain mode resumes 30 minutes after leave time.",
            "退勤時刻の前に維持モードを一時停止して目標まで充電します。退勤30分後に維持モードに戻ります。",
            "在下班时间前暂停保持模式并充电到目标。下班 30 分钟后恢复保持模式。"],
        "퇴근 시각": ["Leave time", "退勤時刻", "下班时间"],
        "충전 시작: %@분 전": ["Start charging: %@ min before", "充電開始: %@分前", "开始充电: 提前 %@ 分钟"],
        "충전 목표": ["Charge target", "充電目標", "充电目标"],
        "다음 퇴근: %@ · 충전 시작 %@%@": ["Next leave: %@ · charging starts %@%@", "次の退勤: %@ · 充電開始 %@%@", "下次下班: %@ · 开始充电 %@%@"],
        " · 지금 속도로 %@%까지 약 %@분": [" · about %2$@ min to %1$@% at this rate", " · 今の速度で%@%まで約%@分", " · 按当前速度约 %2$@ 分钟到 %1$@%"],
        "Clamshell Discharge — 배터리 대시보드": ["Clamshell Discharge — Battery Dashboard", "Clamshell Discharge — バッテリーダッシュボード", "Clamshell Discharge — 电池仪表盘"],

        // 메뉴 막대 (우클릭 메뉴, 알림)
        "배터리 %@ · %@": ["Battery %@ · %@", "バッテリー %@ · %@", "电池 %@ · %@"],
        " · 목표 %@%": [" · target %@%", " · 目標 %@%", " · 目标 %@%"],
        "클램쉘 방전 실행 중 → %@%": ["Clamshell discharge running → %@%", "クラムシェル放電中 → %@%", "合盖放电进行中 → %@%"],
        "터미널에서 방전 실행 중": ["Discharge running from Terminal", "ターミナルから放電中", "正在从终端放电"],
        "배터리 대시보드…": ["Battery Dashboard…", "バッテリーダッシュボード…", "电池仪表盘…"],
        "충전 유지 모드 (%@%)": ["Charge maintain (%@%)", "充電維持モード (%@%)", "充电保持模式 (%@%)"],
        "퇴근 충전 (%@ 까지 %@%)": ["Leave charge (%2$@% by %1$@)", "退勤前充電 (%@までに%@%)", "下班前充电 (%@ 前 %@%)"],
        "battery CLI 미설치": ["battery CLI not installed", "battery CLI 未インストール", "未安装 battery CLI"],
        "방전 시작": ["Start discharge", "放電開始", "开始放电"],
        "방전 목표 변경 (지금 %@)": ["Change discharge target (now %@)", "放電目標を変更(現在 %@)", "更改放电目标(当前 %@)"],
        "자동 업무 모드 (전원: 덮개 닫아도 동작 / 배터리: 잠자기)": ["Auto work mode (power: awake lid closed / battery: sleep)", "自動作業モード(電源: 蓋を閉じても動作 / バッテリー: スリープ)", "自动工作模式(电源: 合盖运行 / 电池: 睡眠)"],
        "전원 연결": ["On power", "電源接続", "已接电源"],
        "닫힘": ["closed", "閉", "合上"],
        "열림": ["open", "開", "打开"],
        "차단": ["blocked", "遮断", "阻止"],
        "허용": ["allowed", "許可", "允许"],
        "   지금: %@ · 덮개 %@ · 외장 모니터 %@대 · 잠자기 %@": ["   Now: %@ · lid %@ · %@ external displays · sleep %@", "   現在: %@ · 蓋 %@ · 外部モニタ %@台 · スリープ %@", "   当前: %@ · 盖子 %@ · 外接显示器 %@ 台 · 睡眠 %@"],
        "방전 중지": ["Stop discharge", "放電停止", "停止放电"],
        "방전 시작 실패 — 로그를 확인하세요": ["Failed to start discharge — check the log", "放電を開始できません — ログを確認してください", "放电启动失败 — 请查看日志"],
        "실행 실패: %@": ["Launch failed: %@", "起動失敗: %@", "启动失败: %@"],
        "권한 설정 실패: %@": ["Permission setup failed: %@", "権限設定に失敗: %@", "权限设置失败: %@"],
        "권한 설정 완료": ["Permission set up", "権限設定完了", "权限设置完成"],
        "권한 설정이 적용되지 않았습니다": ["Permission was not applied", "権限設定が反映されていません", "权限未生效"],
        "로그인 항목 설정 실패: %@": ["Login item failed: %@", "ログイン項目の設定に失敗: %@", "登录项设置失败: %@"],
    ]
}
