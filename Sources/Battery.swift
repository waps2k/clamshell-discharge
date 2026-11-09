// 배터리 상태 읽기 + 어댑터(SMC CHIE) 제어 + 공용 유틸

import Cocoa

let home = FileManager.default.homeDirectoryForCurrentUser.path
let smcPath = "/usr/local/co.palokaj.battery/smc"

@discardableResult
func sh(_ cmd: String) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    // waitUntilExit() 는 런루프를 돌려서, SwiftUI 갱신 도중 타이머가 끼어들어 크래시를 일으킴.
    // 종료 알림을 세마포어로 기다려 런루프를 돌리지 않음.
    let done = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in done.signal() }
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    done.wait()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

struct BatterySnapshot {
    var date = Date()
    var percent = 0            // 표시 충전량 (%)
    var rawCurrent = 0         // mAh
    var rawMax = 0             // 현재 최대 용량 (mAh)
    var design = 0             // 설계 용량 (mAh)
    var cycles = 0
    var designCycles = 1000
    var isCharging = false
    var externalConnected = false  // macOS 가 어댑터 전원을 쓰는 중인지 (방전 중엔 No)
    var adapterWatts = 0           // 어댑터가 물리적으로 꽂혀 있으면 > 0
    var voltage = 0                // mV
    var amperage = 0               // mA (+충전 / -방전)
    var temperature: Double?       // °C
    var timeToEmpty: Int?          // 분
    var timeToFull: Int?           // 분
    var systemWatts: Double?       // 시스템 전체 소비 전력 (SMC PDTR)
    var nominal = 0                // NominalChargeCapacity (mAh)

    /// 배터리 입출력 전력 (W): +충전 / -방전
    var batteryWatts: Double { Double(voltage) * Double(amperage) / 1_000_000 }

    /// State of Health: 현재 최대 용량 / 설계 용량
    var soh: Double { design > 0 ? Double(rawMax) / Double(design) * 100 : 0 }
    var plugged: Bool { adapterWatts > 0 || externalConnected }
}

enum Battery {
    static func read() -> BatterySnapshot? {
        let out = sh("ioreg -rn AppleSmartBattery").1
        guard !out.isEmpty else { return nil }

        func int(_ key: String) -> Int? {
            guard let r = out.range(of: "\"\(key)\" ?= ?(-?[0-9]+)", options: .regularExpression) else { return nil }
            let s = out[r]
            guard let n = s.range(of: "-?[0-9]+$", options: .regularExpression) else { return nil }
            let txt = String(s[n])
            if let v = Int(txt) { return v }
            if let u = UInt64(txt) { return Int(Int64(bitPattern: u)) } // 음수가 unsigned 64비트로 보고되는 경우
            return nil
        }
        func bool(_ key: String) -> Bool {
            out.range(of: "\"\(key)\" = Yes") != nil
        }

        var b = BatterySnapshot()
        b.percent = int("CurrentCapacity") ?? 0
        b.rawCurrent = int("AppleRawCurrentCapacity") ?? 0
        b.rawMax = int("AppleRawMaxCapacity") ?? 0
        b.design = int("DesignCapacity") ?? 0
        b.cycles = int("CycleCount") ?? 0
        b.designCycles = int("DesignCycleCount9C") ?? 1000
        b.isCharging = bool("IsCharging")
        b.externalConnected = bool("ExternalConnected")
        b.voltage = int("Voltage") ?? 0
        b.amperage = int("InstantAmperage") ?? int("Amperage") ?? 0
        // 어댑터 차단 직후 등 ioreg 값이 늦게 갱신될 때: 배터리 전원이면 방전 방향으로 표시
        if !b.externalConnected && b.amperage > 0 { b.amperage = -b.amperage }
        b.nominal = int("NominalChargeCapacity") ?? 0
        if let t = SMC.readUInt16LE("B0AT"), t > 2000 { b.temperature = Double(t) / 10 - 273.15 } // 0.1 K
        else if let t = int("Temperature"), t > 0 { b.temperature = Double(t) / 100 }
        b.systemWatts = SMC.readFloatLE("PDTR")
        if let v = int("AvgTimeToEmpty"), v > 0, v < 65535 { b.timeToEmpty = v }
        if let v = int("AvgTimeToFull"), v > 0, v < 65535 { b.timeToFull = v }
        if let w = Battery.pdContractWatts() {
            b.adapterWatts = w   // USB-C PD 전원 계약 기준 (뽑으면 바로 0)
        } else if let r = out.range(of: "\"AdapterDetails\" = \\{[^}]*\\}", options: .regularExpression) {
            // PD 정보가 없는 기종: AdapterDetails (뽑은 뒤에도 값이 남을 수 있음)
            let s = String(out[r])
            if let w = s.range(of: "\"Watts\"=[0-9]+", options: .regularExpression) {
                b.adapterWatts = Int(s[w].split(separator: "=").last ?? "0") ?? 0
            }
        }
        return b
    }

    /// USB-C 포트의 실제 전원 계약(PD contract) 중 가장 큰 와트. 계약이 없으면 0.
    /// 어댑터를 차단(CHIE)해도 계약은 유지되므로 '물리적으로 꽂혀 있는지' 판단에 쓴다.
    /// AdapterDetails 는 뽑은 뒤에도 마지막 값이 남는 경우가 있어 믿을 수 없다.
    /// PortControllerInfo 가 없는 기종이면 nil.
    static func pdContractWatts() -> Int? {
        let out = sh("ioreg -r -k PortControllerInfo -d 1").1
        guard out.contains("PortControllerMaxPower") else { return nil }
        var best = 0
        for chunk in out.components(separatedBy: "{") where chunk.contains("PortControllerMaxPower") {
            func val(_ key: String) -> Int {
                guard let r = chunk.range(of: "\"\(key)\"=[0-9]+", options: .regularExpression) else { return 0 }
                return Int(chunk[r].split(separator: "=").last ?? "0") ?? 0
            }
            if val("PortControllerActiveContractRdo") != 0 { best = max(best, val("PortControllerMaxPower") / 1000) }
        }
        return best
    }

    /// macOS 가 보고하는 배터리 상태 문자열 (예: "Normal", "Service Recommended") — 느리므로 가끔만 호출
    static func condition() -> String {
        let out = sh("system_profiler SPPowerDataType 2>/dev/null | grep -m1 'Condition:'").1
        return out.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    static func lidClosed() -> Bool {
        sh(#"ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'"#).0 == 0
    }

    static func externalDisplayCount() -> Int {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success else { return 0 }
        return ids.prefix(Int(n)).filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }.count
    }
}

/// 어댑터 입력 차단(SMC CHIE). 차단하면 꽂힌 채로 배터리를 사용 = 충전도 멈춤.
/// battery CLI 의 sudoers 규칙이 이 두 쓰기를 비밀번호 없이 허용함.
enum Adapter {
    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: smcPath)
            && sh("sudo -n -l \(smcPath) -k CHIE -w 08").0 == 0
    }

    static func isBlocked() -> Bool {
        let out = sh("\(smcPath) -k CHIE -r").1
        return out.contains("bytes 08")
    }

    @discardableResult
    static func setBlocked(_ blocked: Bool) -> Bool {
        sh("sudo -n \(smcPath) -k CHIE -w \(blocked ? "08" : "00")").0 == 0
    }
}

/// SMC 값 읽기 (읽기는 권한 불필요)
enum SMC {
    static func bytes(_ key: String) -> [UInt8]? {
        let out = sh("\(smcPath) -k \(key) -r").1
        guard let r = out.range(of: "bytes ([0-9a-f ]+)\\)", options: .regularExpression) else { return nil }
        let hex = out[r].dropFirst(6).dropLast(1).split(separator: " ")
        let b = hex.compactMap { UInt8($0, radix: 16) }
        return b.isEmpty ? nil : b
    }
    static func readUInt16LE(_ key: String) -> Int? {
        guard let b = bytes(key), b.count >= 2 else { return nil }
        return Int(b[0]) | Int(b[1]) << 8
    }
    static func readFloatLE(_ key: String) -> Double? {
        guard let b = bytes(key), b.count >= 4 else { return nil }
        let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        let v = Double(Float(bitPattern: bits))
        return v.isFinite ? v : nil
    }
}
