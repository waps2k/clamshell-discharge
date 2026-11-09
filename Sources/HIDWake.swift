// 블루투스 키보드/마우스로 화면 깨우기
//
// 클램쉘에서 화면이 잠들면 macOS 가 블루투스 입력으로 디스플레이를 켜지 않는 경우가 있다.
// 시스템 자체는 깨어 있으므로(자동 업무 모드), 화면이 꺼져 있는 동안만 HID 입력을 감시하다가
// 입력이 오면 '사용자 활동'을 선언해 디스플레이를 켠다. 입력 내용은 읽지 않는다(발생 여부만).
// 필요한 권한: 개인정보 보호 및 보안 → 입력 모니터링

import Foundation
import IOKit.hid
import IOKit.pwr_mgt

final class HIDWaker {
    static let shared = HIDWaker()
    private var manager: IOHIDManager?
    private var lastFire = Date.distantPast
    private var assertion: IOPMAssertionID = 0
    /// 입력이 들어왔을 때 화면을 켜기 전에 할 일 (예: 어댑터 차단을 풀어 AC 로 전환)
    var onInput: (() -> Void)?

    var accessGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    /// 권한 요청 (처음엔 시스템 대화상자가 뜸). 이미 거부했으면 설정 앱에서 켜야 함.
    @discardableResult
    func requestAccess() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    var isRunning: Bool { manager != nil }

    func start() {
        guard manager == nil, accessGranted else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let usages: [(Int, Int)] = [
            (kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard),
            (kHIDPage_GenericDesktop, kHIDUsage_GD_Keypad),
            (kHIDPage_GenericDesktop, kHIDUsage_GD_Mouse),
            (kHIDPage_GenericDesktop, kHIDUsage_GD_Pointer),
            (kHIDPage_Digitizer, kHIDUsage_Dig_TouchPad),
        ]
        let matches = usages.map { [kIOHIDDeviceUsagePageKey: $0.0, kIOHIDDeviceUsageKey: $0.1] as [String: Any] }
        IOHIDManagerSetDeviceMatchingMultiple(m, matches as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<HIDWaker>.fromOpaque(ctx).takeUnretainedValue().activity()
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    func stop() {
        guard let m = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    private func activity() {
        // 마우스 이동은 초당 수십 번 오므로 2초에 한 번만
        guard Date().timeIntervalSince(lastFire) > 2 else { return }
        lastFire = Date()
        onInput?()
        IOPMAssertionDeclareUserActivity("Clamshell Discharge: Bluetooth input" as CFString,
                                         kIOPMUserActiveLocal, &assertion)
    }
}
