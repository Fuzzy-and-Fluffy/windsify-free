import Foundation

/// The public Windsify Free keyboard policy.
///
/// This intentionally implements only Windows keyboard essentials. Complete
/// Finder, system, screenshot, application-launch and window-management rules
/// live in the private Pro policy and are not dependencies of this type.
struct KeyboardMappingEngine: KeyboardMappingEvaluating, Sendable {
    static let defaultTerminalBundleIdentifiers: Set<String> = [
        "co.zeit.hyper",
        "com.apple.terminal",
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.warp",
        "dev.warp.warp-stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
    ]

    static let defaultBrowserBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.brave.browser",
        "com.google.chrome",
        "com.google.chrome.beta",
        "com.google.chrome.canary",
        "com.microsoft.edgemac",
        "com.operasoftware.opera",
        "com.operasoftware.operagx",
        "company.thebrowser.browser",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
    ]

    static let defaultRemoteDesktopBundleIdentifiers: Set<String> = [
        "com.citrix.xenappviewer",
        "com.jumpdesktop.jumpdesktop",
        "com.microsoft.rdc.macos",
        "com.microsoft.windowsapp",
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "org.virtualbox.app.virtualboxvm",
    ]

    private let terminalBundleIdentifiers: Set<String>
    private let browserBundleIdentifiers: Set<String>
    private let remoteDesktopBundleIdentifiers: Set<String>

    init(
        terminalBundleIdentifiers: Set<String> =
            Self.defaultTerminalBundleIdentifiers,
        browserBundleIdentifiers: Set<String> =
            Self.defaultBrowserBundleIdentifiers,
        remoteDesktopBundleIdentifiers: Set<String> =
            Self.defaultRemoteDesktopBundleIdentifiers
    ) {
        self.terminalBundleIdentifiers = Set(
            terminalBundleIdentifiers.map { $0.lowercased() }
        )
        self.browserBundleIdentifiers = Set(
            browserBundleIdentifiers.map { $0.lowercased() }
        )
        self.remoteDesktopBundleIdentifiers = Set(
            remoteDesktopBundleIdentifiers.map { $0.lowercased() }
        )
    }

    func evaluate(
        _ stroke: KeyboardStroke,
        context: MappingContext = MappingContext()
    ) -> RuleDecision {
        if let decision = contextFreeDecision(for: stroke) {
            return decision
        }

        guard !context.isSecureInput else {
            return passThrough(ruleID: "native.secure-input")
        }

        if isRemoteDesktop(context) {
            return passThrough(ruleID: "native.remote-desktop")
        }

        if stroke.keyCode == MacKeyCode.space,
           stroke.modifiers == [.control] {
            return passThrough(ruleID: "native.control-space")
        }

        if stroke.keyCode == MacKeyCode.tab,
           stroke.modifiers == [.control]
            || stroke.modifiers == [.control, .shift] {
            return passThrough(ruleID: "native.control-tab")
        }

        // Free retains the Windows input-source gesture because it is a basic
        // keyboard compatibility behavior, not application automation.
        if stroke.keyCode == MacKeyCode.space,
           stroke.modifiers == [.command] {
            return activationDecision(
                for: stroke.phase,
                ruleID: "windows.input-source",
                action: .cycleInputSource
            )
        }

        // Terminal Control chords must remain terminal control sequences.
        // Pro adds Windows Terminal application actions before this safety
        // fallback; Free deliberately does not.
        if isTerminal(context), stroke.modifiers.contains(.control) {
            return passThrough(ruleID: "terminal.native-control")
        }

        if stroke.keyCode == MacKeyCode.y,
           stroke.modifiers == [.control] {
            return replacingModifiers(
                in: stroke,
                with: [.command, .shift],
                ruleID: "generic.control-y-redo"
            )
        }

        if context.isTextInput,
           stroke.keyCode == MacKeyCode.home {
            switch stroke.modifiers.subtracting([.function]) {
            case []:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.leftArrow,
                    modifiers: [.command],
                    ruleID: "editing.home"
                )
            case [.shift]:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.leftArrow,
                    modifiers: [.command, .shift],
                    ruleID: "editing.shift-home"
                )
            case [.control]:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.upArrow,
                    modifiers: [.command],
                    ruleID: "editing.control-home"
                )
            case [.control, .shift]:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.upArrow,
                    modifiers: [.command, .shift],
                    ruleID: "editing.control-shift-home"
                )
            default:
                break
            }
        }

        if context.isTextInput,
           stroke.keyCode == MacKeyCode.end {
            switch stroke.modifiers.subtracting([.function]) {
            case []:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.rightArrow,
                    modifiers: [.command],
                    ruleID: "editing.end"
                )
            case [.shift]:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.rightArrow,
                    modifiers: [.command, .shift],
                    ruleID: "editing.shift-end"
                )
            case [.control]:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.downArrow,
                    modifiers: [.command],
                    ruleID: "editing.control-end"
                )
            case [.control, .shift]:
                return replacingKey(
                    in: stroke,
                    keyCode: MacKeyCode.downArrow,
                    modifiers: [.command, .shift],
                    ruleID: "editing.control-shift-end"
                )
            default:
                break
            }
        }

        if [MacKeyCode.leftArrow, MacKeyCode.rightArrow,
            MacKeyCode.upArrow, MacKeyCode.downArrow]
            .contains(stroke.keyCode),
           stroke.modifiers == [.control]
            || stroke.modifiers == [.control, .shift] {
            return replacingModifiers(
                in: stroke,
                with: stroke.modifiers.contains(.shift)
                    ? [.option, .shift]
                    : [.option],
                ruleID: "editing.control-arrow"
            )
        }

        if stroke.keyCode == MacKeyCode.delete,
           stroke.modifiers == [.control] {
            return replacingModifiers(
                in: stroke,
                with: [.option],
                ruleID: "editing.control-backspace"
            )
        }

        if stroke.keyCode == MacKeyCode.forwardDelete,
           stroke.modifiers == [.control] {
            return replacingModifiers(
                in: stroke,
                with: [.option],
                ruleID: "editing.control-forward-delete"
            )
        }

        if stroke.keyCode == MacKeyCode.forwardDelete,
           stroke.modifiers == [.shift],
           context.isTextInput {
            return replacingModifiers(
                in: stroke,
                with: [],
                ruleID: "editing.shift-delete"
            )
        }

        if stroke.keyCode == MacKeyCode.tab,
           stroke.modifiers == [.option]
            || stroke.modifiers == [.option, .shift] {
            return replacingModifiers(
                in: stroke,
                with: stroke.modifiers.contains(.shift)
                    ? [.command, .shift]
                    : [.command],
                ruleID: "generic.alt-tab"
            )
        }

        if stroke.keyCode == MacKeyCode.leftArrow,
           stroke.modifiers == [.option] {
            return replacingKey(
                in: stroke,
                keyCode: MacKeyCode.leftBracket,
                modifiers: [.command],
                ruleID: "generic.alt-left"
            )
        }

        if stroke.keyCode == MacKeyCode.rightArrow,
           stroke.modifiers == [.option] {
            return replacingKey(
                in: stroke,
                keyCode: MacKeyCode.rightBracket,
                modifiers: [.command],
                ruleID: "generic.alt-right"
            )
        }

        if stroke.keyCode == MacKeyCode.insert,
           stroke.modifiers == [.control] {
            return replacingKey(
                in: stroke,
                keyCode: MacKeyCode.c,
                modifiers: [.command],
                ruleID: "editing.control-insert-copy"
            )
        }

        if stroke.keyCode == MacKeyCode.insert,
           stroke.modifiers == [.shift] {
            return replacingKey(
                in: stroke,
                keyCode: MacKeyCode.v,
                modifiers: [.command],
                ruleID: "editing.shift-insert-paste"
            )
        }

        if stroke.keyCode == MacKeyCode.f4,
           stroke.modifiers == [.control]
            || stroke.modifiers == [.control, .function] {
            return replacingKey(
                in: stroke,
                keyCode: MacKeyCode.w,
                modifiers: [.command],
                ruleID: "generic.control-f4"
            )
        }

        if stroke.keyCode == MacKeyCode.f4,
           stroke.modifiers == [.option]
            || stroke.modifiers == [.option, .function] {
            return replacingKey(
                in: stroke,
                keyCode: MacKeyCode.w,
                modifiers: isBrowser(context)
                    ? [.command, .shift]
                    : [.command],
                ruleID: isBrowser(context)
                    ? "browser.alt-f4"
                    : "generic.alt-f4"
            )
        }

        if stroke.modifiers == [.control]
            || stroke.modifiers == [.control, .shift] {
            var modifiers = stroke.modifiers
            modifiers.remove(.control)
            modifiers.insert(.command)
            return replacingModifiers(
                in: stroke,
                with: modifiers,
                ruleID: "generic.control-to-command"
            )
        }

        return passThrough(ruleID: "native.unmapped")
    }

    func contextFreeDecision(
        for stroke: KeyboardStroke
    ) -> RuleDecision? {
        if stroke.phase == .flagsChanged {
            return passThrough(ruleID: "native.flags-changed")
        }

        if [MacKeyCode.leftArrow, MacKeyCode.rightArrow,
            MacKeyCode.downArrow, MacKeyCode.upArrow]
            .contains(stroke.keyCode),
           stroke.modifiers == [.shift] {
            return passThrough(ruleID: "native.shift-selection")
        }

        return nil
    }

    func permitsHostShortcut(in context: MappingContext) -> Bool {
        !context.isSecureInput && !isRemoteDesktop(context)
    }

    private func isTerminal(_ context: MappingContext) -> Bool {
        guard let bundleIdentifier = context.bundleIdentifier else {
            return false
        }
        return terminalBundleIdentifiers.contains(
            bundleIdentifier.lowercased()
        )
    }

    private func isBrowser(_ context: MappingContext) -> Bool {
        guard let bundleIdentifier = context.bundleIdentifier else {
            return false
        }
        return browserBundleIdentifiers.contains(
            bundleIdentifier.lowercased()
        )
    }

    private func isRemoteDesktop(_ context: MappingContext) -> Bool {
        guard let bundleIdentifier = context.bundleIdentifier else {
            return false
        }
        return remoteDesktopBundleIdentifiers.contains(
            bundleIdentifier.lowercased()
        )
    }

    private func replacingModifiers(
        in stroke: KeyboardStroke,
        with modifiers: Set<KeyModifier>,
        ruleID: String
    ) -> RuleDecision {
        replacingKey(
            in: stroke,
            keyCode: stroke.keyCode,
            modifiers: modifiers,
            ruleID: ruleID
        )
    }

    private func replacingKey(
        in stroke: KeyboardStroke,
        keyCode: UInt16,
        modifiers: Set<KeyModifier>,
        ruleID: String
    ) -> RuleDecision {
        RuleDecision(
            ruleID: ruleID,
            action: .replace([
                KeyboardStroke(
                    keyCode: keyCode,
                    phase: stroke.phase,
                    modifiers: modifiers
                ),
            ])
        )
    }

    private func activationDecision(
        for phase: KeyPhase,
        ruleID: String,
        action: EngineAction
    ) -> RuleDecision {
        switch phase {
        case .down:
            return RuleDecision(ruleID: ruleID, action: action)
        case .up:
            return RuleDecision(ruleID: ruleID, action: .suppress)
        case .flagsChanged:
            return passThrough(ruleID: "native.flags-changed")
        }
    }

    private func passThrough(ruleID: String) -> RuleDecision {
        RuleDecision(ruleID: ruleID, action: .passThrough)
    }
}
