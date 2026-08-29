import AppKit
import Carbon
import Foundation

/// Classifies Accessibility metadata without reading an element's text value.
/// Web editors frequently expose a generic role plus editable/settable
/// metadata instead of a native AXTextField or AXTextArea role.
enum TextInputAccessibilityClassifier {
    private static let nativeTextRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField",
    ]

    private static let webContainerRoles: Set<String> = [
        "AXGroup",
        "AXWebArea",
        "AXGenericContainer",
        "AXUnknown",
    ]

    static func isTextInput(
        role: String?,
        subrole: String?,
        isEditable: Bool,
        valueIsSettable: Bool,
        selectedTextRangeIsSettable: Bool
    ) -> Bool {
        if let role, nativeTextRoles.contains(role) {
            return true
        }
        if subrole == "AXSearchField" {
            return true
        }
        if isEditable || selectedTextRangeIsSettable {
            return true
        }
        guard let role, webContainerRoles.contains(role) else {
            return false
        }
        return valueIsSettable
    }
}

/// Resolves the focused control through the application that is actually
/// accepting keyboard input. System Open/Save panels can be hosted outside the
/// application's ordinary frontmost Accessibility tree.
enum AccessibilityFocusResolver {
    enum Source: String, Equatable {
        case keyboardFocusApplication
        case systemWide
        case frontmostApplication
    }

    struct Resolution<Element> {
        let element: Element
        let source: Source
    }

    static func resolve<Element>(
        systemWideElement: Element,
        focusedElement: (Element) -> Element?,
        focusedApplication: (Element) -> Element?,
        frontmostApplication: () -> Element?
    ) -> Resolution<Element>? {
        resolutions(
            systemWideElement: systemWideElement,
            focusedElement: focusedElement,
            focusedApplication: focusedApplication,
            frontmostApplication: frontmostApplication
        ).first
    }

    /// Returns every focused-element source in priority order. Some browsers
    /// expose a generic page container from the application while the
    /// system-wide Accessibility object exposes the actual web editor. Callers
    /// that classify focus should inspect all candidates instead of stopping
    /// at the first non-nil element.
    static func resolutions<Element>(
        systemWideElement: Element,
        focusedElement: (Element) -> Element?,
        focusedApplication: (Element) -> Element?,
        frontmostApplication: () -> Element?
    ) -> [Resolution<Element>] {
        var results: [Resolution<Element>] = []

        if let application = focusedApplication(systemWideElement),
           let element = focusedElement(application) {
            results.append(
                Resolution(
                    element: element,
                    source: .keyboardFocusApplication
                )
            )
        }

        if let element = focusedElement(systemWideElement) {
            results.append(
                Resolution(element: element, source: .systemWide)
            )
        }

        if let application = frontmostApplication(),
           let element = focusedElement(application) {
            results.append(
                Resolution(
                    element: element,
                    source: .frontmostApplication
                )
            )
        }

        return results
    }
}

/// Some system dialogs focus an internal child of an editable control rather
/// than the AXTextField itself. Check a small, bounded ancestor chain so Home
/// and End still recognize the surrounding editor without scanning UI content.
enum AccessibilityTextInputFocusResolver {
    static func isTextInput<Element>(
        startingAt element: Element,
        maximumAncestorDepth: Int = 4,
        classifiesAsTextInput: (Element) -> Bool,
        parent: (Element) -> Element?
    ) -> Bool {
        var current: Element? = element
        var depth = 0

        while let candidate = current,
              depth <= maximumAncestorDepth {
            if classifiesAsTextInput(candidate) {
                return true
            }
            current = parent(candidate)
            depth += 1
        }
        return false
    }
}

/// Classifies every Accessibility focus source before concluding that the
/// current control is not editable. This is important for web editors where
/// the application-level source can be a generic AXWebArea while the
/// system-wide source points at the actual text entry area.
enum AccessibilityTextInputCandidateResolver {
    static func isTextInput<Element>(
        candidates: [Element],
        maximumAncestorDepth: Int = 4,
        classifiesAsTextInput: (Element) -> Bool,
        parent: (Element) -> Element?
    ) -> Bool {
        candidates.contains { candidate in
            AccessibilityTextInputFocusResolver.isTextInput(
                startingAt: candidate,
                maximumAncestorDepth: maximumAncestorDepth,
                classifiesAsTextInput: classifiesAsTextInput,
                parent: parent
            )
        }
    }
}

/// Resolves the caret destination for native single-line fields without
/// inspecting their text. Character count is Accessibility metadata; the
/// actual element value never needs to be copied.
enum AccessibilityTextCaretResolver {
    static func location(
        forRuleID ruleID: String,
        characterCount: Int
    ) -> Int? {
        guard characterCount >= 0 else {
            return nil
        }

        switch ruleID {
        case "editing.home", "editing.control-home":
            return 0
        case "editing.end", "editing.control-end":
            return characterCount
        default:
            return nil
        }
    }
}

/// Tracks a modifier-only Windows-key tap without retaining any typed input.
/// A chord cancels the pending tap; releasing Command then opens Spotlight.
struct WindowsKeyTapTracker {
    private(set) var pressedCommandKeys: Set<UInt16> = []
    private var isCandidate = false

    mutating func observe(_ stroke: KeyboardStroke) -> Bool {
        if stroke.phase == .flagsChanged,
           stroke.keyCode == MacKeyCode.leftCommand
            || stroke.keyCode == MacKeyCode.rightCommand {
            if !pressedCommandKeys.contains(stroke.keyCode),
               stroke.modifiers.contains(.command) {
                pressedCommandKeys.insert(stroke.keyCode)
                if pressedCommandKeys.count == 1 {
                    isCandidate = true
                }
                return false
            }

            pressedCommandKeys.remove(stroke.keyCode)
            let shouldOpen = pressedCommandKeys.isEmpty && isCandidate
            if pressedCommandKeys.isEmpty {
                isCandidate = false
            }
            return shouldOpen
        }

        if !pressedCommandKeys.isEmpty,
           stroke.phase == .down {
            isCandidate = false
        }
        return false
    }
}

/// Commits a key-down replacement until the matching physical key-up. This
/// prevents a focus, secure-input, or modifier change between the two events
/// from producing a different policy decision and an unmatched synthetic key.
struct KeyboardReplacementTransactionStore {
    private var replacementsByPhysicalKey: [UInt16: [KeyboardStroke]] = [:]

    mutating func commit(
        physicalStroke: KeyboardStroke,
        replacements: [KeyboardStroke]
    ) {
        guard physicalStroke.phase == .down else {
            return
        }
        replacementsByPhysicalKey[physicalStroke.keyCode] = replacements
    }

    func keyUpReplacements(
        for physicalStroke: KeyboardStroke
    ) -> [KeyboardStroke]? {
        guard physicalStroke.phase == .up,
              let replacements = replacementsByPhysicalKey[
                  physicalStroke.keyCode
              ] else {
            return nil
        }
        return replacements.map {
            KeyboardStroke(
                keyCode: $0.keyCode,
                phase: .up,
                modifiers: $0.modifiers
            )
        }
    }

    mutating func complete(
        physicalStroke: KeyboardStroke
    ) {
        replacementsByPhysicalKey.removeValue(
            forKey: physicalStroke.keyCode
        )
    }

    func autoRepeatReplacements(
        for physicalStroke: KeyboardStroke
    ) -> [KeyboardStroke]? {
        guard physicalStroke.phase == .down,
              let replacements = replacementsByPhysicalKey[
                  physicalStroke.keyCode
              ] else {
            return nil
        }
        return replacements.map {
            KeyboardStroke(
                keyCode: $0.keyCode,
                phase: .down,
                modifiers: $0.modifiers
            )
        }
    }

    mutating func releaseAll() -> [KeyboardStroke] {
        let releases = replacementsByPhysicalKey.values.flatMap {
            replacements in
            replacements.map {
                KeyboardStroke(
                    keyCode: $0.keyCode,
                    phase: .up,
                    modifiers: $0.modifiers
                )
            }
        }
        replacementsByPhysicalKey.removeAll()
        return releases
    }

}

/// Publishes an emergency release as an all-or-nothing transaction. A partial
/// batch must never clear the committed mapping because its remaining target
/// keys would have no matching key-up.
enum KeyboardEmergencyRelease {
    static func perform<Event>(
        strokes: [KeyboardStroke],
        makeEvents: ([KeyboardStroke]) -> [Event]?,
        publish: ([Event]) -> Void,
        complete: () -> Void
    ) -> Bool {
        guard !strokes.isEmpty,
              let events = makeEvents(strokes),
              events.count == strokes.count else {
            return false
        }

        publish(events)
        complete()
        return true
    }
}

/// Converts public macOS media-key events emitted by laptop top rows into
/// ordinary F-key strokes. Unknown consumer keys fail open.
enum SystemDefinedKeyDecoder {
    // These two auxiliary-key values are emitted by modern Apple keyboards
    // but are not named in the public SDK header.
    private static let missionControlKeyType = 32
    private static let launchpadKeyType = 33

    private static let functionKeyByAuxiliaryKeyType: [Int: UInt16] = [
        Int(NX_KEYTYPE_BRIGHTNESS_DOWN): MacKeyCode.f1,
        Int(NX_KEYTYPE_BRIGHTNESS_UP): MacKeyCode.f2,
        missionControlKeyType: MacKeyCode.f3,
        Int(NX_KEYTYPE_LAUNCH_PANEL): MacKeyCode.f4,
        launchpadKeyType: MacKeyCode.f4,
        Int(NX_KEYTYPE_ILLUMINATION_DOWN): MacKeyCode.f5,
        Int(NX_KEYTYPE_ILLUMINATION_UP): MacKeyCode.f6,
        Int(NX_KEYTYPE_PREVIOUS): MacKeyCode.f7,
        Int(NX_KEYTYPE_PLAY): MacKeyCode.f8,
        Int(NX_KEYTYPE_NEXT): MacKeyCode.f9,
        Int(NX_KEYTYPE_MUTE): MacKeyCode.f10,
        Int(NX_KEYTYPE_SOUND_DOWN): MacKeyCode.f11,
        Int(NX_KEYTYPE_SOUND_UP): MacKeyCode.f12,
    ]

    static func decode(
        data1: Int,
        modifiers: Set<KeyModifier>
    ) -> KeyboardStroke? {
        let keyType = (data1 & 0xFFFF_0000) >> 16
        guard let keyCode = functionKeyByAuxiliaryKeyType[keyType] else {
            return nil
        }

        let state = (data1 & 0x0000_FF00) >> 8
        let phase: KeyPhase
        switch state {
        case 0xA:
            phase = .down
        case 0xB:
            phase = .up
        default:
            return nil
        }

        return KeyboardStroke(
            keyCode: keyCode,
            phase: phase,
            modifiers: modifiers.subtracting([.function])
        )
    }
}

enum SystemInputSourceCycler {
    static func selectNext() {
        let properties: [CFString: Any] = [
            kTISPropertyInputSourceCategory:
                kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsEnabled: true,
            kTISPropertyInputSourceIsSelectCapable: true,
        ]

        guard let rawSources = TISCreateInputSourceList(
            properties as CFDictionary,
            false
        )?.takeRetainedValue() as? [TISInputSource],
              !rawSources.isEmpty else {
            return
        }

        let current = TISCopyCurrentKeyboardInputSource()
            .takeRetainedValue()
        let currentIndex = rawSources.firstIndex {
            CFEqual($0, current)
        } ?? -1
        let nextIndex = (currentIndex + 1) % rawSources.count
        TISSelectInputSource(rawSources[nextIndex])
    }
}
