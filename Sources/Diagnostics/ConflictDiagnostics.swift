import AppKit
import Foundation

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

    init(
        id: String,
        title: String,
        message: String,
        recommendation: String,
        severity: ConflictSeverity,
        affectedCapabilities: Set<ConflictCapability> = []
    ) {
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
    var macOSModifierMappingPreferenceKeys: Set<String> = []
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
                affectedCapabilities: affectedCapabilities
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
                affectedCapabilities: [.keyboardTranslation]
            ),
        ]
    }
}

struct MacOSModifierMappingConflictRule: ConflictRule {
    func findings(in snapshot: ConflictSnapshot) -> [ConflictFinding] {
        let count = snapshot.macOSModifierMappingPreferenceKeys.count
        guard count > 0 else {
            return []
        }

        return [
            ConflictFinding(
                id: "system.macos-modifier-mapping",
                title: "macOS Modifier Keys",
                message: "macOS has \(count) saved keyboard modifier "
                    + "mapping(s). These can overlap with Windsify Mac's "
                    + "shortcut translation.",
                recommendation: "Review System Settings → Keyboard → Keyboard "
                    + "Shortcuts → Modifier Keys. Windsify Mac will not alter "
                    + "these settings.",
                severity: .blocking,
                affectedCapabilities: [.keyboardTranslation]
            ),
        ]
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

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func snapshot() -> ConflictSnapshot {
        ConflictSnapshot(
            installedApplicationBundleIdentifiers:
                installedApplicationBundleIdentifiers(),
            runningApplicationBundleIdentifiers: Set(
                NSWorkspace.shared.runningApplications.compactMap {
                    $0.bundleIdentifier?.lowercased()
                }
            ),
            runningProcessNames: runningProcessNames(),
            hidutilUserKeyMappingCount: hidutilUserKeyMappingCount(),
            macOSModifierMappingPreferenceKeys:
                macOSModifierMappingPreferenceKeys()
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

    private func macOSModifierMappingPreferenceKeys() -> Set<String> {
        var keys: Set<String> = []

        if let globalDomain = UserDefaults.standard.persistentDomain(
            forName: UserDefaults.globalDomain
        ) {
            keys.formUnion(modifierMappingKeys(in: globalDomain))
        }

        let globalPreferences = homeDirectory
            .appendingPathComponent("Library/Preferences/.GlobalPreferences.plist")
        keys.formUnion(modifierMappingKeys(inPlistAt: globalPreferences))

        let byHostDirectory = homeDirectory
            .appendingPathComponent("Library/Preferences/ByHost")
        if let urls = try? fileManager.contentsOfDirectory(
            at: byHostDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for url in urls where
                url.lastPathComponent.hasPrefix(".GlobalPreferences.")
                    && url.pathExtension == "plist"
            {
                keys.formUnion(modifierMappingKeys(inPlistAt: url))
            }
        }

        return keys
    }

    private func modifierMappingKeys(inPlistAt url: URL) -> Set<String> {
        guard
            let data = try? Data(contentsOf: url),
            let dictionary = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return []
        }

        return modifierMappingKeys(in: dictionary)
    }

    private func modifierMappingKeys(
        in dictionary: [String: Any]
    ) -> Set<String> {
        Set(
            dictionary.keys.filter {
                $0.lowercased().hasPrefix(
                    "com.apple.keyboard.modifiermapping."
                )
            }
        )
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
