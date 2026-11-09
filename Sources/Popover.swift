// 메뉴 막대 팝오버 (메인 화면): 배터리 상태 · 사용 기록 · 세부 사항 · 상위 프로세스 · 빠른 제어

import SwiftUI

/// AppDelegate 가 가진 동작을 SwiftUI 에 넘기기 위한 묶음
struct AppActions {
    var startDischarge: (Int) -> Void
    var stopDischarge: () -> Void
    var dischargeState: () -> (running: Bool, target: Int?)
    var permissionReady: () -> Bool
    var setupPermission: () -> Void
    var openLog: () -> Void
    var loginEnabled: () -> Bool
    var toggleLogin: () -> Void
    var openDashboard: () -> Void
    var quit: () -> Void
}

enum ChargeState {
    case charging, sailing, manualDischarge, onBattery, full, pluggedIdle

    var label: String {
        switch self {
        case .charging: "충전 중"
        case .sailing: "방전 중 · 유지 모드"
        case .manualDischarge: "방전 중 · 수동 방전"
        case .onBattery: "배터리 사용 중"
        case .full: "충전 완료"
        case .pluggedIdle: "전원 연결됨 · 충전 대기"
        }
    }
    var color: Color {
        switch self {
        case .charging, .full: .green
        case .sailing: .blue
        case .manualDischarge: .orange
        case .onBattery: .secondary
        case .pluggedIdle: .teal
        }
    }
    var symbol: String {
        switch self {
        case .charging: "bolt.fill"
        case .sailing: "sailboat.fill"
        case .manualDischarge: "arrow.down"
        case .onBattery: "minus"
        case .full: "checkmark"
        case .pluggedIdle: "powerplug.fill"
        }
    }
}

extension Engine {
    var chargeState: ChargeState {
        let b = snapshot
        if mode == .manual { return .manualDischarge }
        if b.plugged && adapterBlocked { return .sailing }
        if !b.plugged { return .onBattery }
        if b.isCharging { return .charging }
        if b.percent >= 99 { return .full }
        return .pluggedIdle
    }
}

func levelColor(_ pct: Int) -> Color { pct <= 10 ? .red : (pct <= 20 ? .orange : .green) }

func fmtMinutes(_ m: Int) -> String { m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분" }

// MARK: - 배터리 그림

struct BatteryGlyph: View {
    let percent: Int
    let state: ChargeState
    var width: CGFloat = 170

    var body: some View {
        let h = width * 0.5
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h * 0.22)
                    .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 3)
                RoundedRectangle(cornerRadius: h * 0.16)
                    .fill(levelColor(percent).gradient)
                    .frame(width: max(h * 0.2, (width - 14) * CGFloat(percent) / 100))
                    .padding(7)
                if state == .charging || state == .sailing || state == .manualDischarge {
                    Image(systemName: state.symbol)
                        .font(.system(size: h * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: h)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 6, height: h * 0.32)
        }
        .animation(.easeInOut, value: percent)
    }
}

// MARK: - 팝오버

struct PopoverView: View {
    @ObservedObject var engine = Engine.shared
    @ObservedObject var settings = Settings.shared
    let actions: AppActions
    @State private var tick = 0 // 메뉴 상태(로그인 항목 등) 재계산용

    var body: some View {
        let b = engine.snapshot
        let st = engine.chargeState
        ScrollView {
            VStack(spacing: 12) {
                header(b, st)
                section("사용 기록") { usageHistory }
                section("세부 사항") { details(b, st) }
                section("배터리") { batteryDetails(b) }
                section("모드") { controls }
                section("상위 프로세스") { processes }
                footer
            }
            .padding(16)
        }
        .frame(width: 340, height: 720)
    }

    // MARK: 헤더

    func header(_ b: BatterySnapshot, _ st: ChargeState) -> some View {
        VStack(spacing: 10) {
            BatteryGlyph(percent: b.percent, state: st)
                .padding(.top, 6)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(b.percent)").font(.system(size: 44, weight: .bold, design: .rounded))
                Text("%").font(.title2).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: st.symbol)
                Text(st.label)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(st.color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(st.color.opacity(0.14)))
            if let t = engine.target, engine.mode == .maintain || engine.mode == .departure {
                Text(engine.mode == .departure ? "퇴근 충전 · 목표 \(t)%" : "유지 모드 · \(t - settings.band)~\(t)%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 사용 기록 (최근 4시간, 5분 단위 막대)

    struct Bar: Identifiable { let id: Int; let pct: Int?; let charging: Bool; let blocked: Bool }

    var bars: [Bar] {
        let bucket: TimeInterval = 300, count = 48
        let now = Date()
        let start = now.addingTimeInterval(-bucket * Double(count))
        var groups = [Int: [Sample]]()
        for s in engine.samples where s.date >= start {
            let i = min(count - 1, Int(s.date.timeIntervalSince(start) / bucket))
            groups[i, default: []].append(s)
        }
        return (0..<count).map { i in
            guard let g = groups[i], let last = g.last else { return Bar(id: i, pct: nil, charging: false, blocked: false) }
            return Bar(id: i, pct: last.percent, charging: g.contains { $0.charging }, blocked: g.contains { $0.adapterBlocked })
        }
    }

    var usageHistory: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width / 48
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(bars) { bar in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.12))
                            if let p = bar.pct {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(bar.blocked ? Color.blue : (bar.charging ? Color.green : levelColor(p).opacity(0.75)))
                                    .frame(height: geo.size.height * CGFloat(p) / 100)
                            }
                        }
                        .frame(width: max(1, w - 2))
                        .frame(width: w)
                    }
                }
            }
            .frame(height: 90)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
            HStack(spacing: 10) {
                legend(.green, "충전")
                legend(.blue, "유지(어댑터 차단)")
                legend(.green.opacity(0.75), "배터리")
                Spacer()
                Text("최근 4시간").foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
    }

    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 3) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8); Text(t) }
    }

    // MARK: 세부 사항

    func details(_ b: BatterySnapshot, _ st: ChargeState) -> some View {
        VStack(spacing: 6) {
            row("공급원", b.plugged ? (engine.adapterBlocked ? "어댑터 \(b.adapterWatts)W (차단 중)" : "어댑터 \(b.adapterWatts)W") : "배터리 전원")
            switch st {
            case .charging:
                row("완충까지", b.timeToFull.map(fmtMinutes) ?? "계산 중")
                if let t = engine.target, t < 100, let m = engine.minutesToCharge(to: t) {
                    row("\(t)%까지", fmtMinutes(m))
                }
            case .full, .pluggedIdle:
                row("충전", "대기")
            default:
                row("남은 사용 시간", b.timeToEmpty.map(fmtMinutes) ?? "계산 중")
            }
            if settings.departureEnabled, let dep = engine.nextDeparture {
                row("다음 퇴근 충전", "\(dep.formatted(date: .omitted, time: .shortened)) · \(settings.departureTarget)%")
            }
        }
    }

    // MARK: 배터리

    func batteryDetails(_ b: BatterySnapshot) -> some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("최대 용량").font(.caption2).foregroundStyle(.secondary)
                    Text("\(b.rawMax) mAh").font(.callout)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("설계 용량").font(.caption2).foregroundStyle(.secondary)
                    Text("\(b.design) mAh").font(.callout)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(b.soh >= 80 ? Color.green : Color.orange)
                        .frame(width: geo.size.width * min(1, CGFloat(b.soh) / 100))
                }
            }
            .frame(height: 10)
            .padding(.bottom, 4)
            if let w = b.systemWatts { row("시스템 전력", String(format: "%.2f W", w)) }
            row("배터리 전력", String(format: "%+.2f W", b.batteryWatts))
            row("전류", "\(b.amperage) mA")
            row("전압", String(format: "%.2f V", Double(b.voltage) / 1000))
            row("상태 (SOH)", String(format: "%.1f%%", b.soh), tint: b.soh >= 80 ? .primary : .orange)
            row("사이클", "\(b.cycles) / \(b.designCycles)")
            if let t = b.temperature {
                row("온도", String(format: "%.1f°C", t), tint: t >= 40 ? .orange : .primary)
            }
            row("macOS 판정", engine.condition)
        }
    }

    // MARK: 모드 / 제어

    var controls: some View {
        let ds = actions.dischargeState()
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { settings.maintainEnabled }, set: { on in
                settings.maintainEnabled = on
                if on { settings.autoMode = true }
            })) {
                HStack {
                    Text("충전 유지")
                    Spacer()
                    Text("\(settings.maintainLevel)%").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if settings.maintainEnabled {
                HStack {
                    Slider(value: Binding(get: { Double(settings.maintainLevel) }, set: { settings.maintainLevel = Int($0) }),
                           in: 60...100, step: 5)
                    if settings.maintainLevel != 60 {
                        Button("추천 60") { settings.maintainLevel = 60 }.controlSize(.mini)
                    }
                }
            }
            Toggle(isOn: $settings.departureEnabled) {
                HStack {
                    Text("퇴근 충전")
                    Spacer()
                    Text("\(settings.departureTimeText) · \(settings.departureTarget)%").foregroundStyle(.secondary)
                }
            }
            Toggle("자동 업무 모드 (클램쉘)", isOn: $settings.autoMode)
                .disabled(!actions.permissionReady())

            HStack {
                if ds.running {
                    Button {
                        actions.stopDischarge()
                    } label: {
                        Label("방전 중지\(ds.target.map { " (→\($0)%)" } ?? "")", systemImage: "stop.fill")
                    }
                } else {
                    Menu {
                        ForEach([90, 85, 80, 75, 70, 60, 50], id: \.self) { t in
                            Button("\(t)% 까지") { actions.startDischarge(t) }
                        }
                    } label: {
                        Label("수동 방전", systemImage: "arrow.down.circle")
                    }
                    .fixedSize()
                    .disabled(!actions.permissionReady())
                }
                Spacer()
                Button("대시보드") { actions.openDashboard() }
            }
            if !actions.permissionReady() {
                Button {
                    actions.setupPermission()
                    tick += 1
                } label: {
                    Label("권한 설정 (최초 1회)…", systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
                Text("클램쉘 잠자기 제어(수동 방전·자동 업무 모드)에 필요합니다.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: 상위 프로세스

    var processes: some View {
        VStack(spacing: 5) {
            HStack {
                Text("프로세스"); Spacer(); Text("CPU")
            }
            .font(.caption).foregroundStyle(.secondary)
            ForEach(engine.processes) { p in
                HStack {
                    Circle().fill(p.cpu >= 50 ? Color.orange : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                    Text(p.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.1f%%", p.cpu)).monospacedDigit()
                }
                .font(.callout)
            }
        }
    }

    // MARK: 하단

    var footer: some View {
        HStack {
            Menu {
                Button("로그 보기") { actions.openLog() }
                Toggle("로그인 시 자동 실행", isOn: Binding(get: { actions.loginEnabled() }, set: { _ in actions.toggleLogin(); tick += 1 }))
                Divider()
                Text("덮개 닫힌 채 모니터/어댑터를 뽑으면 자동 중지 후 잠자기")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("종료") { actions.quit() }.controlSize(.small)
        }
        .id(tick)
    }

    // MARK: 공통

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack { Divider() }
                Text(title).font(.caption).foregroundStyle(.secondary).fixedSize()
                VStack { Divider() }
            }
            content()
        }
    }

    func row(_ k: String, _ v: String, tint: Color = .primary) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).foregroundStyle(tint).monospacedDigit()
        }
        .font(.callout)
    }
}
