// ClamshellDischarge — 메뉴 막대 앱
// - 수동 방전: 번들된 clamshell-discharge 스크립트 실행
// - 자동 업무 모드: 전원 연결 시 덮개 닫아도 동작, 배터리면 잠자기
// - 충전 유지 / 퇴근 충전 / 대시보드: Engine.swift, Dashboard.swift

import Cocoa
import ServiceManagement
import SwiftUI

let logPath = "\(home)/.battery/clamshell-discharge.log"
let sudoersPath = "/etc/sudoers.d/clamshell-discharge"
let targetFilePath = "\(home)/.battery/clamshell-discharge.target"
let targets = [90, 85, 80, 75, 70, 60, 50]

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let popover = NSPopover()
    var liveTimer: Timer?
    var proc: Process?
    var target: Int?
    var timer: Timer?
    var autoTimer: Timer?
    var lastAutoAction = ""
    let engine = Engine.shared
    let settings = Settings.shared
    var autoMode: Bool {
        get { settings.autoMode }
        set { settings.autoMode = newValue }
    }

    var scriptPath: String {
        Bundle.main.path(forResource: "clamshell-discharge", ofType: nil) ?? "\(home)/bin/clamshell-discharge"
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.delegate = self
        if let b = item.button {
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.delegate = self
        refreshIcon()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshIcon() }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.autoTick() }
        syncManualState()
        engine.manualDischarge = { [weak self] in
            guard let self else { return false }
            return self.isRunning || self.externalRunning
        }
        engine.start()
        if CommandLine.arguments.contains("--show-dashboard") { // 디버그/스크린샷: 대시보드 열기
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { DashboardWindow.show() }
        }
        if CommandLine.arguments.contains("--show-popover") { // 디버그: 실행하자마자 팝오버 열기
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showPopover() }
        }
        // 이전에 비정상 종료돼 잠자기 차단이 남아 있으면 복구
        if !isRunning && !externalRunning && FileManager.default.fileExists(atPath: "\(home)/.battery/clamshell-discharge.sleepdisabled") {
            _ = sh("'\(scriptPath)' --restore >> '\(logPath)' 2>&1")
        }
    }

    func applicationWillTerminate(_ n: Notification) {
        if let p = proc, p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        engine.shutdown()
        if autoMode && !externalRunning { _ = setSleepDisabled(false) }
    }

    // MARK: 자동 업무 모드
    // 전원(어댑터 물리 연결) + (덮개 열림 또는 외장 모니터 있음) → 덮개 닫아도 계속 동작 (disablesleep 1)
    // 그 외(배터리, 또는 덮개 닫힘 + 외장 모니터 없음) → 일반 잠자기 (disablesleep 0), 덮개 닫혀 있으면 즉시 잠자기

    func adapterPlugged() -> Bool {
        if sh("pmset -g batt | head -1").1.contains("AC Power") { return true }
        let w = sh(#"ioreg -rn AppleSmartBattery | grep -o '"AdapterDetails" = {[^}]*}' | grep -Eo '"Watts"=[0-9]+' | head -1 | cut -d= -f2"#).1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (Int(w) ?? 0) > 0
    }

    func lidClosed() -> Bool {
        sh(#"ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'"#).0 == 0
    }

    func externalDisplayCount() -> Int {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success else { return 0 }
        return ids.prefix(Int(n)).filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }.count
    }

    func sleepDisabledNow() -> Bool {
        sh("pmset -g | awk '/SleepDisabled/ {print $2}'").1.hasPrefix("1")
    }

    @discardableResult
    func setSleepDisabled(_ on: Bool) -> Bool {
        sh("sudo -n /usr/bin/pmset -a disablesleep \(on ? 1 : 0)").0 == 0
    }

    /// 뷰가 읽을 수동 방전 상태를 갱신 (타이머·동작 직후에만 호출)
    func syncManualState() {
        let running = isRunning || externalRunning
        let t = running ? currentDischargeTarget() : nil
        if engine.manualRunning != running { engine.manualRunning = running }
        if engine.manualTarget != t { engine.manualTarget = t }
        let perm = permissionReady
        if engine.permissionReady != perm { engine.permissionReady = perm }
    }

    func autoTick() {
        syncManualState()
        guard autoMode, permissionReady else { return }
        let plugged = adapterPlugged()
        let closed = lidClosed()
        let displays = externalDisplayCount()
        let work = plugged && (!closed || displays > 0)
        let discharging = isRunning || externalRunning

        if work {
            if !sleepDisabledNow() { setSleepDisabled(true) }
            lastAutoAction = "work"
        } else {
            // 방전 스크립트가 돌고 있으면 스크립트의 퇴근 감지가 정리하도록 먼저 중지
            if discharging && closed { stopDischarge() }
            if sleepDisabledNow() { setSleepDisabled(false) }
            if closed && lastAutoAction != "slept" {
                lastAutoAction = "slept"
                _ = sh("pmset sleepnow")
            } else if !closed {
                lastAutoAction = "battery"
            }
        }
        refreshIcon()
    }

    @objc func toggleAutoMode() {
        autoMode.toggle()
        if autoMode {
            autoTick()
        } else if !(isRunning || externalRunning) {
            setSleepDisabled(false)
        }
        refreshIcon()
    }

    // MARK: 상태

    var isRunning: Bool { proc?.isRunning ?? false }

    var externalRunning: Bool {
        !isRunning && sh("pgrep -f 'clamshell-discharge [0-9]'").0 == 0
    }

    /// sudo -n -l 은 시스템 설정에 따라 실제로는 비밀번호가 필요한데도 통과하는 경우가 있어 파일 존재로 확인
    var permissionReady: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    var batteryInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/local/co.palokaj.battery/battery")
    }

    func batteryLine() -> String {
        let out = sh("pmset -g batt").1
        let pct = out.range(of: #"\d+%"#, options: .regularExpression).map { String(out[$0]) } ?? "?"
        let state: String
        if out.contains("discharging") { state = tr("방전 중") }
        else if out.contains("charging") && !out.contains("not charging") { state = tr("충전 중") }
        else if out.contains("charged") { state = tr("충전 완료") }
        else { state = tr("충전 안 함") }
        return tr("배터리 \(pct) · \(state)")
    }

    func refreshIcon() {
        guard let b = item.button else { return }
        let snap = engine.snapshot
        let st = engine.chargeState
        let symbol: String
        switch st {
        case .charging: symbol = "battery.100percent.bolt"
        case .sailing: symbol = "sailboat.fill"
        case .manualDischarge: symbol = "arrow.down.circle.fill"
        case .pluggedIdle, .full: symbol = "powerplug.fill"
        case .onBattery:
            let p = snap.percent
            symbol = p > 87 ? "battery.100percent" : p > 62 ? "battery.75percent" : p > 37 ? "battery.50percent" : p > 12 ? "battery.25percent" : "battery.0percent"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: st.label)
        img?.isTemplate = true
        b.image = img
        b.imagePosition = .imageLeft
        var title = " \(snap.percent)%"
        if (isRunning || externalRunning), let t = currentDischargeTarget() { title += "→\(t)" }
        else if engine.mode == .departure { title += "⏰" }
        b.title = title
        b.toolTip = "\(st.label)\(engine.target.map { tr(" · 목표 \($0)%") } ?? "")"
    }

    // MARK: 팝오버

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let b = item.button else { return }
        engine.refreshLive()
        // 내용 크기에 맞춰 팝오버 크기가 정해지고, 편집 칸을 펼치면 함께 늘어남 (스크롤 없음)
        if popover.contentViewController == nil {
            let host = NSHostingController(rootView: PopoverView(actions: makeActions()))
            if #available(macOS 13.0, *) { host.sizingOptions = [.preferredContentSize] }
            popover.contentViewController = host
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        // 활성 창이어야 스위치가 강조색으로 보임. 첫 컨트롤에 포커스 테두리는 생기지 않게 비움.
        if let w = popover.contentViewController?.view.window {
            w.makeKey()
            DispatchQueue.main.async { w.makeFirstResponder(nil) }
        }
    }

    func popoverWillShow(_ notification: Notification) {
        liveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.engine.refreshLive()
            self?.refreshIcon()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    func makeActions() -> AppActions {
        AppActions(
            startDischarge: { [weak self] t in self?.startDischarge(target: t) },
            stopDischarge: { [weak self] in self?.stopDischarge() },
            // 뷰 body 에서 호출되므로 외부 명령 없이 캐시된 값만 반환
            dischargeState: { [weak self] in
                guard let e = self?.engine else { return (false, nil) }
                return (e.manualRunning, e.manualTarget)
            },
            changeDischargeTarget: { [weak self] t in self?.changeDischargeTarget(t) },
            permissionReady: { [weak self] in self?.engine.permissionReady ?? false },
            setupPermission: { [weak self] in self?.popover.performClose(nil); self?.setupPermission() },
            openLog: { [weak self] in self?.openLog() },
            loginEnabled: { SMAppService.mainApp.status == .enabled },
            toggleLogin: { [weak self] in self?.toggleLogin() },
            openDashboard: { [weak self] in self?.popover.performClose(nil); self?.openDashboard() },
            quit: { [weak self] in self?.quit() }
        )
    }

    // MARK: 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = isRunning
        let ext = externalRunning

        let status = NSMenuItem(title: batteryLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if running, let t = target {
            let s = NSMenuItem(title: tr("클램쉘 방전 실행 중 → \(t)%"), action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        } else if ext {
            let s = NSMenuItem(title: tr("터미널에서 방전 실행 중"), action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        let b = engine.snapshot
        let modeLine = NSMenuItem(title: "\(engine.mode.label)\(engine.target.map { tr(" · 목표 \($0)%") } ?? "")\(engine.adapterBlocked ? tr(" · 어댑터 차단") : "") · SOH \(String(format: "%.1f", b.soh))%", action: nil, keyEquivalent: "")
        modeLine.isEnabled = false
        menu.addItem(modeLine)
        menu.addItem(withTitle: tr("배터리 대시보드…"), action: #selector(openDashboard), keyEquivalent: "d").target = self
        menu.addItem(.separator())

        let maintain = NSMenuItem(title: tr("충전 유지 모드 (\(settings.maintainLevel)%)"), action: #selector(toggleMaintain), keyEquivalent: "")
        maintain.target = self
        maintain.state = settings.maintainEnabled ? .on : .off
        menu.addItem(maintain)
        let dep = NSMenuItem(title: tr("퇴근 충전 (\(settings.departureTimeText) 까지 \(settings.departureTarget)%)"), action: #selector(toggleDeparture), keyEquivalent: "")
        dep.target = self
        dep.state = settings.departureEnabled ? .on : .off
        menu.addItem(dep)
        menu.addItem(.separator())

        if !batteryInstalled {
            let m = NSMenuItem(title: tr("battery CLI 미설치"), action: nil, keyEquivalent: "")
            m.isEnabled = false
            menu.addItem(m)
        } else if !permissionReady {
            menu.addItem(withTitle: tr("권한 설정 (최초 1회)…"), action: #selector(setupPermission), keyEquivalent: "").target = self
        } else {
            let start = NSMenuItem(title: tr("방전 시작"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for t in targets {
                let mi = NSMenuItem(title: tr("\(t)% 까지"), action: #selector(startDischarge(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = t
                sub.addItem(mi)
            }
            start.submenu = sub
            if running || ext {
                // 실행 중에는 같은 자리에서 목표만 바꿈
                start.title = tr("방전 목표 변경 (지금 \(currentDischargeTarget().map { "\($0)%" } ?? "?"))")
                for mi in sub.items {
                    mi.action = #selector(changeDischargeTargetMenu(_:))
                    mi.state = mi.tag == currentDischargeTarget() ? .on : .off
                }
            }
            menu.addItem(start)
        }

        let auto = NSMenuItem(title: tr("자동 업무 모드 (전원: 덮개 닫아도 동작 / 배터리: 잠자기)"), action: permissionReady ? #selector(toggleAutoMode) : nil, keyEquivalent: "")
        auto.target = self
        auto.state = autoMode ? .on : .off
        menu.addItem(auto)
        if autoMode {
            let plugged = adapterPlugged(), closed = lidClosed(), d = externalDisplayCount()
            let st = NSMenuItem(title: tr("   지금: \(plugged ? tr("전원 연결") : tr("배터리")) · 덮개 \(closed ? tr("닫힘") : tr("열림")) · 외장 모니터 \(d)대 · 잠자기 \(sleepDisabledNow() ? tr("차단") : tr("허용"))"), action: nil, keyEquivalent: "")
            st.isEnabled = false
            menu.addItem(st)
        }
        menu.addItem(.separator())

        let stop = NSMenuItem(title: tr("방전 중지"), action: (running || ext) ? #selector(stopDischarge) : nil, keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)

        menu.addItem(.separator())
        menu.addItem(withTitle: tr("로그 보기"), action: #selector(openLog), keyEquivalent: "").target = self

        let login = NSMenuItem(title: tr("로그인 시 자동 실행"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let help = NSMenuItem(title: tr("덮개 닫힌 채 모니터/어댑터를 뽑으면 자동 중지 후 잠자기"), action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)

        menu.addItem(.separator())
        menu.addItem(withTitle: tr("종료"), action: #selector(quit), keyEquivalent: "q").target = self
    }

    // MARK: 동작

    @objc func startDischarge(_ sender: NSMenuItem) { startDischarge(target: sender.tag) }

    func startDischarge(target t: Int) {
        guard !isRunning else { return }
        FileManager.default.createFile(atPath: logPath, contents: nil) // 실행마다 새 로그
        guard let fh = FileHandle(forWritingAtPath: logPath) else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptPath, String(t)]
        p.standardOutput = fh
        p.standardError = fh
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.proc = nil
                self?.target = nil
                self?.syncManualState()
                self?.refreshIcon()
                if proc.terminationStatus != 0 && proc.terminationReason == .exit {
                    self?.notify(tr("방전 시작 실패 — 로그를 확인하세요"))
                }
            }
        }
        do {
            try p.run()
            proc = p
            target = t
            syncManualState()
            engine.tick()
            refreshIcon()
        } catch {
            notify(tr("실행 실패: \(error.localizedDescription)"))
        }
    }

    /// 실행 중인 방전의 목표 (스크립트가 10초마다 이 파일을 다시 읽음)
    func currentDischargeTarget() -> Int? {
        if let s = try? String(contentsOfFile: targetFilePath, encoding: .utf8),
           let t = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return t }
        return target
    }

    /// 다시 시작하지 않고 목표만 변경
    func changeDischargeTarget(_ t: Int) {
        let t = max(20, min(100, t))
        try? "\(t)\n".write(toFile: targetFilePath, atomically: true, encoding: .utf8)
        target = t
        syncManualState()
        refreshIcon()
    }

    @objc func changeDischargeTargetMenu(_ sender: NSMenuItem) { changeDischargeTarget(sender.tag) }

    @objc func stopDischarge() {
        if let p = proc, p.isRunning {
            p.terminate() // SIGTERM → 스크립트가 방전 해제 + 잠자기 복원
        } else {
            _ = sh("pkill -TERM -f 'clamshell-discharge [0-9]'")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.syncManualState(); self.refreshIcon() }
    }

    @objc func setupPermission() {
        let user = NSUserName()
        // pmset -a disablesleep 0/1 두 명령만 비밀번호 없이 허용. visudo 로 문법 검사 후 설치.
        let rule = "\(user) ALL = (root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let cmd = "t=$(mktemp) && printf '%s\\\\n' '\(rule)' > $t && /usr/sbin/visudo -cf $t && /usr/bin/install -m 440 -o root -g wheel $t \(sudoersPath); r=$?; rm -f $t; exit $r"
        let src = "do shell script \"\(cmd)\" with prompt \"클램쉘 방전: 잠자기 설정(pmset disablesleep)을 비밀번호 없이 바꿀 수 있도록 허용합니다.\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err = err {
            if (err[NSAppleScript.errorNumber] as? Int) != -128 { // -128 = 사용자가 취소
                notify(tr("권한 설정 실패: \(err[NSAppleScript.errorMessage] ?? "")"))
            }
        } else {
            syncManualState()
            notify(permissionReady ? tr("권한 설정 완료") : tr("권한 설정이 적용되지 않았습니다"))
        }
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            notify(tr("로그인 항목 설정 실패: \(error.localizedDescription)"))
        }
    }

    @objc func openDashboard() { DashboardWindow.show() }

    @objc func toggleMaintain() {
        settings.maintainEnabled.toggle()
        if settings.maintainEnabled { autoMode = true }
        engine.tick(); refreshIcon()
    }

    @objc func toggleDeparture() {
        settings.departureEnabled.toggle()
        engine.tick(); refreshIcon()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func notify(_ text: String) {
        let a = NSAlert()
        a.messageText = "Clamshell Discharge"
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
