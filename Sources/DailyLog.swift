// 일별 배터리 기록 (영구 보관)
//
// 1분 단위 기록(history.csv)은 90일만 남기지만, 하루 한 줄 요약은 계속 쌓는다(10년 ≈ 수백 KB).
// - 로컬: ~/Library/Application Support/ClamshellDischarge/daily.csv (원본)
// - iCloud Drive: ~/Library/Mobile Documents/com~apple~CloudDocs/ClamshellDischarge/<모델>-<기기ID>.csv (복사본)
//   기기마다 자기 파일에만 쓰므로 여러 Mac 이 같은 파일을 고칠 일이 없다. 서버는 쓰지 않는다.
//   기기 ID 는 하드웨어 UUID 를 SHA-256 으로 해시한 앞 8자리(시리얼은 남기지 않음).

import CryptoKit
import Foundation
import IOKit

struct DayRecord: Identifiable {
    let day: String          // yyyy-MM-dd (로컬 날짜)
    var soh: Double
    var cycles: Int
    var maxmAh: Int?
    var designmAh: Int?
    var tempMax: Double?
    var id: String { day }

    var date: Date? { DailyLog.dayFormatter.date(from: day) }

    var line: String {
        [day, String(format: "%.2f", soh), "\(cycles)",
         maxmAh.map(String.init) ?? "", designmAh.map(String.init) ?? "",
         tempMax.map { String(format: "%.1f", $0) } ?? ""].joined(separator: ",")
    }

    init(day: String, soh: Double, cycles: Int, maxmAh: Int? = nil, designmAh: Int? = nil, tempMax: Double? = nil) {
        self.day = day; self.soh = soh; self.cycles = cycles
        self.maxmAh = maxmAh; self.designmAh = designmAh; self.tempMax = tempMax
    }

    init?(line: Substring) {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 3, DailyLog.dayFormatter.date(from: f[0]) != nil,
              let s = Double(f[1]), let c = Int(f[2]) else { return nil }
        day = f[0]; soh = s; cycles = c
        maxmAh = f.count > 3 ? Int(f[3]) : nil
        designmAh = f.count > 4 ? Int(f[4]) : nil
        tempMax = f.count > 5 ? Double(f[5]) : nil
    }
}

enum DailyLog {
    static let header = "date,soh_percent,cycles,max_mAh,design_mAh,temp_max_c"
    static let localPath = "\(History.dir)/daily.csv"
    static let iCloudRoot = "\(home)/Library/Mobile Documents/com~apple~CloudDocs"
    static var iCloudDir: String { "\(iCloudRoot)/ClamshellDischarge" }
    static var iCloudAvailable: Bool { FileManager.default.fileExists(atPath: iCloudRoot) }
    static var iCloudPath: String { "\(iCloudDir)/\(deviceFileName).csv" }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 오늘 본 가장 높은 배터리 온도 (날이 바뀌면 초기화)
    private static var tempDay = ""
    private static var tempMaxToday: Double?

    static func noteTemperature(_ c: Double?) {
        guard let c else { return }
        let today = dayFormatter.string(from: Date())
        if today != tempDay { tempDay = today; tempMaxToday = nil }
        tempMaxToday = max(tempMaxToday ?? c, c)
    }

    // MARK: 기기 식별

    static let model: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let s = String(cString: buf)
        return s.isEmpty ? "Mac" : s
    }()

    static let deviceID: String = {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(entry) }
        let uuid = (IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String) ?? Host.current().localizedName ?? "unknown"
        let digest = SHA256.hash(data: Data(uuid.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }()

    static var deviceFileName: String { "\(model.replacingOccurrences(of: ",", with: "_"))-\(deviceID)" }

    // MARK: 읽기 / 쓰기

    static func read(_ path: String) -> [DayRecord] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { $0.hasPrefix("#") ? nil : DayRecord(line: $0) }
    }

    static func load() -> [DayRecord] { read(localPath) }

    private static func text(_ records: [DayRecord]) -> String {
        let info = "# Clamshell Discharge daily battery log · model=\(model) · device=\(deviceID)"
        return ([info, header] + records.map(\.line)).joined(separator: "\n") + "\n"
    }

    /// 1분 기록에서 하루 요약을 만들어 영구 기록에 합치고, 켜져 있으면 iCloud Drive 에도 복사한다.
    static func update(samples: [Sample], snapshot b: BatterySnapshot, iCloud: Bool) {
        var byDay = Dictionary(uniqueKeysWithValues: load().map { ($0.day, $0) })

        // 같은 기기의 iCloud 복사본에만 있는 날(앱 재설치·초기화 후)은 되살린다
        if iCloud && iCloudAvailable {
            for r in read(iCloudPath) where byDay[r.day] == nil { byDay[r.day] = r }
        }

        let groups = Dictionary(grouping: samples.filter { $0.soh > 0 }) { dayFormatter.string(from: $0.date) }
        for (day, s) in groups {
            var r = byDay[day] ?? DayRecord(day: day, soh: 0, cycles: 0)
            r.soh = s.map(\.soh).reduce(0, +) / Double(s.count)
            r.cycles = s.map(\.cycles).max() ?? r.cycles
            byDay[day] = r
        }

        // 오늘 줄: 지금 값으로 용량·온도 채우기
        let today = dayFormatter.string(from: Date())
        if b.soh > 0 {
            var r = byDay[today] ?? DayRecord(day: today, soh: b.soh, cycles: b.cycles)
            r.cycles = max(r.cycles, b.cycles)
            r.maxmAh = b.rawMax
            r.designmAh = b.design
            if tempDay == today, let t = tempMaxToday { r.tempMax = max(r.tempMax ?? t, t) }
            byDay[today] = r
        }

        let records = byDay.values.sorted { $0.day < $1.day }
        guard !records.isEmpty else { return }
        let out = text(records)
        try? FileManager.default.createDirectory(atPath: History.dir, withIntermediateDirectories: true)
        try? out.write(toFile: localPath, atomically: true, encoding: .utf8)

        if iCloud && iCloudAvailable {
            try? FileManager.default.createDirectory(atPath: iCloudDir, withIntermediateDirectories: true)
            try? out.write(toFile: iCloudPath, atomically: true, encoding: .utf8)
        }
    }
}
