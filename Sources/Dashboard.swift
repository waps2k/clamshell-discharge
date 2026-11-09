// 대시보드: 충전량 / SOH 그래프 + 유지·퇴근 충전 설정

import SwiftUI
import Charts

enum ChartRange: String, CaseIterable, Identifiable {
    case h6 = "6시간", h24 = "24시간", d7 = "7일", d30 = "30일"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self { case .h6: 6 * 3600; case .h24: 86400; case .d7: 7 * 86400; case .d30: 30 * 86400 }
    }
}

struct DashboardView: View {
    @ObservedObject var engine = Engine.shared
    @ObservedObject var settings = Settings.shared
    @State private var range: ChartRange = .h24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCards
                GroupBox {
                    CapacityBar(current: engine.snapshot.rawCurrent, max: engine.snapshot.rawMax, design: engine.snapshot.design, height: 20)
                        .padding(4)
                }
                chargeChart
                sohChart
                maintainSettings
                departureSettings
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 720)
    }

    // MARK: 상태 카드

    var statusCards: some View {
        let b = engine.snapshot
        return HStack(spacing: 12) {
            card("충전량", "\(b.percent)%", sub: chargeStateText)
            card("배터리 성능 (SOH)", String(format: "%.1f%%", b.soh),
                 sub: "\(b.rawMax) / \(b.design) mAh", tint: sohColor(b.soh))
            card("사이클", "\(b.cycles)", sub: "설계 \(b.designCycles)회 기준 \(b.designCycles > 0 ? b.cycles * 100 / b.designCycles : 0)%")
            card("상태", engine.mode.rawValue,
                 sub: engine.target.map { "목표 \($0)%" + (engine.adapterBlocked ? " · 어댑터 차단" : "") } ?? "macOS: \(engine.condition)")
        }
    }

    var chargeStateText: String {
        let b = engine.snapshot
        if !b.plugged { return "배터리 사용" }
        if engine.adapterBlocked { return "꽂힘 · 배터리 사용(세일링)" }
        if b.isCharging { return "충전 중 \(b.amperage)mA" }
        return "꽂힘 · 충전 안 함"
    }

    func sohColor(_ v: Double) -> Color { v >= 85 ? .green : (v >= 80 ? .orange : .red) }

    func card(_ title: String, _ value: String, sub: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: 충전량 그래프

    var visibleSamples: [Sample] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let s = engine.samples.filter { $0.date >= cutoff }
        // 점이 너무 많으면 솎아냄
        let step = max(1, s.count / 600)
        return stride(from: 0, to: s.count, by: step).map { s[$0] }
    }

    var chargeChart: some View {
        GroupBox {
            VStack(alignment: .leading) {
                HStack {
                    Text("충전량").font(.headline)
                    Spacer()
                    Picker("", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                let data = visibleSamples
                if data.isEmpty {
                    Text("기록이 쌓이는 중입니다 (1분마다 저장)").foregroundStyle(.secondary).frame(height: 200)
                } else {
                    Chart {
                        ForEach(data) { s in
                            AreaMark(x: .value("시간", s.date), y: .value("충전량", s.percent))
                                .foregroundStyle(.linearGradient(colors: [.green.opacity(0.35), .green.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("시간", s.date), y: .value("충전량", s.percent))
                                .foregroundStyle(.green)
                        }
                        if settings.maintainEnabled {
                            RuleMark(y: .value("유지", settings.maintainLevel))
                                .foregroundStyle(.blue)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("유지 \(settings.maintainLevel)%").font(.caption2).foregroundStyle(.blue)
                                }
                        }
                        if settings.departureEnabled {
                            RuleMark(y: .value("퇴근", settings.departureTarget))
                                .foregroundStyle(.orange)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .bottom, alignment: .trailing) {
                                    Text("퇴근 목표 \(settings.departureTarget)%").font(.caption2).foregroundStyle(.orange)
                                }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 220)
                }
            }
            .padding(4)
        }
    }

    // MARK: SOH 그래프

    struct DayPoint: Identifiable { let day: Date; let soh: Double; let cycles: Int; var id: Date { day } }

    var dailySOH: [DayPoint] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: engine.samples.filter { $0.soh > 0 }) { cal.startOfDay(for: $0.date) }
        return groups.map { day, s in
            DayPoint(day: day, soh: s.map(\.soh).reduce(0, +) / Double(s.count), cycles: s.map(\.cycles).max() ?? 0)
        }.sorted { $0.day < $1.day }
    }

    var sohChart: some View {
        GroupBox {
            VStack(alignment: .leading) {
                HStack {
                    Text("배터리 성능 (SOH)").font(.headline)
                    Spacer()
                    Text("현재 최대 용량 ÷ 설계 용량 · 80% 미만이면 교체 고려").font(.caption).foregroundStyle(.secondary)
                }
                let pts = dailySOH
                if pts.isEmpty {
                    Text("기록이 쌓이는 중입니다").foregroundStyle(.secondary).frame(height: 160)
                } else {
                    let lo = max(0, min(70, (pts.map(\.soh).min() ?? 70) - 5))
                    Chart {
                        ForEach(pts) { p in
                            LineMark(x: .value("날짜", p.day, unit: .day), y: .value("SOH", p.soh))
                                .foregroundStyle(.purple)
                            PointMark(x: .value("날짜", p.day, unit: .day), y: .value("SOH", p.soh))
                                .foregroundStyle(.purple)
                                .annotation(position: .top) {
                                    Text(String(format: "%.1f", p.soh)).font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                        RuleMark(y: .value("기준", 80))
                            .foregroundStyle(.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .chartYScale(domain: lo...100)
                    .frame(height: 160)
                }
            }
            .padding(4)
        }
    }

    // MARK: 설정

    var maintainSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { settings.maintainEnabled }, set: { on in
                    settings.maintainEnabled = on
                    if on { settings.autoMode = true } // 클램쉘에서 세일링 중 잠들지 않게
                })) {
                    Text("충전 유지 모드").font(.headline)
                }
                Text("전원이 연결된 동안 배터리를 설정한 수준 근처로 유지합니다. 목표에 닿으면 어댑터를 차단해 배터리로 쓰다가, \(settings.band)% 내려오면 다시 충전합니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("유지 수준")
                    Slider(value: Binding(get: { Double(settings.maintainLevel) }, set: { settings.maintainLevel = Int($0) }),
                           in: 60...100, step: 5)
                    Text("\(settings.maintainLevel)%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    if settings.maintainLevel == 60 {
                        Text("추천").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                    } else {
                        Button("추천값 60%") { settings.maintainLevel = 60 }.controlSize(.small)
                    }
                }
                .disabled(!settings.maintainEnabled)
                Toggle("덮개가 닫혀 있을 때(클램쉘)만 적용", isOn: $settings.maintainOnlyClamshell)
                    .disabled(!settings.maintainEnabled)
                Toggle("자동 업무 모드 (전원 연결 시 덮개 닫아도 동작, 배터리면 잠자기)", isOn: $settings.autoMode)
            }
            .padding(4)
        }
    }

    var departureSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.departureEnabled) { Text("퇴근 충전").font(.headline) }
                Text("퇴근 시각 전에 유지 모드를 잠시 멈추고 목표까지 충전합니다. 퇴근 후 30분이 지나면 다시 유지 모드로 돌아갑니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Group {
                    HStack {
                        Text("퇴근 시각")
                        DatePicker("", selection: Binding(get: {
                            Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(settings.departureMinutes * 60))
                        }, set: { d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            settings.departureMinutes = (c.hour ?? 18) * 60 + (c.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 100)
                        Spacer()
                        Stepper("충전 시작: \(settings.departureLead)분 전", value: $settings.departureLead, in: 15...240, step: 15)
                    }
                    HStack {
                        Text("충전 목표")
                        Slider(value: Binding(get: { Double(settings.departureTarget) }, set: { settings.departureTarget = Int($0) }),
                               in: 60...100, step: 5)
                        Text("\(settings.departureTarget)%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    HStack(spacing: 6) {
                        Text("요일")
                        ForEach([(2, "월"), (3, "화"), (4, "수"), (5, "목"), (6, "금"), (7, "토"), (1, "일")], id: \.0) { wd, name in
                            Toggle(name, isOn: Binding(get: { settings.departureWeekdays.contains(wd) }, set: { on in
                                if on { settings.departureWeekdays.insert(wd) } else { settings.departureWeekdays.remove(wd) }
                            }))
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }
                    if let dep = engine.nextDeparture {
                        let start = dep.addingTimeInterval(-TimeInterval(settings.departureLead * 60))
                        let est = estimateText
                        Text("다음 퇴근: \(dep.formatted(date: .abbreviated, time: .shortened)) · 충전 시작 \(start.formatted(date: .omitted, time: .shortened))\(est)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.departureEnabled)
            }
            .padding(4)
        }
    }

    var estimateText: String {
        // 대략: 이 Mac 의 평균 충전 속도(약 1%/분 반, 60→100 이 60~80분) 대신 현재 전류가 있으면 그걸로 계산
        if let m = engine.minutesToCharge(to: settings.departureTarget) {
            return " · 지금 속도로 \(settings.departureTarget)%까지 약 \(m)분"
        }
        return ""
    }
}

final class DashboardWindow {
    static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Clamshell Discharge — 배터리 대시보드"
            w.contentView = NSHostingView(rootView: DashboardView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        Engine.shared.tick()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
