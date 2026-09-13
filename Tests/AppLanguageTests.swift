import XCTest
@testable import WindsifyMac

final class AppLanguageTests: XCTestCase {
    func testDynamicServiceMessagesTranslateWithoutChangingDiagnostics() {
        let locale = Locale(identifier: "zh-Hans")
        let raw = "Polar is temporarily busy. Try again in 12 seconds."
        XCTAssertEqual(L10n.message(raw, locale: locale), "Polar 暂时繁忙，请在 12 秒后重试。")
        XCTAssertEqual(L10n.message(raw, locale: Locale(identifier: "en")), raw)
        XCTAssertEqual(L10n.message("Window engine: Keychain operation failed with status -50.", locale: locale), "窗口引擎：钥匙串操作失败，状态码：-50。")
        XCTAssertEqual(L10n.message("Window action: fill", locale: locale), "窗口操作：填满可用区域")
        let invalid = "Polar no longer permits this license activation."
        let suffix = " Windsify could not save this status; keep the app open and try again while online."
        XCTAssertEqual(L10n.message(invalid + suffix, locale: locale), L10n.text(invalid, locale: locale) + L10n.text(suffix, locale: locale))
        XCTAssertEqual(L10n.message("Unknown OS error 123", locale: locale), "Unknown OS error 123")
    }

    func testSystemLanguageAndExplicitOverrides() {
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-CN", "en"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["de-DE", "zh"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: []), "en")
        XCTAssertEqual(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh"]), "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedIdentifier(preferredLanguages: ["en"]), "zh-Hans")
    }

    @MainActor
    func testLanguagePersistsWithoutChangingExistingPreferences() throws {
        let suite = "WindsifyLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing: [String: Any] = ["windowManagementEnabled": true, "keyboardTranslationEnabled": false,
                                       "windowFillArea": "keepDockVisible", "licenseFixture": "untouched"]
        existing.forEach { defaults.set($0.value, forKey: $0.key) }
        let store = AppLanguageStore(defaults: defaults)
        XCTAssertEqual(store.selection, .english)
        XCTAssertFalse(store.showsFirstLaunchChoice)
        store.select(.simplifiedChinese)
        XCTAssertEqual(AppLanguageStore(defaults: defaults).selection, .simplifiedChinese)
        store.select(.english)
        XCTAssertEqual(AppLanguageStore(defaults: defaults).selection, .english)
        store.select(.system)
        for (key, value) in existing {
            XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject)
        }
        defaults.set("unknown-future-language", forKey: AppLanguageStore.preferenceKey)
        XCTAssertEqual(AppLanguageStore(defaults: defaults).selection, .english)
        XCTAssertEqual(defaults.string(forKey: AppLanguageStore.preferenceKey), "unknown-future-language")
    }

    @MainActor
    func testLegacyFreeTrialAndPaidInstallationsStayEnglish() throws {
        for key in ["keyboardTranslationEnabled", "trialFirstLaunchAt", "runtimeWindowEngineRunning"] {
            let suite = "WindsifyLanguageTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(false, forKey: key) // Presence, not truthiness, identifies past use.
            let existing = AppLanguageStore.hasExistingInstallation(
                defaults: defaults, accessibilityGranted: false, fileExists: { _ in false }
            )
            XCTAssertTrue(existing, key)
            let store = AppLanguageStore(defaults: defaults, hasExistingInstallation: existing)
            XCTAssertEqual(store.selection.resolvedIdentifier(preferredLanguages: ["zh-CN"]), "en")
            XCTAssertFalse(store.showsFirstLaunchChoice)
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
        }
    }

    @MainActor
    func testFreshInstallOffersChoiceOnlyOnFirstLaunchEvenIfDismissedOrQuit() throws {
        for makeChoice in [false, true] {
            let suite = "WindsifyLanguageTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = AppLanguageStore(defaults: defaults, hasExistingInstallation: false)
            XCTAssertTrue(store.showsFirstLaunchChoice)
            XCTAssertEqual(store.selection, .english)
            if makeChoice {
                store.select(.simplifiedChinese)
                store.dismissFirstLaunchChoice()
                XCTAssertFalse(store.showsFirstLaunchChoice)
            }
            // No version parameter: restart and future language releases use the same marker.
            let next = AppLanguageStore(defaults: defaults, hasExistingInstallation: false)
            XCTAssertFalse(next.showsFirstLaunchChoice)
            XCTAssertEqual(next.selection, makeChoice ? .simplifiedChinese : .english)
            defaults.removeObject(forKey: AppLanguageStore.preferenceKey)
            XCTAssertFalse(AppLanguageStore(defaults: defaults, hasExistingInstallation: false).showsFirstLaunchChoice)
        }
    }

    @MainActor
    func testEveryExplicitChoiceSurvivesMigrationAndNeverPrompts() throws {
        for language in AppLanguage.allCases {
            let suite = "WindsifyLanguageTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(language.rawValue, forKey: AppLanguageStore.preferenceKey)
            let store = AppLanguageStore(defaults: defaults, hasExistingInstallation: false)
            XCTAssertEqual(store.selection, language)
            XCTAssertFalse(store.showsFirstLaunchChoice)
        }
    }

    @MainActor
    func testInstallEvidenceUsesPermissionAndDurableFilesWithoutReadingCredentials() throws {
        let suite = "WindsifyLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertFalse(AppLanguageStore.hasExistingInstallation(defaults: defaults, accessibilityGranted: false, home: home))
        let mirror = home.appendingPathComponent("Library/Application Support/Windsify Mac")
        try FileManager.default.createDirectory(at: mirror, withIntermediateDirectories: true)
        XCTAssertTrue(AppLanguageStore.hasExistingInstallation(defaults: defaults, accessibilityGranted: false, home: home))
        XCTAssertTrue(AppLanguageStore.hasExistingInstallation(defaults: defaults, accessibilityGranted: true, fileExists: { _ in false }))
        XCTAssertTrue(AppLanguageStore.hasExistingInstallation(defaults: defaults, accessibilityGranted: false, fileExists: { _ in throw CocoaError(.fileReadNoPermission) }))
    }

    func testBundledChineseAndEnglishWithSafeFallback() throws {
        let bundle = Bundle.main
        XCTAssertEqual(L10n.text("Language", locale: Locale(identifier: "zh-Hans"), bundle: bundle), "语言")
        XCTAssertEqual(L10n.text("Language", locale: Locale(identifier: "en"), bundle: bundle), "Language")
        XCTAssertEqual(L10n.text("Untranslated future message", locale: Locale(identifier: "zh-Hans"), bundle: bundle), "Untranslated future message")
        let englishURL = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"))
        let chineseURL = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "zh-Hans"))
        let english = try XCTUnwrap(NSDictionary(contentsOf: englishURL) as? [String: String])
        let chinese = try XCTUnwrap(NSDictionary(contentsOf: chineseURL) as? [String: String])
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let pattern = try NSRegularExpression(pattern: "%[0-9$]*[a-z@]+")
        for key in english.keys {
            let tokens: (String) -> [String] = { value in
                pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }.sorted()
            }
            XCTAssertEqual(tokens(english[key]!), tokens(chinese[key]!), "Format mismatch: \(key)")
            XCTAssertFalse(chinese[key]!.isEmpty, "Empty translation: \(key)")
        }
    }
}
