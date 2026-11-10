// 어댑터 식별
//
// - Apple 정품 어댑터는 이름·시리얼·모델을 알려 준다 → 시리얼로 정확히 구분.
// - 호환(타사) 어댑터는 USB-C PD 전압 목록(PDO)과 출력만 알 수 있다 → "전압 목록" 조합으로 구분
//   (같은 모델끼리는 구분 불가). 처음 보는 조합이면 "처음 연결", 본 적 있으면 "사용한 적 있음".
// - 알려 온 최대 출력보다 협상된 출력이 크게 낮으면 "연결 약함" (케이블·접촉 문제일 때가 많음).
// 기록은 이 Mac 의 UserDefaults 에만 저장한다.

import Foundation

struct AdapterInfo: Equatable {
    var name: String?
    var serial: String?
    var model: String?
    var watts = 0                 // 지금 협상된 출력
    var millivolts = 0
    var milliamps = 0
    var pdos: [[Int]] = []        // [[mV, mA], ...] 어댑터가 알려 온 전압 목록

    var isApple: Bool { (serial?.isEmpty == false) || (name?.contains("Power Adapter") ?? false) }

    /// 어댑터가 낼 수 있다고 알려 온 최대 출력 (W)
    var maxAdvertised: Int { pdos.map { $0[0] * $0[1] / 1_000_000 }.max() ?? watts }

    /// 같은 어댑터를 알아보는 열쇠
    var fingerprint: String {
        if isApple { return "apple:" + (serial ?? name ?? "unknown") }
        return "pdo:" + pdos.map { "\($0[0] / 1000)V\($0[1])" }.joined(separator: ",")
    }

    /// 화면용 이름: "Apple 30W" / "호환 65W"
    var title: String {
        if isApple { return tr("Apple 정품 \(maxAdvertised)W") }
        return tr("호환 \(maxAdvertised)W")
    }

    /// 협상된 출력이 알려 온 최대치의 70% 미만이면 연결이 약한 것 (예: 65W 어댑터인데 15W)
    var weak: Bool { maxAdvertised >= 30 && watts > 0 && Double(watts) < Double(maxAdvertised) * 0.7 }

    var voltageText: String { String(format: "%.0fV × %.2fA", Double(millivolts) / 1000, Double(milliamps) / 1000) }

    /// ioreg AppleSmartBattery 출력에서 AdapterDetails { ... } 를 읽는다 (중첩된 UsbHvcMenu 포함)
    static func parse(_ out: String) -> AdapterInfo? {
        guard let start = out.range(of: "\"AdapterDetails\" = {") else { return nil }
        var depth = 0
        var end = start.upperBound
        var i = out.index(before: start.upperBound)
        while i < out.endIndex {
            let c = out[i]
            if c == "{" { depth += 1 }
            if c == "}" { depth -= 1; if depth == 0 { end = out.index(after: i); break } }
            i = out.index(after: i)
        }
        let s = String(out[start.lowerBound..<end])

        func str(_ key: String) -> String? {
            guard let r = s.range(of: "\"\(key)\"=\"[^\"]*\"", options: .regularExpression) else { return nil }
            let v = s[r].split(separator: "=", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (v?.isEmpty ?? true) ? nil : v
        }
        func num(_ key: String, in t: String) -> Int? {
            guard let r = t.range(of: "\"\(key)\"=[0-9]+", options: .regularExpression) else { return nil }
            return Int(t[r].split(separator: "=").last ?? "")
        }

        var a = AdapterInfo()
        a.name = str("Name")
        a.serial = str("SerialString")
        a.model = str("Model")
        // 중첩 목록을 빼고 맨 바깥 값만 읽기
        let top = s.components(separatedBy: "\"UsbHvcMenu\"").first ?? s
        a.watts = num("Watts", in: top) ?? 0
        a.millivolts = num("AdapterVoltage", in: top) ?? 0
        a.milliamps = num("Current", in: top) ?? 0
        if let m = s.range(of: "\"UsbHvcMenu\"=\\(.*\\)", options: .regularExpression) {
            for entry in s[m].components(separatedBy: "{").dropFirst() {
                if let v = num("MaxVoltage", in: entry), let c = num("MaxCurrent", in: entry) { a.pdos.append([v, c]) }
            }
        }
        if a.pdos.isEmpty && a.millivolts > 0 { a.pdos = [[a.millivolts, a.milliamps]] }
        return a.watts > 0 || a.isApple ? a : nil
    }
}

/// 연결해 본 어댑터 기록
struct AdapterRecord: Codable {
    var title: String
    var firstSeen: Date
    var lastSeen: Date
    var connections: Int
    var bestWatts: Int
}

enum AdapterHistory {
    private static let key = "knownAdapters"

    static func load() -> [String: AdapterRecord] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode([String: AdapterRecord].self, from: d) else { return [:] }
        return v
    }

    static func save(_ v: [String: AdapterRecord]) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
}
