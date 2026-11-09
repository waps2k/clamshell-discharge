// ClamshellDischarge — 메뉴 막대에서 클램쉘 능동 방전을 시작/중지
// 실제 작업은 번들된 clamshell-discharge 스크립트가 하고, 이 앱은 시작/중지/상태 표시만 담당.

import Cocoa
import ServiceManagement

let home = FileManager.default.homeDirectoryForCurrentUser.path
let logPath = "\(home)/.battery/clamshell-discharge.log"
let sudoersPath = "/etc/sudoers.d/clamshell-discharge"
let targets = [90, 85, 80, 75, 70, 60, 50]

func sh(_ cmd: String) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var proc: Process?
    var target: Int?
    var timer: Timer?
    var autoTimer: Timer?
    var lastAutoAction = ""
    var autoMode: Bool {
        get { UserDefaults.standard.bool(forKey: "autoMode") }
        set { UserDefaults.standard.set(newValue, forKey: "autoMode") }
    }

    var scriptPath: String {
        Bundle.main.path(forResource: "clamshell-discharge", ofType: nil) ?? "\(home)/bin/clamshell-discharge"
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.delegate = self
        item.menu = menu
        refreshIcon()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.refreshIcon() }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.autoTick() }
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

    func autoTick() {
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

    var permissionReady: Bool {
        sh("sudo -n -l /usr/bin/pmset -a disablesleep 1").0 == 0
    }

    var batteryInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/local/co.palokaj.battery/battery")
    }

    func batteryLine() -> String {
        let out = sh("pmset -g batt").1
        let pct = out.range(of: #"\d+%"#, options: .regularExpression).map { String(out[$0]) } ?? "?"
        let state: String
        if out.contains("discharging") { state = "방전 중" }
        else if out.contains("charging") && !out.contains("not charging") { state = "충전 중" }
        else if out.contains("charged") { state = "충전 완료" }
        else { state = "충전 안 함" }
        return "배터리 \(pct) · \(state)"
    }

    func refreshIcon() {
        guard let b = item.button else { return }
        let running = isRunning || externalRunning
        let symbol = running ? "battery.25percent" : (autoMode ? "laptopcomputer.and.arrow.down" : "battery.100percent.bolt")
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Clamshell Discharge")
        img?.isTemplate = true
        b.image = img
        b.imagePosition = .imageLeft
        b.title = running ? (target.map { " →\($0)%" } ?? " ↓") : ""
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
            let s = NSMenuItem(title: "클램쉘 방전 실행 중 → \(t)%", action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        } else if ext {
            let s = NSMenuItem(title: "터미널에서 방전 실행 중", action: nil, keyEquivalent: "")
            s.isEnabled = false
            menu.addItem(s)
        }
        menu.addItem(.separator())

        if !batteryInstalled {
            let m = NSMenuItem(title: "battery CLI 미설치", action: nil, keyEquivalent: "")
            m.isEnabled = false
            menu.addItem(m)
        } else if !permissionReady {
            menu.addItem(withTitle: "권한 설정 (최초 1회)…", action: #selector(setupPermission), keyEquivalent: "").target = self
        } else {
            let start = NSMenuItem(title: "방전 시작", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for t in targets {
                let mi = NSMenuItem(title: "\(t)% 까지", action: #selector(startDischarge(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = t
                sub.addItem(mi)
            }
            start.submenu = sub
            start.isEnabled = !(running || ext)
            menu.addItem(start)
        }

        let auto = NSMenuItem(title: "자동 업무 모드 (전원: 덮개 닫아도 동작 / 배터리: 잠자기)", action: permissionReady ? #selector(toggleAutoMode) : nil, keyEquivalent: "")
        auto.target = self
        auto.state = autoMode ? .on : .off
        menu.addItem(auto)
        if autoMode {
            let plugged = adapterPlugged(), closed = lidClosed(), d = externalDisplayCount()
            let st = NSMenuItem(title: "   지금: \(plugged ? "전원 연결" : "배터리") · 덮개 \(closed ? "닫힘" : "열림") · 외장 모니터 \(d)대 · 잠자기 \(sleepDisabledNow() ? "차단" : "허용")", action: nil, keyEquivalent: "")
            st.isEnabled = false
            menu.addItem(st)
        }
        menu.addItem(.separator())

        let stop = NSMenuItem(title: "방전 중지", action: (running || ext) ? #selector(stopDischarge) : nil, keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)

        menu.addItem(.separator())
        menu.addItem(withTitle: "로그 보기", action: #selector(openLog), keyEquivalent: "").target = self

        let login = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let help = NSMenuItem(title: "덮개 닫힌 채 모니터/어댑터를 뽑으면 자동 중지 후 잠자기", action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)

        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
    }

    // MARK: 동작

    @objc func startDischarge(_ sender: NSMenuItem) {
        guard !isRunning else { return }
        let t = sender.tag
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
                self?.refreshIcon()
                if proc.terminationStatus != 0 && proc.terminationReason == .exit {
                    self?.notify("방전 시작 실패 — 로그를 확인하세요")
                }
            }
        }
        do {
            try p.run()
            proc = p
            target = t
            refreshIcon()
        } catch {
            notify("실행 실패: \(error.localizedDescription)")
        }
    }

    @objc func stopDischarge() {
        if let p = proc, p.isRunning {
            p.terminate() // SIGTERM → 스크립트가 방전 해제 + 잠자기 복원
        } else {
            _ = sh("pkill -TERM -f 'clamshell-discharge [0-9]'")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refreshIcon() }
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
                notify("권한 설정 실패: \(err[NSAppleScript.errorMessage] ?? "")")
            }
        } else {
            notify(permissionReady ? "권한 설정 완료" : "권한 설정이 적용되지 않았습니다")
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
            notify("로그인 항목 설정 실패: \(error.localizedDescription)")
        }
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
