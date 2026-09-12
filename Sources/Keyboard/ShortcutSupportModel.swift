import AppKit
import Carbon
import Combine
import IOKit.hid

@MainActor
final class ShortcutSupportModel: ObservableObject {
    @Published var kind: ShortcutTestKind = .closeWindow
    @Published private(set) var isListening = false
    @Published private(set) var result: ShortcutSupportResult?
    @Published private(set) var report = ""
    @Published private(set) var status = ShortcutSupportStatus()
    @Published private(set) var feedbackMessage: String?

    var statusProvider: () -> ShortcutSupportStatus = { ShortcutSupportStatus() }
    var isApplicationActive: () -> Bool = { NSApp.isActive }
    var secureInputProvider: () -> Bool = { IsSecureEventInputEnabled() }
    var evaluate: (KeyboardStroke) -> RuleDecision = {
        KeyboardMappingEngine().evaluate($0, context: MappingContext(isTextInput: true))
    }

    private var capture = ShortcutCaptureState()
    private var localMonitor: Any?
    private var resignObserver: Any?
    private var deadline: Timer?
    private var metadata: [String] = []

    func show() {
        refresh()
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            let suppress = MainActor.assumeIsolated {
                guard let self, let cgEvent = event.cgEvent else { return false }
                return self.intercept(type: cgEvent.type, event: cgEvent, source: "app-window") == true
            }
            return suppress ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishWithoutKey(lostFocus: true) }
        }
    }

    func hide() {
        cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    func refresh() {
        status = statusProvider()
        status.secureInput = secureInputProvider()
    }

    func start() {
        refresh()
        result = nil
        report = ""
        feedbackMessage = nil
        metadata = Self.environmentSummary()
        capture.start()
        isListening = true
        deadline?.invalidate()
        deadline = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishWithoutKey(lostFocus: false) }
        }
    }

    func cancel() {
        capture.cancel()
        isListening = false
        deadline?.invalidate()
        deadline = nil
    }

    /// nil = normal translation, false = bypass translation, true = suppress.
    /// Called by the existing main-run-loop event tap before decoding, and by
    /// a local window monitor when the translation service is not running.
    func intercept(type: CGEventType, event: CGEvent, source: String = "keyboard-service") -> Bool? {
        guard event.getIntegerValueField(.eventSourceUserData) != CGEventTapController.syntheticEventMarker else { return nil }
        if type == .flagsChanged {
            guard capture.isListening, isApplicationActive() else { return nil }
            capture.modifierChanged()
            return false
        }
        var auxiliaryKey: Int?
        var auxiliaryState: Int?
        var keyCode: UInt16?
        var isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let isDown: Bool
        if type == .keyDown || type == .keyUp {
            keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            isDown = type == .keyDown
        } else if type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
            auxiliaryKey = (nsEvent.data1 >> 16) & 0xFFFF
            auxiliaryState = (nsEvent.data1 >> 8) & 0xFF
            isRepeat = (nsEvent.data1 & 1) != 0
            guard auxiliaryState == 0xA || auxiliaryState == 0xB else { return nil }
            isDown = auxiliaryState == 0xA
        } else { return nil }

        if capture.isListening && !isApplicationActive() { finishWithoutKey(lostFocus: true) }
        let wasListening = capture.isListening
        guard capture.consume(keyCode: keyCode, auxiliaryKey: auxiliaryKey, isDown: isDown, isRepeat: isRepeat) else { return nil }
        if wasListening && capture.captured {
            let stroke = CGEventTapController.keyboardStroke(from: event, type: type)
            let sample = ShortcutInputSample(
                eventType: type.rawValue, keyCode: keyCode, flags: event.flags.rawValue,
                modifiers: CGEventTapController.keyModifiers(from: event.flags).map(\.rawValue).sorted(),
                keyboardType: keyCode == nil ? nil : event.getIntegerValueField(.keyboardEventKeyboardType),
                auxiliaryKeyType: auxiliaryKey, auxiliaryState: auxiliaryState, source: source)
            let diagnostic = ShortcutSupportResult.evaluate(kind: kind, sample: sample, stroke: stroke,
                                                          decision: stroke.map(evaluate), status: status)
            complete(diagnostic)
        }
        return true
    }

    private func finishWithoutKey(lostFocus: Bool) {
        guard capture.isListening else { return }
        complete(.endedWithoutKey(sawModifier: capture.sawModifier, lostFocus: lostFocus, status: status))
    }

    private func complete(_ diagnostic: ShortcutSupportResult) {
        cancel()
        result = diagnostic
        report = Self.makeReport(kind: kind, result: diagnostic, status: status, metadata: metadata)
    }

    func prepareFeedback() {
        if report.isEmpty {
            refresh()
            report = Self.makeReport(kind: kind, result: result, status: status, metadata: Self.environmentSummary())
        }
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        feedbackMessage = "Report copied. You can paste it into your reply to Windsify Support."
    }

    func openEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "hello@windsify.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Windsify shortcut support"),
            URLQueryItem(name: "body", value: "Hi Windsify Support,\n\nI need help with this shortcut. Here is the report collected by Windsify:\n\n" + report)
        ]
        if let url = components.url, NSWorkspace.shared.open(url) {
            feedbackMessage = "Your email app will open a draft with the report. Review it and press Send when ready."
        } else {
            feedbackMessage = "We couldn't open your email app. Copy the report and email it to hello@windsify.com."
        }
    }

    static func makeReport(kind: ShortcutTestKind, result: ShortcutSupportResult?, status: ShortcutSupportStatus, metadata: [String]) -> String {
        var lines = ["Windsify shortcut report (v1)", "Test: \(kind.rawValue)",
                     "Outcome: \(result?.outcome ?? "status-only")", "Mode: safe preview; no command executed",
                     "Edition: \(status.edition)", "Keyboard enabled: \(status.keyboardEnabled)",
                     "Keyboard service running: \(status.keyboardRunning)", "Accessibility: \(status.accessibilityGranted)",
                     "Secure input: \(status.secureInput)", "Blocked by conflict: \(status.blockedByConflict)",
                     "Conflict IDs: \(status.conflictIDs.sorted().joined(separator: ", "))"]
        lines += metadata
        if let sample = result?.sample, let data = try? JSONEncoder().encode(sample), let json = String(data: data, encoding: .utf8) {
            lines.append("Input event: \(json)")
        }
        if let ruleID = result?.ruleID { lines.append("Rule: \(ruleID)") }
        if let output = result?.output { lines.append("Preview output: \(output)") }
        lines.append("Preview context: standard text input, not a live target application")
        lines.append("No typed text, clipboard content, document titles, license keys or device serial numbers included.")
        return lines.joined(separator: "\n")
    }

    private static func environmentSummary() -> [String] {
        let info = Bundle.main.infoDictionary ?? [:]
        var lines = ["App: \(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))",
                     "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            lines.append("Input source: \(Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue())")
        }
        let mode = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.keyboard.fnState"] as? Bool
        lines.append("Standard function keys preference: \(mode.map(String.init) ?? "not available")")
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                               kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let descriptions = devices.prefix(8).map { device in
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Keyboard"
            let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "unknown"
            let functionRow = FunctionRowMetadata.summary(for: device) ?? "not available"
            return "\(product.prefix(100)) [vendor \(vendor), product \(productID), \(transport.prefix(30))] [Advertised function row: \(functionRow)]"
        }.sorted()
        lines.append("Connected keyboards (event device not identified): \(descriptions.isEmpty ? "not available" : descriptions.joined(separator: "; "))")
        return lines
    }
}
