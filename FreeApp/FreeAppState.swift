import Combine
import Foundation

enum FreeAccessibilityStatus: Equatable {
    case granted
    case notGranted
}

@MainActor
final class FreeAppState: ObservableObject {
    private enum PreferenceKey {
        static let keyboardTranslationEnabled =
            "keyboardTranslationEnabled"
    }

    @Published private(set) var keyboardTranslationEnabled: Bool
    @Published private(set) var keyboardEngineIsRunning = false
    @Published private(set) var accessibilityStatus: FreeAccessibilityStatus
    @Published private(set) var conflicts: [ConflictFinding] = []
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var codeEditorMigrationMessage: String?
    let shortcutSupport = ShortcutSupportModel()

    private let keyboardController: CGEventTapController
    private let applicationMenuKeyController: ApplicationMenuKeyController
    private let accessibilityAuthorizer: any AccessibilityAuthorizing
    private let conflictDiagnostics: any ConflictDiagnosing
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let defaults: UserDefaults
    private var hasActivated = false

    init(
        accessibilityAuthorizer: any AccessibilityAuthorizing =
            SystemAccessibilityAuthorizer(),
        conflictDiagnostics: any ConflictDiagnosing =
            ConflictDiagnostics(),
        launchAtLoginManager: any LaunchAtLoginManaging =
            SystemLaunchAtLoginManager(),
        defaults: UserDefaults = .standard
    ) {
        self.accessibilityAuthorizer = accessibilityAuthorizer
        self.conflictDiagnostics = conflictDiagnostics
        self.launchAtLoginManager = launchAtLoginManager
        self.defaults = defaults
        keyboardController = CGEventTapController()
        keyboardController.windowActionsEnabled = false
        applicationMenuKeyController = ApplicationMenuKeyController()

        keyboardTranslationEnabled = defaults.object(
            forKey: PreferenceKey.keyboardTranslationEnabled
        ) as? Bool ?? false
        accessibilityStatus = accessibilityAuthorizer.isTrusted
            ? .granted
            : .notGranted
        launchAtLoginEnabled = launchAtLoginManager.isEnabled
        keyboardController.shortcutTestHandler = { [weak shortcutSupport] type, event in
            MainActor.assumeIsolated { shortcutSupport?.intercept(type: type, event: event) }
        }
        keyboardController.shortcutDecisionObserver = { [weak shortcutSupport] event, stroke, context, decision, milliseconds in
            MainActor.assumeIsolated {
                shortcutSupport?.observeLive(event: event, stroke: stroke, context: context,
                                             decision: decision, contextMilliseconds: milliseconds)
            }
        }
        shortcutSupport.statusProvider = { [weak self] in
            guard let self else { return ShortcutSupportStatus() }
            return ShortcutSupportStatus(keyboardEnabled: self.keyboardTranslationEnabled,
                                         keyboardRunning: self.keyboardEngineIsRunning,
                                         accessibilityGranted: self.accessibilityStatus == .granted,
                                         conflictIDs: self.relevantConflicts.map(\.id),
                                         blockedByConflict: self.keyboardIsBlockedByConflicts)
        }
    }

    var relevantConflicts: [ConflictFinding] {
        conflicts.filter {
            $0.affectedCapabilities.contains(.keyboardTranslation)
        }
    }

    var keyboardIsBlockedByConflicts: Bool {
        relevantConflicts.contains { $0.blocksKeyboardTranslation }
    }

    func activate() {
        guard !InputRuntimeSafety.isTestHost else { return }
        guard !hasActivated else {
            refresh()
            return
        }
        hasActivated = true
        if !InputRuntimeSafety.isTestHost {
            do {
                if try VSCodeLegacyCleanup.remove() {
                    codeEditorMigrationMessage = "Old VS Code shortcuts were removed. Reload the VS Code window to restore native behavior."
                }
            } catch { codeEditorMigrationMessage = error.localizedDescription }
        }
        refresh()
    }

    func refresh() {
        accessibilityStatus = accessibilityAuthorizer.isTrusted
            ? .granted
            : .notGranted
        conflicts = conflictDiagnostics.scan()
        launchAtLoginEnabled = launchAtLoginManager.isEnabled
        reconcileKeyboardEngine()
    }

    func setKeyboardTranslationEnabled(_ isEnabled: Bool) {
        keyboardTranslationEnabled = isEnabled
        defaults.set(
            isEnabled,
            forKey: PreferenceKey.keyboardTranslationEnabled
        )
        reconcileKeyboardEngine()
    }

    func requestAccessibilityAccess() {
        accessibilityAuthorizer.requestAccess()
        refresh()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(isEnabled)
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            lastErrorMessage = nil
        } catch {
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func reconcileKeyboardEngine() {
        let shouldRun = keyboardTranslationEnabled
            && accessibilityStatus == .granted
            && !keyboardIsBlockedByConflicts

        guard shouldRun else {
            applicationMenuKeyController.stop()
            keyboardController.stop()
            keyboardEngineIsRunning = false
            return
        }

        do {
            if !keyboardController.isRunning {
                try keyboardController.start()
            }
            // The ordinary event tap remains the engine's required owner.
            // Menu-key HID support is best-effort and must not disable Free
            // shortcuts if Input Monitoring is unavailable.
            try? applicationMenuKeyController.start()
            keyboardEngineIsRunning = true
            lastErrorMessage = nil
        } catch {
            keyboardEngineIsRunning = false
            lastErrorMessage = error.localizedDescription
        }
    }
}
