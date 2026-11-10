// 메뉴 막대 팝오버 (메인 화면): 배터리 상태 · 사용 기록 · 세부 사항 · 상위 프로세스 · 빠른 제어

import SwiftUI

/// AppDelegate 가 가진 동작을 SwiftUI 에 넘기기 위한 묶음
struct AppActions {
    var startDischarge: (Int) -> Void
    var stopDischarge: () -> Void
    var dischargeState: () -> (running: Bool, target: Int?)
    var changeDischargeTarget: (Int) -> Void
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
        case .charging: tr("충전 중")
        case .sailing: tr("방전 중 · 유지 모드")
        case .manualDischarge: tr("방전 중 · 수동 방전")
        case .onBattery: tr("배터리 사용 중")
        case .full: tr("충전 완료")
        case .pluggedIdle: tr("전원 연결됨 · 충전 대기")
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

func fmtMinutes(_ m: Int) -> String { m >= 60 ? tr("\(m / 60)시간 \(m % 60)분") : tr("\(m)분") }

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
    @State private var tick = 0
    /// 처음 펼쳐 둘 일정 (스크린샷 생성용, 앱에서는 nil)
    static var initialExpanded: ScheduleKind? = nil
    @State private var expanded: ScheduleKind? = PopoverView.initialExpanded  // 편집 칸을 펼친 일정
    @State private var departIn: Double = 0            // 지금 충전: 출발까지 시간 (0 = 바로) // 메뉴 상태(로그인 항목 등) 재계산용

    static let columnWidth: CGFloat = 300

    var body: some View {
        let b = engine.snapshot
        let st = engine.chargeState
        VStack(spacing: 0) {
            // 스크롤 없이 한 화면: 왼쪽 = 상태, 오른쪽 = 제어
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    header(b, st)
                    section(tr("사용 기록")) { usageHistory }
                    section(tr("세부 사항")) { details(b, st) }
                    section(tr("배터리")) { batteryDetails(b) }
                }
                .frame(width: Self.columnWidth)
                Divider()
                VStack(spacing: 12) {
                    section(tr("모드")) { controls }
                    Spacer(minLength: 0)
                }
                .frame(width: Self.columnWidth)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
        }
        .frame(width: Self.columnWidth * 2 + 16 + 32 + 1)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, L10n.locale)
    }

    // MARK: 헤더

    func header(_ b: BatterySnapshot, _ st: ChargeState) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                BatteryGlyph(percent: b.percent, state: st, width: 104)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(b.percent)").font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("%").font(.title3).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: st.symbol)
                Text(st.label)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(st.color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(st.color.opacity(0.14)))
            if settings.oneShotTarget > 0, engine.mode != .oneShot, let start = engine.oneShotStartAt {
                Text(tr("지금 충전 예약 · \(start.tTime)부터")).font(.caption).foregroundStyle(.secondary)
            } else if let t = engine.target, let lim = engine.systemLimit, t >= lim {
                Text(tr("macOS 충전 제한 \(lim)% · 배터리 안 쓰고 전원 사용")).font(.caption).foregroundStyle(.secondary)
            } else if let t = engine.target, [.maintain, .departure, .commute, .weekend, .oneShot].contains(engine.mode) {
                Group {
                    switch engine.mode {
                    case .maintain: Text(tr("유지 모드 · \(t - settings.band)~\(t)%"))
                    case .commute: Text(tr("출근 충전 · 목표 \(t)%"))
                    case .weekend: Text(tr("주말 외출 충전 · 목표 \(t)%"))
                    case .oneShot: Text(tr("지금 충전 · 목표 \(t)%"))
                    default: Text(tr("퇴근 충전 · 목표 \(t)%"))
                    }
                }
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
            .frame(height: 64)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
            HStack(spacing: 10) {
                legend(.green, tr("충전"))
                legend(.blue, tr("유지(어댑터 차단)"))
                legend(.green.opacity(0.75), tr("배터리"))
                Spacer()
                Text(tr("최근 4시간")).foregroundStyle(.secondary)
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
            if let c = b.temperature {
                row(tr("배터리 온도"), String(format: "%.1f°C · ", c) + TempLevel(c).label,
                    tint: TempLevel(c) == .hot ? .red : TempLevel(c) == .warm ? .orange : .primary)
            }
            row(tr("공급원"), b.plugged ? (engine.adapterBlocked ? tr("어댑터 \(b.adapterWatts)W (차단 중)") : tr("어댑터 \(b.adapterWatts)W")) : tr("배터리 전원"))
            switch st {
            case .charging:
                row(tr("완충까지"), b.timeToFull.map(fmtMinutes) ?? tr("계산 중"))
                if let t = engine.target, t < 100, let m = engine.minutesToCharge(to: t) {
                    row(tr("\(t)%까지"), fmtMinutes(m))
                }
            case .full, .pluggedIdle:
                row(tr("충전"), tr("대기"))
            default:
                row(tr("남은 사용 시간"), b.timeToEmpty.map(fmtMinutes) ?? tr("계산 중"))
            }
            // 가장 가까운 일정 하나만 (여럿이면 화면이 길어짐)
            if let (k, t) = engine.nextTimes.min(by: { $0.value < $1.value }) {
                row(k == .commute ? tr("다음 출근 충전") : k == .weekend ? tr("다음 주말 외출 충전") : tr("다음 퇴근 충전"),
                    "\(t.tWeekdayTime) · \(settings.schedule(k).target)%")
            }
        }
    }

    // MARK: 배터리

    func batteryDetails(_ b: BatterySnapshot) -> some View {
        VStack(spacing: 6) {
            CapacityBar(current: b.rawCurrent, max: b.rawMax, design: b.design)
                .padding(.bottom, 6)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 5) {
                    row(tr("어댑터"), b.systemWatts.map { String(format: "%.1f W", $0) } ?? "-")
                    row(tr("전류"), "\(b.amperage) mA")
                    row(tr("사이클"), "\(b.cycles)")
                }
                VStack(spacing: 5) {
                    row(tr("배터리"), String(format: "%+.1f W", b.batteryWatts))
                    row(tr("전압"), String(format: "%.2f V", Double(b.voltage) / 1000))
                    row(tr("온도"), b.temperature.map { String(format: "%.1f°C", $0) } ?? "-",
                        tint: (b.temperature ?? 0) >= 40 ? .orange : .primary)
                }
            }
            row(tr("macOS 판정"), engine.condition)
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
                    Text(tr("충전 유지"))
                    Spacer()
                    Text("\(settings.maintainLevel)%").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if settings.maintainEnabled {
                HStack {
                    Slider(value: Binding(get: { Double(settings.maintainLevel) }, set: { settings.maintainLevel = Int($0) }),
                           in: 60...100, step: 5)
                    if settings.maintainLevel != 60 {
                        Button(tr("추천 60")) { settings.maintainLevel = 60 }.controlSize(.mini)
                    }
                }
                // 집(덮개 열고 사용)에서도 유지할지
                HStack(spacing: 6) {
                    Text(tr("적용")).foregroundStyle(.secondary).lineLimit(1).frame(width: 46, alignment: .leading)
                    chip(tr("항상"), selected: !settings.maintainOnlyClamshell) { settings.maintainOnlyClamshell = false }
                    chip(tr("덮개 닫혔을 때만"), selected: settings.maintainOnlyClamshell) { settings.maintainOnlyClamshell = true }
                    Spacer(minLength: 0)
                }
            }
            ForEach(ScheduleKind.allCases) { k in
                scheduleRow(k)
            }
            oneShotRow
            Toggle(isOn: $settings.autoMode) {
                HStack {
                    Text(tr("자동 업무 모드"))
                    Spacer()
                    Text(tr("클램쉘")).foregroundStyle(.secondary)
                }
            }
            .disabled(!actions.permissionReady())
            Toggle(tr("전원 연결 시 잠자기 안 함"), isOn: $settings.keepDisplayOnAC)
            Toggle(isOn: Binding(get: { settings.hidWake }, set: { on in
                settings.hidWake = on
                if on && !HIDWaker.shared.accessGranted { HIDWaker.shared.requestAccess() }
                tick += 1
            })) {
                HStack {
                    Text(tr("블루투스 입력으로 화면 켜기"))
                    Spacer()
                    if settings.hidWake && !HIDWaker.shared.accessGranted {
                        Text(tr("권한 필요")).foregroundStyle(.orange)
                    }
                }
            }
            if settings.hidWake && !HIDWaker.shared.accessGranted {
                HStack {
                    Text(tr("입력 모니터링 권한을 허용해야 동작합니다.")).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("설정 열기")) {
                        HIDWaker.shared.requestAccess()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                    .controlSize(.mini)
                }
            }

            if ds.running {
                dischargeEditor(target: ds.target ?? 60)
                HStack {
                    Spacer()
                    Button(tr("대시보드")) { actions.openDashboard() }
                }
            } else {
                HStack {
                    Menu {
                        ForEach([90, 85, 80, 75, 70, 60, 50], id: \.self) { t in
                            Button(tr("\(t)% 까지")) { actions.startDischarge(t) }
                        }
                    } label: {
                        Label(tr("수동 방전"), systemImage: "arrow.down.circle")
                    }
                    .fixedSize()
                    .disabled(!actions.permissionReady())
                    Spacer()
                    Button(tr("대시보드")) { actions.openDashboard() }
                }
            }
            if !actions.permissionReady() {
                Button {
                    actions.setupPermission()
                    tick += 1
                } label: {
                    Label(tr("권한 설정 (최초 1회)…"), systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
                Text(tr("클램쉘 잠자기 제어(수동 방전·자동 업무 모드)에 필요합니다.")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(ColorSwitchStyle())
        .controlSize(.small)
    }

    // MARK: 수동 방전 (실행 중 목표 변경)

    func dischargeEditor(target: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                Text(tr("수동 방전 중")).font(.callout.weight(.medium))
                Spacer()
                stepButton("minus") { actions.changeDischargeTarget(target - 5); tick += 1 }
                Text("\(target)%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    .frame(minWidth: 46)
                stepButton("plus") { actions.changeDischargeTarget(target + 5); tick += 1 }
            }
            HStack(spacing: 6) {
                Text(tr("목표")).foregroundStyle(.secondary).lineLimit(1).frame(width: 46, alignment: .leading)
                ForEach([50, 60, 70, 80, 90], id: \.self) { t in
                    chip("\(t)%", selected: target == t) { actions.changeDischargeTarget(t); tick += 1 }
                }
            }
            HStack {
                Text(tr("바꾸면 바로 적용됩니다 (다시 시작 불필요)")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    actions.stopDischarge()
                } label: {
                    Label(tr("중지"), systemImage: "stop.fill")
                }
                .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        .id(tick)
    }

    // MARK: 일정 충전 (출근·퇴근)

    /// 켜고 끄는 줄 + (펼친 일정만) 편집 칸. 줄을 누르면 펼치기/접기
    func scheduleRow(_ k: ScheduleKind) -> some View {
        let v = settings.schedule(k)
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { v.enabled }, set: { on in
                settings.update(k) { $0.enabled = on }
                if on { expanded = k }
            })) {
                HStack(spacing: 4) {
                    Text(k.title)
                    if v.enabled {
                        Image(systemName: expanded == k ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(v.timeText) · \(v.target)%").monospacedDigit().foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { if v.enabled { expanded = expanded == k ? nil : k } }
            }
            if v.enabled && expanded == k {
                scheduleEditor(k)
            }
        }
    }

    func scheduleEditor(_ k: ScheduleKind) -> some View {
        let v = settings.schedule(k)
        let presets = k.presets
        return VStack(alignment: .leading, spacing: 9) {
            // 시각: −/+ 15분, 자주 쓰는 시각은 메뉴로
            HStack(spacing: 8) {
                Text(k.shortTitle).foregroundStyle(.secondary).lineLimit(1).frame(width: 46, alignment: .leading)
                stepButton("minus") { settings.update(k) { $0.minutes = ($0.minutes - 15 + 1440) % 1440 } }
                Menu {
                    ForEach(presets, id: \.self) { m in
                        Button(String(format: "%02d:%02d", m / 60, m % 60)) { settings.update(k) { $0.minutes = m } }
                    }
                } label: {
                    Text(v.timeText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                stepButton("plus") { settings.update(k) { $0.minutes = ($0.minutes + 15) % 1440 } }
                Spacer()
                Menu {
                    ForEach([30, 60, 90, 120, 180], id: \.self) { m in
                        Button(tr("\(m)분 전부터 충전")) { settings.update(k) { $0.lead = m } }
                    }
                } label: {
                    Text(tr("\(v.lead)분 전 시작")).font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // 목표: 프리셋 칩 + 미세 조정 슬라이더
            HStack(spacing: 6) {
                Text(tr("목표")).foregroundStyle(.secondary).lineLimit(1).frame(width: 46, alignment: .leading)
                ForEach([80, 90, 100], id: \.self) { t in
                    chip("\(t)%", selected: v.target == t) { settings.update(k) { $0.target = t } }
                }
                Spacer()
                Text("\(v.target)%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(v.target) }, set: { x in settings.update(k) { $0.target = Int(x) } }),
                   in: 60...100, step: 5)
                .padding(.leading, 52)

            // 요일
            HStack(spacing: 4) {
                Text(tr("요일")).foregroundStyle(.secondary).lineLimit(1).frame(width: 46, alignment: .leading)
                ForEach([(2, tr("월")), (3, tr("화")), (4, tr("수")), (5, tr("목")), (6, tr("금")), (7, tr("토")), (1, tr("일"))], id: \.0) { wd, name in
                    chip(name, selected: v.weekdays.contains(wd), compact: true) {
                        settings.update(k) { if $0.weekdays.contains(wd) { $0.weekdays.remove(wd) } else { $0.weekdays.insert(wd) } }
                    }
                }
            }

            if let t = engine.nextTime(k) {
                let start = t.addingTimeInterval(-TimeInterval(v.lead * 60))
                Label(tr("\(start.tTime)부터 충전 → \(t.tWeekdayTime)까지 \(v.target)%"), systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(tr("요일을 하나 이상 선택하세요")).font(.caption2).foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
    }

    // MARK: 지금 충전 (출장·외출)

    /// 켜져 있으면 실제 설정된 출발 시각 기준으로 선택 표시 (남은 시간을 반올림), 꺼져 있으면 고른 값
    var shownDepartIn: Double {
        guard settings.oneShotTarget > 0 else { return departIn }
        guard let dep = settings.oneShotDeparture else { return 0 }
        return min(3, max(1, (dep.timeIntervalSinceNow / 3600).rounded()))
    }

    var oneShotRow: some View {
        let t = settings.oneShotTarget
        let b = engine.snapshot
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "suitcase.rolling.fill").foregroundStyle(t > 0 ? Color.accentColor : .secondary)
                Text(tr("지금 충전 (출장·외출)"))
                Spacer()
                chip("80%", selected: t == 80) { t == 80 ? settings.cancelOneShot() : settings.startOneShot(80, inHours: departIn) }
                chip("100%", selected: t == 100) { t == 100 ? settings.cancelOneShot() : settings.startOneShot(100, inHours: departIn) }
            }
            // 출발 시각: 늦게 나가면 그 시각에 맞춰 늦게 충전 (높은 %로 오래 머물지 않게)
            HStack(spacing: 5) {
                Text(tr("출발")).font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                ForEach([0.0, 1, 2, 3], id: \.self) { h in
                    chip(h == 0 ? tr("지금") : tr("\(Int(h))시간 후"), selected: shownDepartIn == h, compact: true) {
                        departIn = h
                        if t > 0 { settings.setOneShotDeparture(inHours: h) }
                    }
                }
                Spacer(minLength: 0)
            }
            if t > 0 {
                HStack {
                    if let dep = settings.oneShotDeparture, let start = engine.oneShotStartAt, engine.mode != .oneShot, b.percent < t - 1 {
                        Text(tr("\(dep.tTime) 출발 · \(start.tTime)부터 충전")).foregroundStyle(.secondary)
                    } else if b.percent >= t - 1 {
                        Text(tr("충전 완료")).foregroundStyle(.green)
                    } else if let m = engine.minutesToCharge(to: t) {
                        Text(tr("\(t)%까지") + " " + fmtMinutes(m)).foregroundStyle(.secondary)
                    } else {
                        Text(tr("목표 \(t)%")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(tr("해제")) { settings.cancelOneShot() }.controlSize(.mini)
                }
                .font(.caption)
                Text(tr("목표에 도달한 뒤 어댑터를 뽑으면 자동으로 해제됩니다 (최대 24시간)"))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if t == 100 {
                    Text(tr("macOS 충전 한도가 설정돼 있으면 그 이상은 충전되지 않습니다"))
                        .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(Color.secondary.opacity(0.15)))
    }

    func chip(_ title: String, selected: Bool, compact: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(compact ? .caption : .caption.weight(.medium))
                .frame(minWidth: compact ? 22 : 38)
                .padding(.vertical, 3)
                .padding(.horizontal, compact ? 2 : 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 하단

    var footer: some View {
        HStack {
            Menu {
                Picker(tr("언어"), selection: $settings.language) {
                    ForEach(L10n.languages, id: \.code) { l in
                        Text(l.code == "system" ? tr("시스템 설정 따름") : l.name).tag(l.code)
                    }
                }
                Divider()
                Button("☕ " + tr("후원하기")) { NSWorkspace.shared.open(donateURL) }
                Button(tr("로그 보기")) { actions.openLog() }
                Toggle(tr("로그인 시 자동 실행"), isOn: Binding(get: { actions.loginEnabled() }, set: { _ in actions.toggleLogin(); tick += 1 }))
                Divider()
                Text(tr("덮개 닫힌 채 모니터/어댑터를 뽑으면 자동 중지 후 잠자기"))
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button(tr("종료")) { actions.quit() }.controlSize(.small)
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

/// 창이 활성/비활성이어도 켜짐 상태가 분명히 보이는 스위치
/// (메뉴 막대 팝오버는 비활성으로 그려질 때가 많아 기본 스위치가 회색으로 보임)
struct ColorSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.28))
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? "on" : "off")
        }
    }
}
