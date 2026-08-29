import AppKit
import ApplicationServices
import Carbon
import Foundation

enum CGEventTapControllerError: Error, Equatable, LocalizedError {
    case accessibilityPermissionMissing
    case alreadyRunning
    case anotherControllerIsActive
    case eventTapCreationFailed
    case mustStartOnMainThread

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required for keyboard translation."
        case .alreadyRunning:
            return "The keyboard translation engine is already running."
        case .anotherControllerIsActive:
            return "Another Windsify keyboard event tap is already active."
        case .eventTapCreationFailed:
            return "macOS could not create the keyboard event tap."
        case .mustStartOnMainThread:
            return "The keyboard engine must start on the main thread."
        }
    }
}

/// Builds replacement sequences from the original event's state table. Every
/// event in one sequence shares a source, so its down/up pair is coherent. If
/// the originating source cannot be reopened, the current login-session state
/// is the documented fallback for an app posting inside that session.
struct SyntheticKeyboardEventFactory {
    typealias SourceProvider = (_ originalEvent: CGEvent) -> CGEventSource?

    private let sourceProvider: SourceProvider

    init(
        sourceProvider: @escaping SourceProvider =
            SyntheticKeyboardEventFactory.sourceForOriginalEvent
    ) {
        self.sourceProvider = sourceProvider
    }

    func events(
        for strokes: [KeyboardStroke],
        preservingAutoRepeatFrom originalEvent: CGEvent
    ) -> [CGEvent]? {
        guard let source = sourceProvider(originalEvent) else {
            return nil
        }

        var events: [CGEvent] = []
        events.reserveCapacity(strokes.count)

        for stroke in strokes {
            guard stroke.phase != .flagsChanged,
                  let event = CGEvent(
                      keyboardEventSource: source,
                      virtualKey: CGKeyCode(stroke.keyCode),
                      keyDown: stroke.phase == .down
                  ) else {
                return nil
            }

            event.flags = CGEventTapController.composedFlags(
                targetShape: event.flags,
                ambient: originalEvent.flags,
                modifiers: stroke.modifiers
            )
            event.setIntegerValueField(
                .eventSourceUserData,
                value: CGEventTapController.syntheticEventMarker
            )
            event.setIntegerValueField(
                .keyboardEventAutorepeat,
                value: originalEvent.getIntegerValueField(
                    .keyboardEventAutorepeat
                )
            )
            events.append(event)
        }

        return events
    }

    private static func sourceForOriginalEvent(
        _ originalEvent: CGEvent
    ) -> CGEventSource? {
        if let source = CGEventSource(event: originalEvent) {
            return source
        }
        return CGEventSource(stateID: .combinedSessionState)
    }
}

/// Owns the application's single active keyboard event tap.
///
/// Shortcut policy lives behind `KeyboardMappingEvaluating`; this class only adapts
/// Core Graphics events to policy inputs and dispatches the resulting actions.
/// It never observes or stores the characters represented by a key event.
final class CGEventTapController {
    typealias ContextProvider = () -> MappingContext
    typealias ApplicationOpener = (_ bundleIdentifier: String) -> Void
    typealias InputSourceCycler = () -> Void
    typealias ExtendedActionHandler = (
        _ action: EngineAction,
        _ originalEvent: CGEvent,
        _ proxy: CGEventTapProxy
    ) -> ExtendedKeyboardActionDisposition?

    private enum ReplacementDispatchResult {
        case failed
        case posted
        case rewroteOriginal
    }

    // "WIND" encoded as an integer. Synthetic events are tagged with this
    // marker and immediately passed through if they ever re-enter our tap.
    static let syntheticEventMarker: Int64 = 0x5749_4E44
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!

    private static let ownershipLock = NSLock()
    private static weak var activeController: CGEventTapController?

    private let engine: any KeyboardMappingEvaluating
    private let contextProvider: ContextProvider
    private let applicationOpener: ApplicationOpener
    private let inputSourceCycler: InputSourceCycler
    private let extendedActionHandler: ExtendedActionHandler
    private let syntheticEventFactory: SyntheticKeyboardEventFactory

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var windowsKeyTapTracker = WindowsKeyTapTracker()
    private var replacementTransactions =
        KeyboardReplacementTransactionStore()

    /// The event tap remains useful for keyboard translation when window
    /// management is disabled. In that state, physical Win window shortcuts
    /// pass through instead of invoking the window controller.
    var windowActionsEnabled = true

    var isRunning: Bool {
        eventTap != nil
    }

    init(
        engine: any KeyboardMappingEvaluating = KeyboardMappingEngine(),
        contextProvider: @escaping ContextProvider = CGEventTapController.frontmostContext,
        applicationOpener: @escaping ApplicationOpener = CGEventTapController.openApplication,
        inputSourceCycler: @escaping InputSourceCycler = SystemInputSourceCycler.selectNext,
        syntheticEventFactory: SyntheticKeyboardEventFactory =
            SyntheticKeyboardEventFactory(),
        extendedActionHandler: @escaping ExtendedActionHandler = {
            _, _, _ in nil
        }
    ) {
        self.engine = engine
        self.contextProvider = contextProvider
        self.applicationOpener = applicationOpener
        self.inputSourceCycler = inputSourceCycler
        self.syntheticEventFactory = syntheticEventFactory
        self.extendedActionHandler = extendedActionHandler

        #if !DEBUG
        Self.removeLegacyKeyboardFocusDiagnosticState()
        #endif
    }

    deinit {
        stop()
    }

    func start() throws {
        guard Thread.isMainThread else {
            throw CGEventTapControllerError.mustStartOnMainThread
        }
        guard AXIsProcessTrusted() else {
            throw CGEventTapControllerError.accessibilityPermissionMissing
        }
        guard eventTap == nil else {
            throw CGEventTapControllerError.alreadyRunning
        }

        Self.ownershipLock.lock()
        defer { Self.ownershipLock.unlock() }

        if let activeController = Self.activeController,
           activeController !== self,
           activeController.isRunning {
            throw CGEventTapControllerError.anotherControllerIsActive
        }

        let eventMask = Self.eventMask(for: [
            .keyDown,
            .keyUp,
            .flagsChanged,
            Self.systemDefinedEventType,
        ])

        guard let newEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw CGEventTapControllerError.eventTapCreationFailed
        }

        guard let newRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            newEventTap,
            0
        ) else {
            CFMachPortInvalidate(newEventTap)
            throw CGEventTapControllerError.eventTapCreationFailed
        }

        eventTap = newEventTap
        runLoopSource = newRunLoopSource
        Self.activeController = self

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            newRunLoopSource,
            .commonModes
        )
        CGEvent.tapEnable(tap: newEventTap, enable: true)
    }

    func stop() {
        let releases = replacementTransactions.releaseAll()
        if let events = Self.emergencyReleaseEvents(for: releases) {
            for event in events {
                event.post(tap: .cgSessionEventTap)
            }
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        Self.ownershipLock.lock()
        if Self.activeController === self {
            Self.activeController = nil
        }
        Self.ownershipLock.unlock()
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        proxy,
        type,
        event,
        userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<CGEventTapController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        return controller.handleEvent(
            proxy: proxy,
            type: type,
            event: event
        )
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.eventSourceUserData)
            != Self.syntheticEventMarker else {
            return Unmanaged.passUnretained(event)
        }

        guard let stroke = Self.keyboardStroke(from: event, type: type) else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
           let replacements = replacementTransactions
               .autoRepeatReplacements(for: stroke) {
            switch dispatchReplacements(
                replacements,
                originalEvent: event,
                type: type,
                proxy: proxy
            ) {
            case .failed:
                return Unmanaged.passUnretained(event)
            case .posted:
                return nil
            case .rewroteOriginal:
                return Unmanaged.passUnretained(event)
            }
        }

        if let replacements = replacementTransactions
            .keyUpReplacements(for: stroke) {
            switch dispatchReplacements(
                replacements,
                originalEvent: event,
                type: type,
                proxy: proxy
            ) {
            case .failed:
                if recoverCommittedReplacement(
                    physicalStroke: stroke,
                    releases: replacements
                ) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            case .posted:
                replacementTransactions.complete(physicalStroke: stroke)
                return nil
            case .rewroteOriginal:
                replacementTransactions.complete(physicalStroke: stroke)
                return Unmanaged.passUnretained(event)
            }
        }

        if stroke.phase == .down,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           let staleReleases = replacementTransactions.keyUpReplacements(
               for: KeyboardStroke(
                   keyCode: stroke.keyCode,
                   phase: .up
               )
           ),
           !recoverCommittedReplacement(
               physicalStroke: stroke,
               releases: staleReleases
           ) {
            // Do not overwrite an unreleased target or pass through a new
            // physical key-down whose later key-up belongs to that target.
            return nil
        }

        if passesThroughBeforeContext(stroke) {
            Self.normalizeNativeShiftSelectionEvent(
                event,
                stroke: stroke
            )
            return Unmanaged.passUnretained(event)
        }

        let context = contextProvider()
        let decision = engine.evaluate(
            stroke,
            context: context
        )
        let accessibilityTextNavigationHandled =
            moveNativeSingleLineCaretIfSupported(
                for: decision,
                stroke: stroke
            )
        #if DEBUG
        KeyboardFocusDiagnostics.recordIfEnabled(
            stroke: stroke,
            decision: decision
        )
        #endif
        if accessibilityTextNavigationHandled {
            return nil
        }

        switch decision.action {
        case .passThrough:
            if type == Self.systemDefinedEventType,
               decision.ruleID == "native.unmapped" {
                guard let events = syntheticEventFactory.events(
                    for: [stroke],
                    preservingAutoRepeatFrom: event
                ) else {
                    return Unmanaged.passUnretained(event)
                }
                post(events, proxy: proxy)
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .suppress:
            return nil

        case let .replace(replacements):
            let result = dispatchReplacements(
                replacements,
                originalEvent: event,
                type: type,
                proxy: proxy
            )
            switch result {
            case .failed:
                return Unmanaged.passUnretained(event)
            case .posted:
                replacementTransactions.commit(
                    physicalStroke: stroke,
                    replacements: replacements
                )
                return nil
            case .rewroteOriginal:
                replacementTransactions.commit(
                    physicalStroke: stroke,
                    replacements: replacements
                )
                return Unmanaged.passUnretained(event)
            }

        case .window:
            guard windowActionsEnabled else {
                return Unmanaged.passUnretained(event)
            }
            return dispatchExtendedAction(
                decision.action,
                event: event,
                proxy: proxy
            )

        case .cycleInputSource:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                return nil
            }
            DispatchQueue.main.async { [inputSourceCycler] in
                inputSourceCycler()
            }
            return nil

        case .openApplication, .finderClipboard, .closeFrontWindow,
             .captureWindow:
            return dispatchExtendedAction(
                decision.action,
                event: event,
                proxy: proxy
            )
        }
    }

    private func dispatchExtendedAction(
        _ action: EngineAction,
        event: CGEvent,
        proxy: CGEventTapProxy
    ) -> Unmanaged<CGEvent>? {
        switch extendedActionHandler(action, event, proxy) {
        case .suppress:
            return nil
        case .passThrough, nil:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Updates modifier-only Windows-key tracking before any potentially slow
    /// Accessibility query. Non-Command modifier changes and plain
    /// Shift+Arrow are guaranteed to leave through the tap immediately.
    func passesThroughBeforeContext(_ stroke: KeyboardStroke) -> Bool {
        let shouldOpenSpotlight = windowsKeyTapTracker.observe(stroke)

        if stroke.phase == .flagsChanged {
            if shouldOpenSpotlight {
                let context = contextProvider()
                if engine.permitsHostShortcut(in: context) {
                    DispatchQueue.main.async { [applicationOpener] in
                        applicationOpener("com.apple.Spotlight")
                    }
                }
            }
            return true
        }

        guard let decision = engine.contextFreeDecision(for: stroke) else {
            return false
        }
        return decision.action == .passThrough
    }

    private func dispatchReplacements(
        _ replacements: [KeyboardStroke],
        originalEvent: CGEvent,
        type: CGEventType,
        proxy: CGEventTapProxy
    ) -> ReplacementDispatchResult {
        if replacements.count == 1,
           let replacement = replacements.first,
           Self.rewrite(
               originalEvent,
               ofType: type,
               with: replacement
           ) {
            return .rewroteOriginal
        }

        guard let events = syntheticEventFactory.events(
            for: replacements,
            preservingAutoRepeatFrom: originalEvent
        ) else {
            return .failed
        }
        post(events, proxy: proxy)
        return .posted
    }

    private func recoverCommittedReplacement(
        physicalStroke: KeyboardStroke,
        releases: [KeyboardStroke]
    ) -> Bool {
        KeyboardEmergencyRelease.perform(
            strokes: releases,
            makeEvents: Self.emergencyReleaseEvents,
            publish: { events in
                for event in events {
                    event.post(tap: .cgSessionEventTap)
                }
            },
            complete: { [self] in
                replacementTransactions.complete(
                    physicalStroke: physicalStroke
                )
            }
        )
    }

    private func post(
        _ events: [CGEvent],
        proxy: CGEventTapProxy
    ) {
        for event in events {
            event.tapPostEvent(proxy)
        }
    }

    /// Rewrites a same-key modifier mapping on the event already owned by the
    /// tap. This avoids suppress-then-post gaps and preserves the originating
    /// event source, timestamp, keyboard type, and key-shape flags.
    static func rewrite(
        _ event: CGEvent,
        ofType type: CGEventType,
        with stroke: KeyboardStroke
    ) -> Bool {
        let expectedType: CGEventType
        switch stroke.phase {
        case .down:
            expectedType = .keyDown
        case .up:
            expectedType = .keyUp
        case .flagsChanged:
            return false
        }
        guard type == expectedType else {
            return false
        }
        guard event.getIntegerValueField(.keyboardEventKeycode)
            == Int64(stroke.keyCode) else {
            return false
        }

        event.setIntegerValueField(
            .keyboardEventKeycode,
            value: Int64(stroke.keyCode)
        )
        event.flags = composedFlags(
            targetShape: event.flags,
            ambient: event.flags,
            modifiers: stroke.modifiers
        )
        event.setIntegerValueField(
            .eventSourceUserData,
            value: syntheticEventMarker
        )
        return true
    }

    static func keyboardStroke(
        from event: CGEvent,
        type: CGEventType
    ) -> KeyboardStroke? {
        if type == Self.systemDefinedEventType,
           let appKitEvent = NSEvent(cgEvent: event),
           appKitEvent.subtype.rawValue == 8 {
            return SystemDefinedKeyDecoder.decode(
                data1: appKitEvent.data1,
                modifiers: keyModifiers(from: event.flags)
            )
        }

        let phase: KeyPhase
        switch type {
        case .keyDown:
            phase = .down
        case .keyUp:
            phase = .up
        case .flagsChanged:
            phase = .flagsChanged
        default:
            return nil
        }

        let keyCode = UInt16(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        var modifiers = keyModifiers(from: event.flags)
        if [
            MacKeyCode.home,
            MacKeyCode.end,
            MacKeyCode.leftArrow,
            MacKeyCode.rightArrow,
            MacKeyCode.downArrow,
            MacKeyCode.upArrow,
        ].contains(keyCode) {
            modifiers.remove(.function)
        }

        return KeyboardStroke(
            keyCode: keyCode,
            phase: phase,
            modifiers: modifiers
        )
    }

    /// External navigation keys can arrive with SecondaryFn as a key-shape
    /// flag. Leaving it on a native Shift+Arrow event lets macOS interpret the
    /// event as an enabled Fn+Shift symbolic shortcut before the text control
    /// sees it. Remove only that shape flag while preserving Shift, NumericPad,
    /// the originating source, and left/right device-specific state.
    @discardableResult
    static func normalizeNativeShiftSelectionEvent(
        _ event: CGEvent,
        stroke: KeyboardStroke
    ) -> Bool {
        guard stroke.phase == .down || stroke.phase == .up,
              [
                  MacKeyCode.leftArrow,
                  MacKeyCode.rightArrow,
                  MacKeyCode.downArrow,
                  MacKeyCode.upArrow,
              ].contains(stroke.keyCode),
              stroke.modifiers == [.shift],
              event.flags.contains(.maskSecondaryFn) else {
            return false
        }

        event.flags.remove(.maskSecondaryFn)
        return true
    }

    static func keyModifiers(
        from flags: CGEventFlags
    ) -> Set<KeyModifier> {
        var modifiers: Set<KeyModifier> = []
        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.function)
        }
        return modifiers
    }

    static func cgEventFlags(
        from modifiers: Set<KeyModifier>
    ) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }
        if modifiers.contains(.function) {
            flags.insert(.maskSecondaryFn)
        }
        return flags
    }

    static func composedFlags(
        targetShape: CGEventFlags,
        ambient: CGEventFlags,
        modifiers: Set<KeyModifier>
    ) -> CGEventFlags {
        let shortcutModifierFlags: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift,
        ]
        let ambientFlags: CGEventFlags = [
            .maskAlphaShift,
            .maskNonCoalesced,
        ]
        var flags = targetShape.subtracting(shortcutModifierFlags)
        flags.formUnion(ambient.intersection(ambientFlags))
        flags.formUnion(
            cgEventFlags(from: modifiers)
                .intersection(shortcutModifierFlags)
        )
        if modifiers.contains(.function) {
            flags.insert(.maskSecondaryFn)
        }
        return flags
    }

    static func emergencyReleaseEvents(
        for strokes: [KeyboardStroke]
    ) -> [CGEvent]? {
        guard let source = CGEventSource(
            stateID: .combinedSessionState
        ) else {
            return nil
        }

        var events: [CGEvent] = []
        events.reserveCapacity(strokes.count)
        for stroke in strokes {
            guard stroke.phase == .up,
                  let event = CGEvent(
                      keyboardEventSource: source,
                      virtualKey: CGKeyCode(stroke.keyCode),
                      keyDown: false
                  ) else {
                return nil
            }
            event.flags = composedFlags(
                targetShape: event.flags,
                ambient: [],
                modifiers: stroke.modifiers
            )
            event.setIntegerValueField(
                .eventSourceUserData,
                value: syntheticEventMarker
            )
            events.append(event)
        }
        return events
    }

    private static func eventMask(
        for types: [CGEventType]
    ) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }

    private static func openApplication(_ bundleIdentifier: String) {
        guard let applicationURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: { _, _ in }
        )
    }

    private static func frontmostContext() -> MappingContext {
        MappingContext(
            bundleIdentifier: NSWorkspace.shared
                .frontmostApplication?
                .bundleIdentifier,
            isTextInput: focusedElementIsTextInput(),
            isSecureInput: IsSecureEventInputEnabled()
        )
    }

    private static func focusedElementIsTextInput() -> Bool {
        var seenElements: Set<AXUIElement> = []
        let candidates = focusedUIElementResolutions()
            .map(\.element)
            .filter { seenElements.insert($0).inserted }

        return AccessibilityTextInputCandidateResolver.isTextInput(
            candidates: candidates,
            classifiesAsTextInput: elementIsTextInput,
            parent: { element in
                elementAttribute(
                    kAXParentAttribute as CFString,
                    of: element
                )
            }
        )
    }

    private static func elementIsTextInput(_ element: AXUIElement) -> Bool {
        return TextInputAccessibilityClassifier.isTextInput(
            role: stringAttribute(
                kAXRoleAttribute as CFString,
                of: element
            ),
            subrole: stringAttribute(
                kAXSubroleAttribute as CFString,
                of: element
            ),
            isEditable: boolAttribute(
                kAXIsEditableAttribute as CFString,
                of: element
            ),
            valueIsSettable: attributeIsSettable(
                kAXValueAttribute as CFString,
                of: element
            ),
            selectedTextRangeIsSettable: attributeIsSettable(
                kAXSelectedTextRangeAttribute as CFString,
                of: element
            )
        )
    }

    private static func focusedUIElementResolution()
        -> AccessibilityFocusResolver.Resolution<AXUIElement>? {
        focusedUIElementResolutions().first
    }

    private static func focusedUIElementResolutions()
        -> [AccessibilityFocusResolver.Resolution<AXUIElement>] {
        let systemWideElement = AXUIElementCreateSystemWide()
        return AccessibilityFocusResolver.resolutions(
            systemWideElement: systemWideElement,
            focusedElement: { element in
                elementAttribute(
                    kAXFocusedUIElementAttribute as CFString,
                    of: element
                )
            },
            focusedApplication: { element in
                elementAttribute(
                    kAXFocusedApplicationAttribute as CFString,
                    of: element
                )
            },
            frontmostApplication: {
                guard let processIdentifier = NSWorkspace.shared
                    .frontmostApplication?
                    .processIdentifier else {
                    return nil
                }
                return AXUIElementCreateApplication(processIdentifier)
            }
        )
    }

    /// Native single-line fields hosted by system sheets can ignore synthetic
    /// Command+Arrow events even though they accept Accessibility selection
    /// changes. Move the insertion caret directly when the required metadata
    /// is available, then let the ordinary replacement remain the fallback
    /// for web editors, text areas, and controls with incomplete AX support.
    private func moveNativeSingleLineCaretIfSupported(
        for decision: RuleDecision,
        stroke: KeyboardStroke
    ) -> Bool {
        let directRuleIDs: Set<String> = [
            "editing.home",
            "editing.end",
            "editing.control-home",
            "editing.control-end",
        ]
        guard directRuleIDs.contains(decision.ruleID),
              stroke.phase != .flagsChanged,
              let resolution = Self.focusedUIElementResolution(),
              let element = Self.singleLineTextElement(
                  startingAt: resolution.element
              ),
              let characterCount = Self.integerAttribute(
                  kAXNumberOfCharactersAttribute as CFString,
                  of: element
              ),
              let location = AccessibilityTextCaretResolver.location(
                  forRuleID: decision.ruleID,
                  characterCount: characterCount
              ) else {
            return false
        }

        var range = CFRange(location: location, length: 0)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return false
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
    }

    private static func singleLineTextElement(
        startingAt element: AXUIElement,
        maximumAncestorDepth: Int = 4
    ) -> AXUIElement? {
        let supportedRoles: Set<String> = [
            "AXTextField",
            "AXSearchField",
            "AXComboBox",
        ]
        var current: AXUIElement? = element

        for _ in 0...maximumAncestorDepth {
            guard let candidate = current else {
                break
            }
            if let role = stringAttribute(
                kAXRoleAttribute as CFString,
                of: candidate
            ),
               supportedRoles.contains(role),
               attributeIsSettable(
                   kAXSelectedTextRangeAttribute as CFString,
                   of: candidate
               ) {
                return candidate
            }
            current = elementAttribute(
                kAXParentAttribute as CFString,
                of: candidate
            )
        }
        return nil
    }

    #if !DEBUG
    /// Removes snapshots written by pre-release developer builds that used the
    /// production bundle identifier. Release builds contain no recorder.
    private static func removeLegacyKeyboardFocusDiagnosticState(
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(
            forKey: "keyboardFocusDiagnosticsEnabled"
        )
        defaults.removeObject(
            forKey: "keyboardFocusDiagnosticSnapshot"
        )
    }
    #endif

    private static func elementAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> AXUIElement? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &rawValue
        ) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private static func stringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &rawValue
        ) == .success else {
            return nil
        }
        return rawValue as? String
    }

    private static func boolAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> Bool {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &rawValue
        ) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue((rawValue as! CFBoolean))
    }

    private static func integerAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> Int? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &rawValue
        ) == .success,
              let number = rawValue as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private static func attributeIsSettable(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> Bool {
        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            attribute,
            &isSettable
        ) == .success else {
            return false
        }
        return isSettable.boolValue
    }
}

#if DEBUG
/// Opt-in developer diagnostics for Home/End rule selection. Keep this type
/// behind the DEBUG compilation condition so production builds cannot write
/// keyboard event metadata. Even in Debug, persist only the minimum values
/// permitted by the repository privacy policy.
enum KeyboardFocusDiagnostics {
    static let enabledDefaultsKey = "keyboardFocusDiagnosticsEnabled"
    static let snapshotDefaultsKey = "keyboardFocusDiagnosticSnapshot"

    static func recordIfEnabled(
        stroke: KeyboardStroke,
        decision: RuleDecision,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.bool(forKey: enabledDefaultsKey),
              stroke.keyCode == MacKeyCode.home
                || stroke.keyCode == MacKeyCode.end else {
            return
        }

        defaults.set(
            [
                "keyCode": Int(stroke.keyCode),
                "ruleID": decision.ruleID,
            ],
            forKey: snapshotDefaultsKey
        )
    }
}
#endif
