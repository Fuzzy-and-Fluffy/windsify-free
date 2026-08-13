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

    private let keyboardController: CGEventTapController
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

        keyboardTranslationEnabled = defaults.object(
            forKey: PreferenceKey.keyboardTranslationEnabled
        ) as? Bool ?? false
        accessibilityStatus = accessibilityAuthorizer.isTrusted
            ? .granted
            : .notGranted
        launchAtLoginEnabled = launchAtLoginManager.isEnabled
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
        guard !hasActivated else {
            refresh()
            return
        }
        hasActivated = true
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
            keyboardController.stop()
            keyboardEngineIsRunning = false
            return
        }

        guard !keyboardController.isRunning else {
            keyboardEngineIsRunning = true
            return
        }

        do {
            try keyboardController.start()
            keyboardEngineIsRunning = true
            lastErrorMessage = nil
        } catch {
            keyboardEngineIsRunning = false
            lastErrorMessage = error.localizedDescription
        }
    }
}
