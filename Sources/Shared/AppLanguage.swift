import Combine
import Foundation
import SwiftUI

/// Stored independently from keyboard, window, trial and license preferences.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .system:
            return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let preferenceKey = "interfaceLanguage"
    @Published private(set) var selection: AppLanguage
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    var locale: Locale { Locale(identifier: selection.resolvedIdentifier()) }

    func select(_ language: AppLanguage) {
        selection = language
        defaults.set(language.rawValue, forKey: Self.preferenceKey)
    }
}

enum L10n {
    static var locale: Locale {
        let selected = UserDefaults.standard.string(forKey: "interfaceLanguage")
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        return Locale(identifier: selected.resolvedIdentifier())
    }

    /// Explicit lookup for model-provided UI strings; diagnostic report data remains unchanged.
    static func text(_ key: String, locale: Locale = locale, bundle: Bundle = .main) -> String {
        guard let path = bundle.path(forResource: locale.identifier, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    /// Legacy services retain English diagnostic messages. Translate only known
    /// user-facing message shapes here, leaving OS errors and reports intact.
    static func message(_ message: String, locale: Locale = locale) -> String {
        let suffix = " Windsify could not save this status; keep the app open and try again while online."
        if message.hasSuffix(suffix) {
            return self.message(String(message.dropLast(suffix.count)), locale: locale)
                + text(suffix, locale: locale)
        }
        for prefix in ["Window engine: ", "Keyboard engine: ", "Window engine fallback: "] {
            if message.hasPrefix(prefix) {
                let detail = self.message(String(message.dropFirst(prefix.count)), locale: locale)
                return String(format: text(prefix + "%@", locale: locale), locale: locale, detail)
            }
        }
        let numericTemplates = [
            "Polar is temporarily busy. Try again in %d seconds.",
            "Keychain operation failed with status %d.",
            "Trial Keychain operation failed with status %d.",
            "Could not install the window shortcut handler (Carbon status %d)."
        ]
        for template in numericTemplates {
            let parts = template.components(separatedBy: "%d")
            guard message.hasPrefix(parts[0]), message.hasSuffix(parts[1]),
                  message.count >= parts[0].count + parts[1].count else { continue }
            let number = message.dropFirst(parts[0].count).dropLast(parts[1].count)
            if let value = Int32(number) {
                return String(format: text(template, locale: locale), locale: locale, value)
            }
        }
        let registrationPrefix = "Could not register "
        let registrationSeparator = ", usually because another window tool owns it (Carbon status "
        if message.hasPrefix(registrationPrefix), message.hasSuffix(")."),
           let separator = message.range(of: registrationSeparator),
           let status = Int32(message[separator.upperBound...].dropLast(2)) {
            let shortcut = String(message[message.index(message.startIndex, offsetBy: registrationPrefix.count)..<separator.lowerBound])
            return String(format: text("Could not register %@, usually because another window tool owns it (Carbon status %d).", locale: locale), locale: locale, shortcut, status)
        }
        if message.hasPrefix("Window action: ") {
            let raw = String(message.dropFirst("Window action: ".count))
            let action = WindowCommand(rawValue: raw)?.displayName ?? raw
            return String(format: text("Window action: %@", locale: locale), locale: locale, text(action, locale: locale))
        }
        return text(message, locale: locale)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct LanguageSettingsSection: View {
    @EnvironmentObject private var language: AppLanguageStore

    var body: some View {
        Section("Language") {
            Picker("Language", selection: Binding(
                get: { language.selection }, set: { language.select($0) }
            )) {
                Text("Follow System").tag(AppLanguage.system)
                Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                Text(verbatim: "English").tag(AppLanguage.english)
            }
            Link("Read the user guide", destination: URL(string: language.locale.identifier == "zh-Hans" ? "https://windsify.com/zh/guides" : "https://windsify.com/guides")!)
            Text("Changes the interface language only. Keyboard shortcuts and license settings stay the same.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension WindowCommand {
    var displayName: String {
        switch self {
        case .windowsLeft:
            return "Left half or quarter"
        case .windowsRight:
            return "Right half or quarter"
        case .windowsUp:
            return "Maximize or upper quarter"
        case .windowsDown:
            return "Restore, lower quarter, or minimize"
        case .leftHalf:
            return "Left half"
        case .rightHalf:
            return "Right half"
        case .fill:
            return "Fill"
        case .restore:
            return "Restore"
        case .restoreOrMinimize:
            return "Restore or minimize"
        case .minimizeAll:
            return "Minimize all"
        case .restoreMinimized:
            return "Restore minimized"
        case .center:
            return "Center"
        case .maximizeHeight:
            return "Maximize height"
        case .makeSmaller:
            return "Make smaller"
        case .makeLarger:
            return "Make larger"
        case .topHalf:
            return "Top half"
        case .bottomHalf:
            return "Bottom half"
        case .topLeft:
            return "Top-left quarter"
        case .topRight:
            return "Top-right quarter"
        case .bottomLeft:
            return "Bottom-left quarter"
        case .bottomRight:
            return "Bottom-right quarter"
        case .nextDisplay:
            return "Next display"
        case .previousDisplay:
            return "Previous display"
        }
    }
}
