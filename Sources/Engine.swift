// 충전 유지(세일링) + 일정 충전(출근·퇴근) + 지금 충전(출장) + 기록

import Cocoa
import Combine

// MARK: - 설정

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// 유지 모드: 전원 연결 중 배터리를 maintainLevel 근처로 유지
    @Published var maintainEnabled: Bool { didSet { d.set(maintainEnabled, forKey: "maintainEnabled") } }
    /// 유지 수준 60~100 (추천 60)
    @Published var maintainLevel: Int { didSet { d.set(maintainLevel, forKey: "maintainLevel") } }
    /// 덮개 닫혔을 때(클램쉘)만 유지 모드 적용
    @Published var maintainOnlyClamshell: Bool { didSet { d.set(maintainOnlyClamshell, forKey: "maintainOnlyClamshell") } }

    /// 퇴근 충전: 퇴근 시각 전에 목표까지 충전
    @Published var departureEnabled: Bool { didSet { d.set(departureEnabled, forKey: "departureEnabled") } }
    @Published var departureMinutes: Int { didSet { d.set(departureMinutes, forKey: "departureMinutes") } } // 자정 기준 분 (18:00 = 1080)
    @Published var departureTarget: Int { didSet { d.set(departureTarget, forKey: "departureTarget") } }
    @Published var departureLead: Int { didSet { d.set(departureLead, forKey: "departureLead") } }         // 몇 분 전부터 충전
    @Published var departureWeekdays: Set<Int> { didSet { d.set(Array(departureWeekdays), forKey: "departureWeekdays") } } // Calendar weekday (1=일 … 7=토)

    /// 출근 충전: 출근 시각 전에 목표까지 (집에서 밤새 전원 연결해 둘 때)
    @Published var commuteEnabled: Bool { didSet { d.set(commuteEnabled, forKey: "commuteEnabled") } }
    @Published var commuteMinutes: Int { didSet { d.set(commuteMinutes, forKey: "commuteMinutes") } }
    @Published var commuteTarget: Int { didSet { d.set(commuteTarget, forKey: "commuteTarget") } }
    @Published var commuteLead: Int { didSet { d.set(commuteLead, forKey: "commuteLead") } }
    @Published var commuteWeekdays: Set<Int> { didSet { d.set(Array(commuteWeekdays), forKey: "commuteWeekdays") } }

    /// 주말 외출 충전: 출근과 시각이 다른 주말용 일정
    @Published var weekendEnabled: Bool { didSet { d.set(weekendEnabled, forKey: "weekendEnabled") } }
    @Published var weekendMinutes: Int { didSet { d.set(weekendMinutes, forKey: "weekendMinutes") } }
    @Published var weekendTarget: Int { didSet { d.set(weekendTarget, forKey: "weekendTarget") } }
    @Published var weekendLead: Int { didSet { d.set(weekendLead, forKey: "weekendLead") } }
    @Published var weekendWeekdays: Set<Int> { didSet { d.set(Array(weekendWeekdays), forKey: "weekendWeekdays") } }

    /// 지금 충전의 출발 시각 (epoch 초). 0 이면 바로 충전. 미래면 그 시각에 맞춰 늦게 시작
    @Published var oneShotDepartAt: Double { didSet { d.set(oneShotDepartAt, forKey: "oneShotDepartAt") } }

    /// 지금 충전 (출장·외출): 0 이면 꺼짐. 목표 도달 후 어댑터를 뽑거나 24시간이 지나면 해제
    @Published var oneShotTarget: Int { didSet { d.set(oneShotTarget, forKey: "oneShotTarget") } }
    @Published var oneShotSince: Double { didSet { d.set(oneShotSince, forKey: "oneShotSince") } }

    /// 자동 업무 모드 (AppDelegate 와 공유)
    @Published var autoMode: Bool { didSet { d.set(autoMode, forKey: "autoMode") } }
    /// 표시 언어: "system" | "ko" | "en" | "ja" | "zh-Hans"
    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    /// 화면이 꺼져 있을 때 블루투스(및 모든) 키보드/마우스 입력으로 화면 켜기
    @Published var hidWake: Bool { didSet { d.set(hidWake, forKey: "hidWake") } }
    /// 전원(어댑터) 연결 중에는 맥이 잠자기에 들어가지 않게 (세일링 중 포함, 화면은 꺼질 수 있음)
    @Published var keepDisplayOnAC: Bool { didSet { d.set(keepDisplayOnAC, forKey: "keepDisplayOnAC") } }
    /// 메뉴 막대에 배터리 온도 표시
    @Published var showTempInMenuBar: Bool { didSet { d.set(showTempInMenuBar, forKey: "showTempInMenuBar") } }

    let band = 3 // 세일링 폭: 목표에 닿으면 어댑터 차단, 목표-3% 까지 내려오면 다시 충전

    private init() {
        d.register(defaults: [
            "maintainEnabled": false, "maintainLevel": 60, "maintainOnlyClamshell": false,
            "departureEnabled": false, "departureMinutes": 18 * 60, "departureTarget": 100,
            "departureLead": 90, "departureWeekdays": [2, 3, 4, 5, 6],
            "commuteEnabled": false, "commuteMinutes": 8 * 60, "commuteTarget": 80, "commuteLead": 90,
            "commuteWeekdays": [2, 3, 4, 5, 6], "oneShotTarget": 0, "oneShotSince": 0.0, "oneShotDepartAt": 0.0,
            "weekendEnabled": false, "weekendMinutes": 10 * 60, "weekendTarget": 80, "weekendLead": 60, "weekendWeekdays": [7, 1], "autoMode": false, "hidWake": true, "keepDisplayOnAC": true, "showTempInMenuBar": true, "language": "system",
        ])
        maintainEnabled = d.bool(forKey: "maintainEnabled")
        maintainLevel = d.integer(forKey: "maintainLevel")
        maintainOnlyClamshell = d.bool(forKey: "maintainOnlyClamshell")
        departureEnabled = d.bool(forKey: "departureEnabled")
        departureMinutes = d.integer(forKey: "departureMinutes")
        departureTarget = d.integer(forKey: "departureTarget")
        departureLead = d.integer(forKey: "departureLead")
        departureWeekdays = Set((d.array(forKey: "departureWeekdays") as? [Int]) ?? [2, 3, 4, 5, 6])
        commuteEnabled = d.bool(forKey: "commuteEnabled")
        commuteMinutes = d.integer(forKey: "commuteMinutes")
        commuteTarget = d.integer(forKey: "commuteTarget")
        commuteLead = d.integer(forKey: "commuteLead")
        commuteWeekdays = Set((d.array(forKey: "commuteWeekdays") as? [Int]) ?? [2, 3, 4, 5, 6])
        weekendEnabled = d.bool(forKey: "weekendEnabled")
        weekendMinutes = d.integer(forKey: "weekendMinutes")
        weekendTarget = d.integer(forKey: "weekendTarget")
        weekendLead = d.integer(forKey: "weekendLead")
        weekendWeekdays = Set((d.array(forKey: "weekendWeekdays") as? [Int]) ?? [7, 1])
        oneShotDepartAt = d.double(forKey: "oneShotDepartAt")
        oneShotTarget = d.integer(forKey: "oneShotTarget")
        oneShotSince = d.double(forKey: "oneShotSince")
        autoMode = d.bool(forKey: "autoMode")
        hidWake = d.bool(forKey: "hidWake")
        keepDisplayOnAC = d.bool(forKey: "keepDisplayOnAC")
        showTempInMenuBar = d.bool(forKey: "showTempInMenuBar")
        language = d.string(forKey: "language") ?? "system"
    }

    var departureTimeText: String { String(format: "%02d:%02d", departureMinutes / 60, departureMinutes % 60) }
    var commuteTimeText: String { String(format: "%02d:%02d", commuteMinutes / 60, commuteMinutes % 60) }

    /// 일정 하나의 값을 화면에서 같은 코드로 다루기 위한 묶음
    func schedule(_ k: ScheduleKind) -> ScheduleValues {
        switch k {
        case .commute: return ScheduleValues(enabled: commuteEnabled, minutes: commuteMinutes, target: commuteTarget, lead: commuteLead, weekdays: commuteWeekdays)
        case .leave: return ScheduleValues(enabled: departureEnabled, minutes: departureMinutes, target: departureTarget, lead: departureLead, weekdays: departureWeekdays)
        case .weekend: return ScheduleValues(enabled: weekendEnabled, minutes: weekendMinutes, target: weekendTarget, lead: weekendLead, weekdays: weekendWeekdays)
        }
    }

    func update(_ k: ScheduleKind, _ change: (inout ScheduleValues) -> Void) {
        var v = schedule(k)
        change(&v)
        switch k {
        case .commute:
            if commuteEnabled != v.enabled { commuteEnabled = v.enabled }
            if commuteMinutes != v.minutes { commuteMinutes = v.minutes }
            if commuteTarget != v.target { commuteTarget = v.target }
            if commuteLead != v.lead { commuteLead = v.lead }
            if commuteWeekdays != v.weekdays { commuteWeekdays = v.weekdays }
        case .leave:
            if departureEnabled != v.enabled { departureEnabled = v.enabled }
            if departureMinutes != v.minutes { departureMinutes = v.minutes }
            if departureTarget != v.target { departureTarget = v.target }
            if departureLead != v.lead { departureLead = v.lead }
            if departureWeekdays != v.weekdays { departureWeekdays = v.weekdays }
        case .weekend:
            if weekendEnabled != v.enabled { weekendEnabled = v.enabled }
            if weekendMinutes != v.minutes { weekendMinutes = v.minutes }
            if weekendTarget != v.target { weekendTarget = v.target }
            if weekendLead != v.lead { weekendLead = v.lead }
            if weekendWeekdays != v.weekdays { weekendWeekdays = v.weekdays }
        }
    }

    /// target 까지 충전. inHours 시간 뒤 출발이면 그 시각에 맞춰 늦게 시작 (0 = 바로)
    func startOneShot(_ target: Int, inHours: Double? = nil) {
        oneShotSince = Date().timeIntervalSince1970
        if let h = inHours { oneShotDepartAt = h > 0 ? Date().addingTimeInterval(h * 3600).timeIntervalSince1970 : 0 }
        oneShotTarget = target
    }

    /// 출발까지 남은 시간 선택 (켜져 있으면 바로 반영)
    func setOneShotDeparture(inHours h: Double) {
        oneShotDepartAt = h > 0 ? Date().addingTimeInterval(h * 3600).timeIntervalSince1970 : 0
    }

    var oneShotDeparture: Date? { oneShotDepartAt > Date().timeIntervalSince1970 - 3600 && oneShotDepartAt > 0 ? Date(timeIntervalSince1970: oneShotDepartAt) : nil }

    func cancelOneShot() { oneShotTarget = 0 }
}

enum ScheduleKind: String, CaseIterable, Identifiable {
    case commute, leave, weekend
    var id: String { rawValue }
    /// 이름 (번역 키)
    var title: String {
        switch self { case .commute: tr("출근 충전"); case .leave: tr("퇴근 충전"); case .weekend: tr("주말 외출 충전") }
    }
    var shortTitle: String {
        switch self { case .commute: tr("출근"); case .leave: tr("퇴근"); case .weekend: tr("주말") }
    }
    /// 시각 메뉴에 보여줄 자주 쓰는 시각
    var presets: [Int] {
        switch self {
        case .commute: [6 * 60 + 30, 7 * 60, 7 * 60 + 30, 8 * 60, 8 * 60 + 30, 9 * 60, 9 * 60 + 30]
        case .leave: [16 * 60 + 30, 17 * 60, 17 * 60 + 30, 18 * 60, 18 * 60 + 30, 19 * 60, 20 * 60]
        case .weekend: [8 * 60, 9 * 60, 10 * 60, 11 * 60, 12 * 60, 13 * 60, 14 * 60]
        }
    }
}

struct ScheduleValues: Equatable {
    var enabled: Bool
    var minutes: Int        // 자정 기준 분
    var target: Int
    var lead: Int           // 몇 분 전부터 충전
    var weekdays: Set<Int>  // Calendar weekday (1=일 … 7=토)
    var timeText: String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}

// MARK: - 기록

struct Sample: Identifiable {
    let date: Date
    let percent: Int
    let soh: Double
    let cycles: Int
    let adapterBlocked: Bool
    let charging: Bool
    var id: Date { date }
}

enum History {
    static let dir = "\(home)/Library/Application Support/ClamshellDischarge"
    static let path = "\(dir)/history.csv"
    static let keepDays: Double = 90

    static func load() -> [Sample] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let cutoff = Date().addingTimeInterval(-keepDays * 86400)
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: ",")
            guard f.count >= 6, let t = Double(f[0]), let p = Int(f[1]), let s = Double(f[2]), let c = Int(f[3]) else { return nil }
            let date = Date(timeIntervalSince1970: t)
            guard date >= cutoff else { return nil }
            return Sample(date: date, percent: p, soh: s, cycles: c, adapterBlocked: f[4] == "1", charging: f[5] == "1")
        }
    }

    static func append(_ s: Sample) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let line = String(format: "%.0f,%d,%.2f,%d,%d,%d\n", s.date.timeIntervalSince1970, s.percent, s.soh, s.cycles, s.adapterBlocked ? 1 : 0, s.charging ? 1 : 0)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// 오래된 줄을 잘라 파일을 다시 씀
    static func compact(_ samples: [Sample]) {
        let text = samples.map {
            String(format: "%.0f,%d,%.2f,%d,%d,%d", $0.date.timeIntervalSince1970, $0.percent, $0.soh, $0.cycles, $0.adapterBlocked ? 1 : 0, $0.charging ? 1 : 0)
        }.joined(separator: "\n") + "\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - 엔진

enum ChargeMode: String {
    case off = "일반 충전"
    case battery = "배터리 사용 중"
    case maintain = "유지 모드"
    case departure = "퇴근 충전"
    case commute = "출근 충전"
    case oneShot = "지금 충전"
    case weekend = "주말 외출 충전"
    case manual = "수동 방전 중"
    case unavailable = "battery CLI 권한 없음"

    var label: String { trKey(rawValue) }
}

final class Engine: ObservableObject {
    static let shared = Engine()
    let settings = Settings.shared

    @Published var snapshot = Battery.read() ?? BatterySnapshot()
    @Published var samples: [Sample] = History.load()
    @Published var mode: ChargeMode = .off
    @Published var target: Int?          // 지금 적용 중인 목표 %
    @Published var adapterBlocked = Adapter.isBlocked()
    @Published var condition = "…"
    @Published var nextDeparture: Date?      // 다음 퇴근 충전 시각
    @Published var nextCommute: Date?        // 다음 출근 충전 시각
    @Published var nextTimes: [ScheduleKind: Date] = [:]
    /// 지금 충전을 출발 시각에 맞춰 늦게 시작할 때, 충전을 시작할 시각 (그 전까지는 유지 모드)
    @Published var oneShotStartAt: Date?
    /// 수동 방전 상태 (AppDelegate 타이머가 갱신; 뷰는 이 값만 읽음)
    @Published var manualRunning = false
    @Published var manualTarget: Int?
    @Published var permissionReady = FileManager.default.fileExists(atPath: "/etc/sudoers.d/clamshell-discharge")

    /// 팝오버가 열려 있는 동안 자주 호출: 표시용 값만 갱신 (제어 로직은 tick)
    func refreshLive() {
        if let b = Battery.read() { snapshot = b }
        adapterBlocked = Adapter.isBlocked()
    }

    /// 수동 방전 스크립트가 도는 중인지 (AppDelegate 가 알려줌)
    var manualDischarge: () -> Bool = { false }

    private var timer: Timer?
    /// 디스플레이가 잠든 상태. 덮개 닫힘 + 배터리 전원이면 macOS 가 USB 키보드/마우스로 화면을
    /// 깨우지 않는다. 입력 모니터링 권한이 있으면 앱이 입력을 직접 감지하므로 차단을 유지하고
    /// (밤새 60%→80%→60% 왕복을 막음), 권한이 없을 때만 어댑터 차단을 풀어 AC 전원으로 둔다.
    @Published var displaysAsleep = false
    /// 화면이 꺼진 동안 입력이 와서 깨우는 중 (화면이 켜질 때까지 AC 유지)
    var wakeRequested = false
    private var lastSampleAt = Date.distantPast
    private var bag = Set<AnyCancellable>()

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        let nc = NSWorkspace.shared.notificationCenter
        // 잠자기 동안 어댑터가 차단돼 있으면 배터리가 계속 닳으므로 잠들기 전에 해제
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            if Adapter.isBlocked() { Adapter.setBlocked(false) }
            self?.adapterBlocked = false
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.tick() }
        }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            wakeLog("displays slept (lid closed: \(Battery.lidClosed()), blocked: \(Adapter.isBlocked()), input access: \(HIDWaker.shared.accessGranted))")
            self.displaysAsleep = true
            if HIDWaker.shared.accessGranted {
                // 입력을 앱이 감지 → 차단 유지 (첫 입력 때 AC 로 바꾸고 화면을 켬)
                HIDWaker.shared.start()
            } else if Battery.lidClosed() && Adapter.isBlocked() && !self.manualDischarge() {
                // 권한이 없으면 깨우기를 보장하기 위해 바로 AC 로
                Adapter.setBlocked(false)
                self.adapterBlocked = false
            }
        }
        // 화면이 꺼진 동안 키보드/마우스 입력이 오면: 덮개 닫힘 + 차단 중이면 먼저 AC 로 전환
        // (배터리 전원 클램쉘에서는 macOS 가 화면을 켜지 않으므로), 그다음 HIDWaker 가 화면을 켬
        // 입력 직후엔 아직 배터리로 인식돼 화면이 안 켜지므로, AC 로 바뀌는 걸 기다렸다가 한 번 더 깨운다.
        // 화면이 켜질 때까지 tick 이 다시 차단하지 않도록 wakeRequested 로 붙잡아 둔다.
        HIDWaker.shared.onInput = { [weak self] in
            guard let self, self.displaysAsleep, !self.manualDischarge() else { return }
            guard Battery.lidClosed() && Adapter.isBlocked() else { return }
            wakeLog("input while displays asleep → unblock adapter")
            self.wakeRequested = true
            Adapter.setBlocked(false)
            self.adapterBlocked = false
            DispatchQueue.global().async {
                var ac = false
                for _ in 0..<16 {
                    if sh("pmset -g batt | head -1").1.contains("AC Power") { ac = true; break }
                    Thread.sleep(forTimeInterval: 0.5)
                }
                DispatchQueue.main.async {
                    wakeLog("AC \(ac ? "confirmed" : "not confirmed") → declare user activity")
                    HIDWaker.shared.declareActivity()
                }
            }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            wakeLog("displays woke")
            self?.displaysAsleep = false
            self?.wakeRequested = false
            HIDWaker.shared.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.tick() }
        }
        // 설정이 바뀌면 바로 반영
        settings.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &bag)
        // 블루투스 깨우기가 켜져 있으면 처음 한 번 입력 모니터링 권한 요청
        if settings.hidWake && !HIDWaker.shared.accessGranted { HIDWaker.shared.requestAccess() }
        DispatchQueue.global().async {
            let c = Battery.condition()
            DispatchQueue.main.async { self.condition = c }
        }
        tick()
    }

    /// 앱 종료 시: 어댑터 차단을 남기지 않음
    func shutdown() {
        guard Adapter.isBlocked() && !manualDischarge() else { return }
        Adapter.setBlocked(false)
        // 어댑터가 꽂혀 있으면 macOS 가 AC 전원으로 바꿔 인식할 때까지 최대 5초 기다림
        guard (Battery.pdContractWatts() ?? 0) > 0 else { return }
        for _ in 0..<20 {
            if sh("pmset -g batt | head -1").1.contains("AC Power") { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    // MARK: 일정 (출근·퇴근)

    /// 일정의 오늘(또는 다음) 시각. 시각 후 30분까지는 '오늘' 로 봄
    func nextTime(_ k: ScheduleKind, after now: Date = Date()) -> Date? {
        let v = settings.schedule(k)
        guard v.enabled, !v.weekdays.isEmpty else { return nil }
        let cal = Calendar.current
        for dayOffset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) else { continue }
            guard v.weekdays.contains(cal.component(.weekday, from: day)) else { continue }
            let t = day.addingTimeInterval(TimeInterval(v.minutes * 60))
            if t.addingTimeInterval(30 * 60) > now { return t }
        }
        return nil
    }

    func inWindow(_ k: ScheduleKind, _ now: Date = Date()) -> Bool {
        guard let t = nextTime(k, after: now) else { return false }
        let start = t.addingTimeInterval(-TimeInterval(settings.schedule(k).lead * 60))
        return now >= start && now <= t.addingTimeInterval(30 * 60)
    }

    /// 지금 충전 구간인 일정 (여럿이면 목표가 높은 쪽)
    func activeSchedule(_ now: Date = Date()) -> ScheduleKind? {
        ScheduleKind.allCases.filter { inWindow($0, now) }.max { settings.schedule($0).target < settings.schedule($1).target }
    }

    // 예전 이름 유지 (대시보드 등)
    func departure(after now: Date = Date()) -> Date? { nextTime(.leave, after: now) }
    func inDepartureWindow(_ now: Date = Date()) -> Bool { inWindow(.leave, now) }

    /// 현재 충전 속도로 목표까지 걸릴 대략적인 분 (충전 중일 때만)
    func minutesToCharge(to target: Int) -> Int? {
        let b = snapshot
        guard b.amperage > 100, b.rawMax > 0, target > b.percent else { return nil }
        let needed = Double(target - b.percent) / 100 * Double(b.rawMax)
        return Int(needed / Double(b.amperage) * 60)
    }

    // MARK: 주기 작업

    func tick() {
        guard let b = Battery.read() else { return }
        snapshot = b
        nextDeparture = nextTime(.leave)
        nextCommute = nextTime(.commute)
        nextTimes = Dictionary(uniqueKeysWithValues: ScheduleKind.allCases.compactMap { k in nextTime(k).map { (k, $0) } })
        record(b)
        updateOneShot(b)

        if manualDischarge() { mode = .manual; target = nil; adapterBlocked = Adapter.isBlocked(); return }
        guard Adapter.available else { mode = .unavailable; target = nil; return }

        // 어댑터가 실제로 뽑혀 있으면 차단 해제만
        guard b.plugged else {
            if Adapter.isBlocked() { Adapter.setBlocked(false) }
            adapterBlocked = false
            mode = .battery; target = nil
            return
        }

        var want: Int?
        if displaysAsleep && Battery.lidClosed() && (wakeRequested || !HIDWaker.shared.accessGranted) {
            // 클램쉘 + 화면 꺼짐 + 입력 모니터링 권한 없음: AC 유지 (깨우기 보장). 화면이 켜지면 다시 유지 모드.
            mode = settings.maintainEnabled ? .maintain : .off
            want = nil
        } else if settings.oneShotTarget > 0 && oneShotShouldCharge(b) {
            mode = .oneShot
            want = settings.oneShotTarget
        } else if let k = activeSchedule() {
            mode = k == .commute ? .commute : k == .weekend ? .weekend : .departure
            want = settings.schedule(k).target
        } else if settings.maintainEnabled && (!settings.maintainOnlyClamshell || Battery.lidClosed()) {
            mode = .maintain
            want = settings.maintainLevel
        } else {
            mode = .off
        }
        target = want

        let blocked = Adapter.isBlocked()
        if let t = want, t < 100 {
            if b.percent >= t && !blocked {
                Adapter.setBlocked(true)        // 목표 도달 → 어댑터 차단, 배터리로 사용
            } else if b.percent <= t - settings.band && blocked {
                Adapter.setBlocked(false)       // 목표-폭 이하 → 다시 충전
            }
        } else if blocked {
            Adapter.setBlocked(false)           // 목표 100% 이거나 유지 꺼짐 → 정상 충전
        }
        adapterBlocked = Adapter.isBlocked()
    }

    // MARK: 지금 충전 시작 시각 계산

    /// 기록에서 배운 이 Mac 의 충전 속도 (%/분, 80% 아래 구간). 기록이 부족하면 1.0
    func learnedChargeRate() -> Double {
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        let s = samples.filter { $0.date >= cutoff }
        var rates: [Double] = []
        for (a, b) in zip(s, s.dropFirst()) where a.charging && b.charging && b.percent > a.percent && b.percent <= 80 {
            let mins = b.date.timeIntervalSince(a.date) / 60
            if mins > 0.5 && mins < 10 { rates.append(Double(b.percent - a.percent) / mins) }
        }
        guard rates.count >= 5 else { return 1.0 }
        let sorted = rates.sorted()
        return min(3.0, max(0.3, sorted[sorted.count / 2]))  // 중앙값
    }

    /// from% → to% 충전에 걸릴 대략적인 분. 80% 위는 충전이 느려져 절반 속도로 계산
    func estimateMinutes(from: Int, to: Int) -> Int {
        guard to > from else { return 0 }
        let r = learnedChargeRate()
        var m = 0.0
        for p in from..<to { m += p < 80 ? 1 / r : 2 / r }
        return Int(m.rounded(.up))
    }

    /// 출발 시각이 정해져 있으면, (출발 − 예상 충전 시간 − 여유 15분) 이후에만 충전
    private func oneShotShouldCharge(_ b: BatterySnapshot) -> Bool {
        guard let dep = settings.oneShotDeparture, dep > Date() else { oneShotStartAt = nil; return true }
        let start = dep.addingTimeInterval(-TimeInterval((estimateMinutes(from: b.percent, to: settings.oneShotTarget) + 15) * 60))
        oneShotStartAt = start
        return Date() >= start
    }

    /// 지금 충전 자동 해제: 목표에 닿은 뒤 어댑터를 뽑았거나(가지고 나감) 24시간이 지나면
    private var oneShotReached = false
    private func updateOneShot(_ b: BatterySnapshot) {
        guard settings.oneShotTarget > 0 else { oneShotReached = false; return }
        if Date().timeIntervalSince1970 - settings.oneShotSince > 24 * 3600 { settings.cancelOneShot(); return }
        if b.percent >= min(settings.oneShotTarget, 100) - 1 { oneShotReached = true }
        if oneShotReached && !b.plugged { settings.cancelOneShot(); oneShotReached = false }
    }

    private func record(_ b: BatterySnapshot) {
        guard Date().timeIntervalSince(lastSampleAt) >= 55 else { return }
        lastSampleAt = Date()
        let s = Sample(date: Date(), percent: b.percent, soh: b.soh, cycles: b.cycles,
                       adapterBlocked: adapterBlocked, charging: b.isCharging)
        samples.append(s)
        History.append(s)
        let cutoff = Date().addingTimeInterval(-History.keepDays * 86400)
        if let first = samples.first, first.date < cutoff {
            samples.removeAll { $0.date < cutoff }
            History.compact(samples)
        }
    }
}


/// 화면 깨우기 진단 기록: ~/Library/Logs/ClamshellDischarge.log
func wakeLog(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ClamshellDischarge.log")
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}
