import AppKit
import ApplicationServices
import Foundation

/// Reads only the configured Spotlight search shortcut. Missing or unusable
/// evidence requires setup; it never guesses a
/// Command+Space chord that could belong to an input source or another app.
enum SpotlightShortcutPolicy {
    static func configuredShortcut(from symbolicHotKeys: Any?) -> KeyboardStroke? {
        guard let hotKeys = symbolicHotKeys as? [String: Any],
              let entry = hotKeys["64"] as? [String: Any],
              integer(entry["enabled"], allowsBoolean: true) == 1,
              let value = entry["value"] as? [String: Any],
              value["type"] as? String == "standard",
              let parameters = value["parameters"] as? [Any],
              parameters.count == 3,
              integer(parameters[0]) != nil,
              let keyCode = integer(parameters[1]),
              (0...127).contains(keyCode),
              !(54...63).contains(keyCode),
              let flags = integer(parameters[2]), flags >= 0 else {
            return nil
        }

        let supportedFlags: [(CGEventFlags, KeyModifier)] = [
            (.maskCommand, .command), (.maskControl, .control),
            (.maskAlternate, .option), (.maskShift, .shift),
            (.maskSecondaryFn, .function),
        ]
        let mask = supportedFlags.reduce(UInt64(0)) { $0 | $1.0.rawValue }
        guard UInt64(flags) & ~mask == 0 else { return nil }
        let modifiers = Set(supportedFlags.compactMap { flag, modifier in
            UInt64(flags) & flag.rawValue != 0 ? modifier : nil
        })
        return KeyboardStroke(keyCode: UInt16(keyCode), modifiers: modifiers)
    }

    private static func integer(_ value: Any?, allowsBoolean: Bool = false) -> Int64? {
        guard let number = value as? NSNumber,
              allowsBoolean || CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue == Double(number.int64Value) else { return nil }
        return number.int64Value
    }
}

/// Both Windows-key activation paths use this adapter. It installs no input
/// listener and changes no system shortcut preferences.
final class SystemSpotlightActivation {
    enum Outcome: String { case testHost, shortcutUnavailable, eventCreationFailed, actionRequested }
    enum Failure: Equatable { case shortcutUnavailable, eventCreationFailed }

    static let shared = SystemSpotlightActivation()

    private let isTestHost: () -> Bool
    private let shortcutProvider: () -> KeyboardStroke?
    private let eventBuilder: ([KeyboardStroke]) -> [CGEvent]?
    private let publish: ([CGEvent]) -> Void
    private let reportFailure: (Failure) -> Void
    private var failureWasReported = false

    init(
        isTestHost: @escaping () -> Bool = { InputRuntimeSafety.isTestHost },
        shortcutProvider: @escaping () -> KeyboardStroke? = SystemSpotlightActivation.configuredShortcut,
        eventBuilder: @escaping ([KeyboardStroke]) -> [CGEvent]? = SystemSpotlightActivation.events,
        publish: @escaping ([CGEvent]) -> Void = { events in
            guard !InputRuntimeSafety.isTestHost else { return }
            for event in events { event.post(tap: .cgSessionEventTap) }
        },
        reportFailure: @escaping (Failure) -> Void = SystemSpotlightActivation.showFailure
    ) {
        self.isTestHost = isTestHost
        self.shortcutProvider = shortcutProvider
        self.eventBuilder = eventBuilder
        self.publish = publish
        self.reportFailure = reportFailure
    }

    @discardableResult
    func activate() -> Outcome {
        guard !isTestHost() else { return .testHost }
        guard let shortcut = shortcutProvider() else {
            reportOnce(.shortcutUnavailable)
            return .shortcutUnavailable
        }
        let strokes = [KeyPhase.down, .up].map {
            KeyboardStroke(keyCode: shortcut.keyCode, phase: $0, modifiers: shortcut.modifiers)
        }
        guard let events = eventBuilder(strokes), events.count == strokes.count else {
            reportOnce(.eventCreationFailed)
            return .eventCreationFailed
        }
        publish(events)
        failureWasReported = false
        // Posting the configured input is not proof that Spotlight appeared.
        return .actionRequested
    }

    private func reportOnce(_ failure: Failure) {
        // Repeats must not open a chain of modal alerts. Publishing a configured
        // shortcut makes a later, new failure reportable.
        guard !failureWasReported else { return }
        failureWasReported = true
        reportFailure(failure)
    }

    static func events(for strokes: [KeyboardStroke]) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return nil }
        var events: [CGEvent] = []
        for stroke in strokes {
            guard stroke.phase != .flagsChanged,
                  let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: CGKeyCode(stroke.keyCode),
                                      keyDown: stroke.phase == .down) else { return nil }
            event.flags = CGEventTapController.composedFlags(
                targetShape: [], ambient: [], modifiers: stroke.modifiers)
            event.setIntegerValueField(.eventSourceUserData,
                                       value: CGEventTapController.syntheticEventMarker)
            events.append(event)
        }
        return events
    }

    private static func configuredShortcut() -> KeyboardStroke? {
        let domain = "com.apple.symbolichotkeys" as CFString
        return readConfiguredShortcut(isTestHost: { InputRuntimeSafety.isTestHost }, synchronize: {
            // Refresh external System Settings changes. AppSynchronize can write
            // pending edits, but Windsify never sets/removes values in this domain.
            CFPreferencesAppSynchronize(domain)
        }, read: {
            CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain)
        })
    }

    static func readConfiguredShortcut(isTestHost: () -> Bool, synchronize: () -> Bool,
                                       read: () -> Any?) -> KeyboardStroke? {
        guard !isTestHost(), synchronize() else { return nil }
        return SpotlightShortcutPolicy.configuredShortcut(from: read())
    }

    private static func showFailure(_ failure: Failure) {
        guard !InputRuntimeSafety.isTestHost else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("Spotlight could not open")
        switch failure {
        case .shortcutUnavailable:
            alert.informativeText = L10n.text("Windsify cannot open Spotlight because Show Spotlight search is disabled or its shortcut is unavailable. In System Settings > Keyboard > Keyboard Shortcuts > Spotlight, enable Show Spotlight search and choose a shortcut that does not conflict with input-source switching, then try again.")
        case .eventCreationFailed:
            alert.informativeText = L10n.text("Windsify could not send the configured Spotlight shortcut. Restart Windsify and try again. You can still open Spotlight from the menu bar.")
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("OK"))
        alert.runModal()
    }
}
