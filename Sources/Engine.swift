// 충전 유지(세일링) + 퇴근 충전 스케줄 + 기록

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

    /// 자동 업무 모드 (AppDelegate 와 공유)
    @Published var autoMode: Bool { didSet { d.set(autoMode, forKey: "autoMode") } }
    /// 표시 언어: "system" | "ko" | "en" | "ja" | "zh-Hans"
    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    /// 화면이 꺼져 있을 때 블루투스(및 모든) 키보드/마우스 입력으로 화면 켜기
    @Published var hidWake: Bool { didSet { d.set(hidWake, forKey: "hidWake") } }

    let band = 3 // 세일링 폭: 목표에 닿으면 어댑터 차단, 목표-3% 까지 내려오면 다시 충전

    private init() {
        d.register(defaults: [
            "maintainEnabled": false, "maintainLevel": 60, "maintainOnlyClamshell": false,
            "departureEnabled": false, "departureMinutes": 18 * 60, "departureTarget": 100,
            "departureLead": 90, "departureWeekdays": [2, 3, 4, 5, 6], "autoMode": false, "hidWake": true, "language": "system",
        ])
        maintainEnabled = d.bool(forKey: "maintainEnabled")
        maintainLevel = d.integer(forKey: "maintainLevel")
        maintainOnlyClamshell = d.bool(forKey: "maintainOnlyClamshell")
        departureEnabled = d.bool(forKey: "departureEnabled")
        departureMinutes = d.integer(forKey: "departureMinutes")
        departureTarget = d.integer(forKey: "departureTarget")
        departureLead = d.integer(forKey: "departureLead")
        departureWeekdays = Set((d.array(forKey: "departureWeekdays") as? [Int]) ?? [2, 3, 4, 5, 6])
        autoMode = d.bool(forKey: "autoMode")
        hidWake = d.bool(forKey: "hidWake")
        language = d.string(forKey: "language") ?? "system"
    }

    var departureTimeText: String { String(format: "%02d:%02d", departureMinutes / 60, departureMinutes % 60) }
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
    @Published var nextDeparture: Date?
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
    /// 깨우지 않으므로, 이 동안에는 어댑터 차단을 풀어 AC 전원으로 둔다.
    @Published var displaysAsleep = false
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
            self.displaysAsleep = true
            if self.settings.hidWake { HIDWaker.shared.start() }
            // 덮개가 닫혀 있으면 바로 AC 로 돌려서 키보드/마우스로 깨울 수 있게
            if Battery.lidClosed() && Adapter.isBlocked() && !self.manualDischarge() {
                Adapter.setBlocked(false)
                self.adapterBlocked = false
            }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displaysAsleep = false
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
        if Adapter.isBlocked() && !manualDischarge() { Adapter.setBlocked(false) }
    }

    // MARK: 퇴근 스케줄

    /// 오늘(또는 다음) 퇴근 시각
    func departure(after now: Date = Date()) -> Date? {
        guard settings.departureEnabled, !settings.departureWeekdays.isEmpty else { return nil }
        let cal = Calendar.current
        for dayOffset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) else { continue }
            guard settings.departureWeekdays.contains(cal.component(.weekday, from: day)) else { continue }
            let t = day.addingTimeInterval(TimeInterval(settings.departureMinutes * 60))
            if t.addingTimeInterval(30 * 60) > now { return t } // 퇴근 후 30분까지는 '오늘' 로 봄
        }
        return nil
    }

    func inDepartureWindow(_ now: Date = Date()) -> Bool {
        guard let dep = departure(after: now) else { return false }
        let start = dep.addingTimeInterval(-TimeInterval(settings.departureLead * 60))
        return now >= start && now <= dep.addingTimeInterval(30 * 60)
    }

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
        nextDeparture = departure()
        record(b)

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
        if displaysAsleep && Battery.lidClosed() {
            // 클램쉘 + 화면 꺼짐: AC 유지 (깨우기 보장). 화면이 켜지면 다시 유지 모드.
            mode = settings.maintainEnabled ? .maintain : .off
            want = nil
        } else if inDepartureWindow() {
            mode = .departure
            want = settings.departureTarget
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
