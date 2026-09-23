import AppKit
import Foundation
import IOKit.hid

enum ConflictSeverity: Equatable {
    case warning
    case blocking
}

enum ConflictCapability: String, Hashable {
    case keyboardTranslation
    case windowManagement
}

struct ConflictFinding: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let recommendation: String
    let severity: ConflictSeverity
    let affectedCapabilities: Set<ConflictCapability>
    let messageFormat: String?
    let messageArguments: [String]

    var localizedMessage: String {
        guard let messageFormat else { return L10n.text(message) }
        return String(format: L10n.text(messageFormat), locale: L10n.locale,
                      arguments: messageArguments.map { L10n.text($0) })
    }

    init(
        id: String,
        title: String,
        message: String,
        recommendation: String,
        severity: ConflictSeverity,
        affectedCapabilities: Set<ConflictCapability> = [],
        messageFormat: String? = nil,
        messageArguments: [String] = []
    ) {
        self.messageFormat = messageFormat
        self.messageArguments = messageArguments
        self.id = id
        self.title = title
        self.message = message
        self.recommendation = recommendation
        self.severity = severity
        self.affectedCapabilities = affectedCapabilities
    }

    var blocksKeyboardTranslation: Bool {
        severity == .blocking
            && affectedCapabilities.contains(.keyboardTranslation)
    }
}

struct ConflictSnapshot: Equatable {
    var installedApplicationBundleIdentifiers: Set<String> = []
    var runningApplicationBundleIdentifiers: Set<String> = []
    var runningProcessNames: Set<String> = []
    var hidutilUserKeyMappingCount = 0
    var activeMacOSModifierMappingKeys: Set<String> = []
    var uncertainMacOSModifierMappingKeys: Set<String> = []
}

protocol ConflictRule {
    func findings(in snapshot: ConflictSnapshot) -> [ConflictFinding]
}

protocol ConflictSnapshotProviding {
    func snapshot() -> ConflictSnapshot
}

protocol ConflictDiagnosing {
    func scan() -> [ConflictFinding]
}

struct ConflictRuleEvaluator {
    let rules: [any ConflictRule]

    func evaluate(_ snapshot: ConflictSnapshot) -> [ConflictFinding] {
        rules.flatMap { $0.findings(in: snapshot) }
    }
}

struct ConflictDiagnostics: ConflictDiagnosing {
    private let snapshotProvider: any ConflictSnapshotProviding
    private let evaluator: ConflictRuleEvaluator

    init(
        snapshotProvider: any ConflictSnapshotProviding =
            SystemConflictSnapshotProvider(),
        rules: [any ConflictRule] = ConflictRules.standard
    ) {
        self.snapshotProvider = snapshotProvider
        evaluator = ConflictRuleEvaluator(rules: rules)
    }

    func scan() -> [ConflictFinding] {
        evaluator.evaluate(snapshotProvider.snapshot())
    }
}

enum ConflictRules {
    static let standard: [any ConflictRule] = [
        ApplicationConflictRule(
            id: "app.karabiner-elements",
            title: "Karabiner-Elements",
            bundleIdentifiers: [
                "org.pqrs.karabiner-elements",
            ],
            processNameFragments: [
                "karabiner_console_user_server",
                "karabiner_grabber",
            ],
            severity: .blocking,
            capabilityDescription: "keyboard remapping",
            affectedCapabilities: [.keyboardTranslation]
        ),
        ApplicationConflictRule(
            id: "app.rectangle",
            title: "Rectangle",
            bundleIdentifiers: ["com.knollsoft.rectangle"],
            processNameFragments: ["rectangle"],
            severity: .warning,
            capabilityDescription: "window management",
            affectedCapabilities: [.windowManagement]
        ),
        ApplicationConflictRule(
            id: "app.magnet",
            title: "Magnet",
            bundleIdentifiers: [
                "com.crowdcafe.windowmagnet",
                "com.crowdcafe.WindowMagnet",
            ],
            processNameFragments: ["magnet"],
            severity: .warning,
            capabilityDescription: "window management",
            affectedCapabilities: [.windowManagement]
        ),
        ApplicationConflictRule(
            id: "app.bettertouchtool",
            title: "BetterTouchTool",
            bundleIdentifiers: ["com.hegenberg.bettertouchtool"],
            processNameFragments: ["bettertouchtool"],
            severity: .warning,
            capabilityDescription: "keyboard or window automation",
            affectedCapabilities: [
                .keyboardTranslation,
                .windowManagement,
            ]
        ),
        HIDUtilConflictRule(),
        MacOSModifierMappingConflictRule(),
    ]
}

struct ApplicationConflictRule: ConflictRule {
    let id: String
    let title: String
    let bundleIdentifiers: Set<String>
    let processNameFragments: Set<String>
    let severity: ConflictSeverity
    let capabilityDescription: String
    let affectedCapabilities: Set<ConflictCapability>

    init(
        id: String,
        title: String,
        bundleIdentifiers: Set<String>,
        processNameFragments: Set<String>,
        severity: ConflictSeverity,
        capabilityDescription: String,
        affectedCapabilities: Set<ConflictCapability>
    ) {
        self.id = id
        self.title = title
        self.bundleIdentifiers = Set(bundleIdentifiers.map(Self.normalize))
        self.processNameFragments = Set(
            processNameFragments.map(Self.normalize)
        )
        self.severity = severity
        self.capabilityDescription = capabilityDescription
        self.affectedCapabilities = affectedCapabilities
    }

    func findings(in snapshot: ConflictSnapshot) -> [ConflictFinding] {
        let installed = !snapshot.installedApplicationBundleIdentifiers
            .map(Self.normalize)
            .filter(bundleIdentifiers.contains)
            .isEmpty
        let runningByBundleID = !snapshot.runningApplicationBundleIdentifiers
            .map(Self.normalize)
            .filter(bundleIdentifiers.contains)
            .isEmpty
        let runningByProcessName = snapshot.runningProcessNames.contains {
            processName in
            processNameFragments.contains {
                processName.contains($0)
            }
        }
        let running = runningByBundleID || runningByProcessName

        guard installed || running else {
            return []
        }

        let stateDescription: String
        switch (installed, running) {
        case (true, true):
            stateDescription = "is installed and currently running"
        case (true, false):
            stateDescription = "is installed"
        case (false, true):
            stateDescription = "appears to be running"
        case (false, false):
            return []
        }

        let effectiveSeverity: ConflictSeverity =
            running ? severity : .warning
        let recommendation: String
        if effectiveSeverity == .blocking {
            recommendation = "Pause or quit it, then refresh diagnostics "
                + "before enabling overlapping features. Windsify Mac will not change "
                + "it automatically."
        } else {
            recommendation = "Review its enabled shortcuts and pause or "
                + "quit it if you observe duplicate actions. Windsify Mac "
                + "will not change it automatically."
        }

        return [
            ConflictFinding(
                id: id,
                title: title,
                message: "\(title) \(stateDescription) and may overlap with "
                    + "Windsify Mac \(capabilityDescription).",
                recommendation: recommendation,
                severity: effectiveSeverity,
                affectedCapabilities: affectedCapabilities,
                messageFormat: "%@ %@ and may overlap with Windsify Mac %@.",
                messageArguments: [title, stateDescription, capabilityDescription]
            ),
        ]
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
    }
}

struct HIDUtilConflictRule: ConflictRule {
    func findings(in snapshot: ConflictSnapshot) -> [ConflictFinding] {
        guard snapshot.hidutilUserKeyMappingCount > 0 else {
            return []
        }

        return [
            ConflictFinding(
                id: "system.hidutil-user-key-mapping",
                title: "hidutil UserKeyMapping",
                message: "A system-level hidutil UserKeyMapping contains "
                    + "\(snapshot.hidutilUserKeyMappingCount) active "
                    + "mapping(s), which can transform keys before Windsify "
                    + "Mac receives them.",
                recommendation: "Review the mapping before enabling the "
                    + "keyboard translation layer. The window manager will "
                    + "not remove it.",
                severity: .blocking,
                affectedCapabilities: [.keyboardTranslation],
                messageFormat: "A system-level hidutil UserKeyMapping contains %@ active mapping(s), which can transform keys before Windsify Mac receives them.",
                messageArguments: [String(snapshot.hidutilUserKeyMappingCount)]
            ),
        ]
    }
}

struct MacOSModifierMappingConflictRule: ConflictRule {
    func findings(in snapshot: ConflictSnapshot) -> [ConflictFinding] {
        var findings: [ConflictFinding] = []
        let activeCount = snapshot.activeMacOSModifierMappingKeys.count
        if activeCount > 0 {
            findings.append(ConflictFinding(
                id: "system.macos-modifier-mapping",
                title: "macOS Modifier Keys",
                message: "macOS has \(activeCount) keyboard modifier "
                    + "mapping(s) for keyboards detected at the last scan. These can overlap "
                    + "with Windsify Mac's shortcut translation.",
                recommendation: "Review System Settings → Keyboard → Keyboard "
                    + "Shortcuts → Modifier Keys. Windsify Mac will not alter "
                    + "these settings.",
                severity: .blocking,
                affectedCapabilities: [.keyboardTranslation],
                messageFormat: "macOS has %@ keyboard modifier mapping(s) for keyboards detected at the last scan. These can overlap with Windsify Mac's shortcut translation.",
                messageArguments: [String(activeCount)]
            ))
        }

        let uncertainCount = snapshot.uncertainMacOSModifierMappingKeys.count
        if uncertainCount > 0 {
            findings.append(ConflictFinding(
                id: "system.macos-modifier-mapping-uncertain",
                title: "macOS Modifier Keys",
                message: "macOS has \(uncertainCount) saved modifier mapping "
                    + "setting(s) whose effect on keyboards at the last scan could "
                    + "not be confirmed.",
                recommendation: "Review System Settings → Keyboard → Keyboard "
                    + "Shortcuts → Modifier Keys. Windsify Mac will not alter "
                    + "these settings.",
                severity: .warning,
                affectedCapabilities: [.keyboardTranslation],
                messageFormat: "macOS has %@ saved modifier mapping setting(s) whose effect on keyboards at the last scan could not be confirmed.",
                messageArguments: [String(uncertainCount)]
            ))
        }
        return findings
    }
}

struct ModifierKeyboardIdentity: Hashable {
    let vendor: Int
    let product: Int
    let location: Int

    init?(key: String) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let vendor = Int(parts[0]),
              let product = Int(parts[1]),
              let location = Int(parts[2]),
              vendor >= 0, product >= 0, location >= 0 else { return nil }
        self.vendor = vendor
        self.product = product
        self.location = location
    }

    init(vendor: Int, product: Int, location: Int) {
        self.vendor = vendor
        self.product = product
        self.location = location
    }

    func matches(_ connected: ModifierKeyboardIdentity) -> Bool {
        (vendor == 0 && product == 0 ||
            vendor == connected.vendor && product == connected.product)
            && (location == 0 || location == connected.location)
    }
}

struct ModifierMappingEvidence {
    var activeKeys: Set<String> = []
    var uncertainKeys: Set<String> = []

    static func evaluate(
        preferences: [String: Any],
        connectedKeyboards: Set<ModifierKeyboardIdentity>?
    ) -> ModifierMappingEvidence {
        let prefix = "com.apple.keyboard.modifiermapping."
        var evidence = ModifierMappingEvidence()
        for (key, value) in preferences where key.lowercased().hasPrefix(prefix) {
            guard let mappings = value as? [Any] else {
                evidence.uncertainKeys.insert(key)
                continue
            }
            var hasChangedMapping = false
            var hasUnclearMapping = false
            for entry in mappings {
                guard let pair = entry as? [String: Any],
                      let source = usage(pair["HIDKeyboardModifierMappingSrc"]),
                      let destination = usage(pair["HIDKeyboardModifierMappingDst"]) else {
                    hasUnclearMapping = true
                    continue
                }
                hasChangedMapping = hasChangedMapping || source != destination
            }
            if hasUnclearMapping { evidence.uncertainKeys.insert(key) }
            guard hasChangedMapping else { continue }
            let suffix = String(key.dropFirst(prefix.count))
            guard let keyboard = ModifierKeyboardIdentity(key: suffix),
                  let connectedKeyboards else {
                evidence.uncertainKeys.insert(key)
                continue
            }
            if connectedKeyboards.contains(where: keyboard.matches) {
                evidence.activeKeys.insert(key)
            } else {
                evidence.uncertainKeys.insert(key)
            }
        }
        return evidence
    }

    private static func usage(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return UInt64(number.stringValue)
        }
        if let string = value as? String {
            if string.lowercased().hasPrefix("0x") {
                return UInt64(string.dropFirst(2), radix: 16)
            }
            return UInt64(string)
        }
        return nil
    }
}

struct SystemConflictSnapshotProvider: ConflictSnapshotProviding {
    private struct KnownApplication {
        let bundleIdentifiers: [String]
        let paths: [String]
    }

    private static let knownApplications: [KnownApplication] = [
        KnownApplication(
            bundleIdentifiers: [
                "org.pqrs.Karabiner-Elements",
                "org.pqrs.Karabiner-EventViewer",
            ],
            paths: [
                "/Applications/Karabiner-Elements.app",
                "/Applications/Karabiner-EventViewer.app",
            ]
        ),
        KnownApplication(
            bundleIdentifiers: ["com.knollsoft.Rectangle"],
            paths: ["/Applications/Rectangle.app"]
        ),
        KnownApplication(
            bundleIdentifiers: ["com.crowdcafe.WindowMagnet"],
            paths: ["/Applications/Magnet.app"]
        ),
        KnownApplication(
            bundleIdentifiers: ["com.hegenberg.BetterTouchTool"],
            paths: ["/Applications/BetterTouchTool.app"]
        ),
    ]

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let hostIdentifierOverride: String?
    private let connectedKeyboardsOverride: Set<ModifierKeyboardIdentity>?
    private let globalDomainOverride: [String: Any]?

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        hostIdentifierOverride: String? = nil,
        connectedKeyboardsOverride: Set<ModifierKeyboardIdentity>? = nil,
        globalDomainOverride: [String: Any]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.hostIdentifierOverride = hostIdentifierOverride
        self.connectedKeyboardsOverride = connectedKeyboardsOverride
        self.globalDomainOverride = globalDomainOverride
    }

    func snapshot() -> ConflictSnapshot {
        let modifierEvidence = macOSModifierMappingEvidence()
        return ConflictSnapshot(
            installedApplicationBundleIdentifiers:
                installedApplicationBundleIdentifiers(),
            runningApplicationBundleIdentifiers: Set(
                NSWorkspace.shared.runningApplications.compactMap {
                    $0.bundleIdentifier?.lowercased()
                }
            ),
            runningProcessNames: runningProcessNames(),
            hidutilUserKeyMappingCount: hidutilUserKeyMappingCount(),
            activeMacOSModifierMappingKeys: modifierEvidence.activeKeys,
            uncertainMacOSModifierMappingKeys: modifierEvidence.uncertainKeys
        )
    }

    private func installedApplicationBundleIdentifiers() -> Set<String> {
        var results: Set<String> = []

        for application in Self.knownApplications {
            let candidatePaths = application.paths + application.paths.map {
                homeDirectory.appendingPathComponent(
                    String($0.dropFirst())
                ).path
            }
            let foundByPath = candidatePaths.contains {
                fileManager.fileExists(atPath: $0)
            }
            let foundByLaunchServices = application.bundleIdentifiers.contains {
                NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: $0
                ) != nil
            }

            if foundByPath || foundByLaunchServices {
                results.formUnion(
                    application.bundleIdentifiers.map { $0.lowercased() }
                )
            }
        }

        return results
    }

    private func runningProcessNames() -> Set<String> {
        guard let output = runReadOnlyProcess(
            executable: "/bin/ps",
            arguments: ["-axo", "comm="]
        ) else {
            return []
        }

        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .map {
                    URL(fileURLWithPath: String($0))
                        .lastPathComponent
                        .lowercased()
                }
        )
    }

    private func hidutilUserKeyMappingCount() -> Int {
        guard let output = runReadOnlyProcess(
            executable: "/usr/bin/hidutil",
            arguments: ["property", "--get", "UserKeyMapping"]
        ) else {
            return 0
        }

        if output.contains("(null)") || output.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return 0
        }

        let sourceKey = "HIDKeyboardModifierMappingSrc"
        let count = output.components(separatedBy: sourceKey).count - 1
        return max(count, output.contains("{") ? 1 : 0)
    }

    func macOSModifierMappingEvidence() -> ModifierMappingEvidence {
        let globalPreferences = homeDirectory
            .appendingPathComponent("Library/Preferences/.GlobalPreferences.plist")
        var preferences = modifierMappingPreferences(inPlistAt: globalPreferences)
        if let globalDomain = globalDomainOverride ?? UserDefaults.standard.persistentDomain(
            forName: UserDefaults.globalDomain
        ) {
            preferences.merge(globalDomain) { _, live in live }
        }
        if let hostIdentifier = hostIdentifierOverride ?? currentHostIdentifier() {
            let byHostPreferences = homeDirectory.appendingPathComponent(
                "Library/Preferences/ByHost/.GlobalPreferences.\(hostIdentifier).plist"
            )
            preferences.merge(
                modifierMappingPreferences(inPlistAt: byHostPreferences)
            ) { _, currentHost in currentHost }
        }
        if hostIdentifierOverride == nil,
           let liveCurrentHost = CFPreferencesCopyMultiple(
            nil, kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
           ) as? [String: Any] {
            preferences.merge(liveCurrentHost) { _, live in live }
        }
        return ModifierMappingEvidence.evaluate(
            preferences: preferences,
            connectedKeyboards: connectedKeyboardsOverride ?? connectedKeyboards()
        )
    }

    private func modifierMappingPreferences(inPlistAt url: URL) -> [String: Any] {
        guard
            let data = try? Data(contentsOf: url),
            let dictionary = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    private func currentHostIdentifier() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(
            service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String
    }

    private func connectedKeyboards() -> Set<ModifierKeyboardIdentity>? {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager)
            as? Set<IOHIDDevice>, !devices.isEmpty else { return nil }
        let identities = Set(devices.compactMap { device -> ModifierKeyboardIdentity? in
            guard let vendor = IOHIDDeviceGetProperty(
                device, kIOHIDVendorIDKey as CFString
            ) as? Int,
            let product = IOHIDDeviceGetProperty(
                device, kIOHIDProductIDKey as CFString
            ) as? Int else { return nil }
            let location = IOHIDDeviceGetProperty(
                device, kIOHIDLocationIDKey as CFString
            ) as? Int ?? 0
            return ModifierKeyboardIdentity(
                vendor: vendor, product: product, location: location
            )
        })
        return identities.isEmpty ? nil : identities
    }

    private func runReadOnlyProcess(
        executable: String,
        arguments: [String]
    ) -> String? {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            return String(data: output, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
