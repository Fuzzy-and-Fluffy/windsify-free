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
        let preferences: [([String], String)] = [
            (["zh-CN", "en"], "zh-Hans"), (["zh-TW"], "zh-Hant-TW"),
            (["zh-HK"], "zh-Hant-HK"), (["zh-MO"], "zh-Hant-HK"),
            (["zh-Hant"], "zh-Hant"), (["zh-SG"], "zh-Hans"), (["zh"], "zh-Hans"),
            (["zh-Hant-TW"], "zh-Hant-TW"), (["zh-Hant-HK"], "zh-Hant-HK"),
            (["zh-Hans-TW"], "zh-Hans"), (["zh-Hant-CN"], "zh-Hant"),
            (["de-DE", "zh-HK"], "zh-Hant-HK"), (["de-DE", "en", "zh-TW"], "en"),
            (["de-DE", "zh"], "zh-Hans"), ([], "en")
        ]
        for (languages, expected) in preferences {
            XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: languages), expected, "\(languages)")
        }
        for language in AppLanguage.allCases where language != .system {
            XCTAssertEqual(language.resolvedIdentifier(preferredLanguages: ["de-DE", "zh-HK"]), language.rawValue)
        }
    }

    func testGuidesUseTheResolvedLanguageWithoutChangingNeutralScriptIdentity() {
        for (language, path) in [(AppLanguage.english, "/guides"), (.simplifiedChinese, "/zh/guides"),
                                 (.traditionalChineseTaiwan, "/zh-tw/guides"), (.traditionalChineseHongKong, "/zh-hk/guides")] {
            XCTAssertEqual(language.userGuideURL(preferredLanguages: ["en"]).path, path)
        }
        XCTAssertEqual(AppLanguage.system.userGuideURL(preferredLanguages: ["zh-HK"]).path, "/zh-hk/guides")
        XCTAssertEqual(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant"]), "zh-Hant")
        XCTAssertEqual(AppLanguage.system.userGuideURL(preferredLanguages: ["zh-Hant"]).path, "/zh-tw/guides")
    }

    @MainActor
    func testLanguagePersistsWithoutChangingExistingPreferences() throws {
        let suite = "WindsifyLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing: [String: Any] = ["windowManagementEnabled": true, "keyboardTranslationEnabled": false,
                                       "windowFillArea": "keepDockVisible", "licenseFixture": "untouched",
                                       "trialFirstLaunchAt": 12345, "interfaceLanguageInitialized": true]
        existing.forEach { defaults.set($0.value, forKey: $0.key) }
        let store = AppLanguageStore(defaults: defaults)
        XCTAssertEqual(store.selection, .english)
        XCTAssertFalse(store.showsFirstLaunchChoice)
        store.select(.simplifiedChinese)
        XCTAssertEqual(AppLanguageStore(defaults: defaults).selection, .simplifiedChinese)
        for language in [AppLanguage.traditionalChineseTaiwan, .traditionalChineseHongKong, .english] {
            store.select(language)
            let restarted = AppLanguageStore(defaults: defaults, hasExistingInstallation: false)
            XCTAssertEqual(restarted.selection, language)
            XCTAssertFalse(restarted.showsFirstLaunchChoice)
        }
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
                store.select(.traditionalChineseHongKong)
                store.dismissFirstLaunchChoice()
                XCTAssertFalse(store.showsFirstLaunchChoice)
            }
            // No version parameter: restart and future language releases use the same marker.
            let next = AppLanguageStore(defaults: defaults, hasExistingInstallation: false)
            XCTAssertFalse(next.showsFirstLaunchChoice)
            XCTAssertEqual(next.selection, makeChoice ? .traditionalChineseHongKong : .english)
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
        let english = try XCTUnwrap(NSDictionary(contentsOf: englishURL) as? [String: String])
        let pattern = try NSRegularExpression(pattern: "%[0-9$]*[a-z@]+")
        let tokens: (String) -> [String] = { value in
            pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        for identifier in AppLanguage.supportedLocalizations {
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: identifier))
            // Require the actual resource, rather than a development-language fallback.
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, identifier + ".lproj")
            let translations = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            XCTAssertEqual(Set(english.keys), Set(translations.keys), identifier)
            let localizedBundle = try XCTUnwrap(Bundle(path: url.deletingLastPathComponent().path))
            for key in english.keys {
                let value = try XCTUnwrap(translations[key])
                XCTAssertEqual(tokens(english[key]!), tokens(value), "Format mismatch: \(identifier): \(key)")
                XCTAssertFalse(value.isEmpty, "Empty translation: \(identifier): \(key)")
                XCTAssertEqual(L10n.text(key, locale: Locale(identifier: identifier), bundle: bundle), value)
                XCTAssertEqual(localizedBundle.localizedString(forKey: key, value: key, table: nil), value)
            }
        }
        for (identifier, shortcut, copy) in [("zh-Hant", "快捷鍵說明", "複製報告"),
                                            ("zh-Hant-TW", "快速鍵說明", "拷貝報告"),
                                            ("zh-Hant-HK", "快捷鍵說明", "複製報告")] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(L10n.text("Shortcut Help", locale: locale, bundle: bundle), shortcut)
            XCTAssertEqual(L10n.text("Copy report", locale: locale, bundle: bundle), copy)
            XCTAssertEqual(L10n.text("Accessibility", locale: locale, bundle: bundle), "輔助使用")
            if identifier == "zh-Hant-TW" || identifier == "zh-Hant-HK" {
                XCTAssertEqual(L10n.text("Automatically configure VS Code terminal", locale: locale, bundle: bundle), "自動設定 VS Code 終端機")
            }
            XCTAssertEqual(L10n.message("Polar is temporarily busy. Try again in 12 seconds.", locale: locale), "Polar 暫時繁忙，請在 12 秒後重試。")
            XCTAssertEqual(L10n.text("Untranslated future message", locale: locale, bundle: bundle), "Untranslated future message")
        }
    }
}
