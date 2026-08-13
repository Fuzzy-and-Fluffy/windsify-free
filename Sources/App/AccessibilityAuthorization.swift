import AppKit
import ApplicationServices
import Foundation

protocol AccessibilityAuthorizing {
    var isTrusted: Bool { get }

    func requestAccess()
}

struct SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security"
            + "?Privacy_Accessibility"
    )

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        guard !isTrusted, let settingsURL = Self.accessibilitySettingsURL else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }
}
