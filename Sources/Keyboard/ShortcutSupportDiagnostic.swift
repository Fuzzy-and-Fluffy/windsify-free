import Foundation

enum ShortcutTestKind: String, CaseIterable, Identifiable {
    case closeWindow = "Close a window (Alt+F4)"
    case anotherShortcut = "Another shortcut"
    case liveChat = "ChatGPT / Claude copy/paste (live check)"
    var id: String { rawValue }
}

struct ShortcutSupportStatus: Equatable {
    var keyboardEnabled = false
    var keyboardRunning = false
    var accessibilityGranted = false
    var secureInput = false
    var conflictIDs: [String] = []
    var blockedByConflict = false
    var edition = "Free"

    var explanation: String? {
        if !accessibilityGranted {
            return "Windsify needs Accessibility permission to use shortcuts in other apps. Open Accessibility Settings below and allow Windsify."
        }
        if blockedByConflict {
            return "Another keyboard setting or app is pausing Windsify's shortcuts. The feedback report includes the conflict so we can help."
        }
        if !keyboardEnabled {
            return "Windows shortcuts are switched off. Turn them on below to use this shortcut in other apps."
        }
        if secureInput {
            return "macOS is protecting keyboard input, for example while a password field is active. Leave that field and try again."
        }
        if !keyboardRunning {
            return "Windsify's keyboard service is not running. The feedback report includes its status so we can help."
        }
        return nil
    }
}

/// One explicitly requested shortcut, never a character stream. These fields
/// are a closed allowlist: no characters, AX values, document titles or paths.
struct ShortcutInputSample: Equatable, Codable {
    let eventType: UInt32
    let keyCode: UInt16?
    let flags: UInt64
    let modifiers: [String]
    let keyboardType: Int64?
    let auxiliaryKeyType: Int?
    let auxiliaryState: Int?
    let source: String
}

struct ShortcutSupportResult: Equatable {
    let title: String
    let explanation: String
    let outcome: String
    let sample: ShortcutInputSample?
    let ruleID: String?
    let output: String?

    var receivedShortcut: String? {
        guard let sample else { return nil }
        guard let code = sample.keyCode else { return "Special-function key" }
        return ShortcutKeyDisplay.describe(code: code, modifiers: sample.modifiers)
    }

    static func evaluate(
        kind: ShortcutTestKind,
        sample: ShortcutInputSample,
        stroke: KeyboardStroke?,
        decision: RuleDecision?,
        status: ShortcutSupportStatus
    ) -> Self {
        if let explanation = status.explanation {
            return Self(title: "We found something to check", explanation: explanation,
                        outcome: "runtime-unavailable", sample: sample,
                        ruleID: decision?.ruleID, output: nil)
        }
        guard let stroke, let decision else {
            return Self(title: "Your Mac sent a special-function key",
                        explanation: "The top row can open features such as Spotlight instead of sending F4. Try holding Fn (Globe) together with Option (Alt) and F4. You can also send us this result with one click.",
                        outcome: "unsupported-special-key", sample: sample, ruleID: nil, output: nil)
        }
        if kind == .closeWindow,
           (stroke.keyCode != MacKeyCode.f4
            || stroke.modifiers.subtracting([.function]) != [.option]) {
            return Self(title: "We received a different shortcut",
                        explanation: "To close a window, hold Option (Alt) and press F4. On a MacBook, you may also need to hold Fn (Globe). The report already includes what your Mac received.",
                        outcome: "different-shortcut", sample: sample,
                        ruleID: decision.ruleID, output: actionDescription(decision.action))
        }
        if decision.action == .passThrough || decision.action == .suppress {
            return Self(title: "This shortcut has no replacement here",
                        explanation: "Windsify would leave this key to the app, or it is not supported in this preview. Send us the result and we can investigate without asking you to collect technical details.",
                        outcome: "no-replacement", sample: sample,
                        ruleID: decision.ruleID, output: actionDescription(decision.action))
        }
        return Self(title: "Windsify recognizes this shortcut",
                    explanation: "The key and its mapping were detected. This was a safe preview; no window was closed and no command was sent. If it still fails in another app, send us this result.",
                    outcome: "mapping-recognized-preview-only", sample: sample,
                    ruleID: decision.ruleID, output: actionDescription(decision.action))
    }

    static func endedWithoutKey(sawModifier: Bool, lostFocus: Bool, status: ShortcutSupportStatus) -> Self {
        if let explanation = status.explanation {
            return Self(title: "We found something to check", explanation: explanation,
                        outcome: "runtime-unavailable-no-key", sample: nil, ruleID: nil, output: nil)
        }
        return Self(title: lostFocus ? "The test paused when you left Windsify" : "We couldn't see the shortcut",
                    explanation: sawModifier
                        ? "We saw a modifier key, but no complete shortcut reached this test. For Alt+F4, try holding Fn (Globe) too. Your Mac may have handled a special key first; the report will help us investigate."
                        : "No complete shortcut reached this test. Click Test shortcut and press the combination while this window is active. You can still send the automatically collected status to support.",
                    outcome: lostFocus ? "focus-lost" : "no-shortcut-observed",
                    sample: nil, ruleID: nil, output: nil)
    }

    static func actionDescription(_ action: EngineAction) -> String {
        switch action {
        case .passThrough: return "Leave unchanged"
        case .suppress: return "Consume event"
        case .replace(let strokes):
            return strokes.map { stroke in
                ShortcutKeyDisplay.describe(code: stroke.keyCode, modifiers: stroke.modifiers.map(\.rawValue))
            }.joined(separator: ", ")
        case .closeFrontWindow: return "Close front window"
        case .window(let command): return "Window action: \(command.rawValue)"
        case .openApplication: return "Open application"
        case .cycleInputSource: return "Switch input source"
        case .finderClipboard: return "Finder clipboard action"
        case .captureWindow: return "Window screenshot"
        case .captureSelection: return "Frozen selection screenshot"
        }
    }
}

enum ShortcutKeyDisplay {
    static func describe(code: UInt16, modifiers: [String]) -> String {
        let labels = [("control", "Control"), ("option", "Option"),
                      ("shift", "Shift"), ("command", "Command"), ("function", "Fn")]
        let visibleModifiers = AppleActionKey.names[code] == nil
            ? modifiers : modifiers.filter { $0 != "function" }
        let prefix = labels.filter { visibleModifiers.contains($0.0) }.map { $0.1 }
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O",
            32: "U", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            48: "Tab", 49: "Space", 51: "Backspace", 53: "Escape",
            MacKeyCode.f1: "F1", MacKeyCode.f2: "F2", MacKeyCode.f3: "F3", MacKeyCode.f4: "F4",
            MacKeyCode.f5: "F5", MacKeyCode.f6: "F6", MacKeyCode.f7: "F7", MacKeyCode.f8: "F8",
            MacKeyCode.f9: "F9", MacKeyCode.f10: "F10", MacKeyCode.f11: "F11", MacKeyCode.f12: "F12",
            MacKeyCode.home: "Home", MacKeyCode.end: "End", MacKeyCode.forwardDelete: "Delete",
            MacKeyCode.leftArrow: "Left", MacKeyCode.rightArrow: "Right", MacKeyCode.upArrow: "Up", MacKeyCode.downArrow: "Down"
        ]
        return (prefix + [AppleActionKey.names[code] ?? names[code] ?? "Unrecognized key"]).joined(separator: " + ")
    }
}

/// Tracks releases even after a result appears, preventing a held shortcut
/// from escaping the preview on repeat or key-up. No second chord is saved.
struct ShortcutCaptureState {
    private(set) var isListening = false
    private(set) var sawModifier = false
    private(set) var captured = false
    private var heldKeys: Set<UInt16> = []
    private var heldAuxiliaryKeys: Set<Int> = []

    mutating func start() {
        isListening = true
        sawModifier = false
        captured = false
    }

    mutating func cancel() { isListening = false }

    mutating func modifierChanged() {
        if isListening { sawModifier = true }
    }

    mutating func consume(keyCode: UInt16?, auxiliaryKey: Int?, isDown: Bool, isRepeat: Bool = false) -> Bool {
        if let keyCode, heldKeys.contains(keyCode) {
            if isDown && isRepeat { return true }
            heldKeys.remove(keyCode)
            if !isDown { return true }
        }
        if let auxiliaryKey, heldAuxiliaryKeys.contains(auxiliaryKey) {
            if isDown && isRepeat { return true }
            heldAuxiliaryKeys.remove(auxiliaryKey)
            if !isDown { return true }
        }
        guard isListening, isDown else { return false }
        if let keyCode { heldKeys.insert(keyCode) }
        if let auxiliaryKey { heldAuxiliaryKeys.insert(auxiliaryKey) }
        captured = true
        isListening = false
        return true
    }
}
