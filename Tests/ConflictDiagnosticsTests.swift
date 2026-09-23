import XCTest
@testable import WindsifyMac

final class ConflictDiagnosticsTests: XCTestCase {
    func testInjectedRulesAreEvaluatedInOrder() {
        let snapshot = ConflictSnapshot(hidutilUserKeyMappingCount: 2)
        let diagnostics = ConflictDiagnostics(
            snapshotProvider: StubSnapshotProvider(value: snapshot),
            rules: [
                StubRule(id: "first"),
                StubRule(id: "second"),
            ]
        )

        let findings = diagnostics.scan()

        XCTAssertEqual(findings.map(\.id), ["first", "second"])
    }

    func testApplicationRuleCombinesInstalledAndRunningState() {
        let rule = ApplicationConflictRule(
            id: "app.example",
            title: "Example Remapper",
            bundleIdentifiers: ["com.example.Remapper"],
            processNameFragments: ["example-remapper"],
            severity: .warning,
            capabilityDescription: "keyboard remapping",
            affectedCapabilities: [.keyboardTranslation]
        )
        let snapshot = ConflictSnapshot(
            installedApplicationBundleIdentifiers: ["com.example.remapper"],
            runningProcessNames: ["example-remapper-helper"]
        )

        let findings = rule.findings(in: snapshot)

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.id, "app.example")
        XCTAssertTrue(findings.first?.message.contains("installed and currently running") == true)
        XCTAssertTrue(findings.first?.recommendation.contains("will not change it automatically") == true)
    }

    func testInstalledBlockingAppIsOnlyBlockingWhileRunning() {
        let rule = ApplicationConflictRule(
            id: "app.example",
            title: "Example Remapper",
            bundleIdentifiers: ["com.example.remapper"],
            processNameFragments: ["example-remapper"],
            severity: .blocking,
            capabilityDescription: "keyboard remapping",
            affectedCapabilities: [.keyboardTranslation]
        )

        let installedFinding = rule.findings(
            in: ConflictSnapshot(
                installedApplicationBundleIdentifiers: [
                    "com.example.remapper",
                ]
            )
        ).first
        let runningFinding = rule.findings(
            in: ConflictSnapshot(
                runningProcessNames: ["example-remapper-helper"]
            )
        ).first

        XCTAssertEqual(installedFinding?.severity, .warning)
        XCTAssertEqual(runningFinding?.severity, .blocking)
        XCTAssertEqual(
            runningFinding?.blocksKeyboardTranslation,
            true
        )
    }

    func testSystemMappingRulesOnlyReportActiveMappings() {
        let emptySnapshot = ConflictSnapshot()
        let mappedSnapshot = ConflictSnapshot(
            hidutilUserKeyMappingCount: 3,
            activeMacOSModifierMappingKeys: [
                "com.apple.keyboard.modifiermapping.1-2-0",
            ]
        )

        XCTAssertTrue(HIDUtilConflictRule().findings(in: emptySnapshot).isEmpty)
        XCTAssertTrue(
            MacOSModifierMappingConflictRule()
                .findings(in: emptySnapshot)
                .isEmpty
        )
        XCTAssertEqual(
            HIDUtilConflictRule().findings(in: mappedSnapshot).first?.severity,
            .blocking
        )
        XCTAssertEqual(
            MacOSModifierMappingConflictRule()
                .findings(in: mappedSnapshot)
                .first?
                .severity,
            .blocking
        )
        XCTAssertEqual(
            HIDUtilConflictRule()
                .findings(in: mappedSnapshot)
                .first?
                .blocksKeyboardTranslation,
            true
        )
    }

    func testDefaultAndIdentityModifierMappingsDoNotBlock() {
        let keyboard = ModifierKeyboardIdentity(vendor: 1, product: 2, location: 3)
        let key = "com.apple.keyboard.modifiermapping.1-2-0"
        let evidence = ModifierMappingEvidence.evaluate(
            preferences: [key: [
                ["HIDKeyboardModifierMappingSrc": 0x7000000E3,
                 "HIDKeyboardModifierMappingDst": 0x7000000E3],
            ]],
            connectedKeyboards: [keyboard]
        )
        let empty = ModifierMappingEvidence.evaluate(
            preferences: [key: []], connectedKeyboards: [keyboard]
        )

        XCTAssertTrue(evidence.activeKeys.isEmpty)
        XCTAssertTrue(evidence.uncertainKeys.isEmpty)
        XCTAssertTrue(empty.activeKeys.isEmpty)
        XCTAssertTrue(empty.uncertainKeys.isEmpty)
    }

    func testChangedModifierMappingBlocksOnlyMatchingKeyboard() {
        let key = "com.apple.keyboard.modifiermapping.1-2-0"
        let map = [[
            "HIDKeyboardModifierMappingSrc": 0x7000000E3,
            "HIDKeyboardModifierMappingDst": 0x7000000E0,
        ]]
        let matching = ModifierMappingEvidence.evaluate(
            preferences: [key: map],
            connectedKeyboards: [ModifierKeyboardIdentity(vendor: 1, product: 2, location: 3)]
        )
        let inactive = ModifierMappingEvidence.evaluate(
            preferences: [key: map],
            connectedKeyboards: [ModifierKeyboardIdentity(vendor: 4, product: 5, location: 3)]
        )
        let unavailable = ModifierMappingEvidence.evaluate(
            preferences: [key: map], connectedKeyboards: nil
        )

        XCTAssertEqual(matching.activeKeys, [key])
        XCTAssertTrue(matching.uncertainKeys.isEmpty)
        XCTAssertTrue(inactive.activeKeys.isEmpty)
        XCTAssertEqual(inactive.uncertainKeys, [key])
        XCTAssertTrue(unavailable.activeKeys.isEmpty)
        XCTAssertEqual(unavailable.uncertainKeys, [key])
        XCTAssertTrue(MacOSModifierMappingConflictRule().findings(in: ConflictSnapshot(
            activeMacOSModifierMappingKeys: matching.activeKeys
        )).first?.blocksKeyboardTranslation == true)

        let otherLocation = ModifierMappingEvidence.evaluate(
            preferences: ["com.apple.keyboard.modifiermapping.1-2-9": map],
            connectedKeyboards: [ModifierKeyboardIdentity(vendor: 1, product: 2, location: 3)]
        )
        XCTAssertTrue(otherLocation.activeKeys.isEmpty)
        XCTAssertEqual(otherLocation.uncertainKeys.count, 1)
    }

    func testMalformedAndMixedMappingsRemainVisibleWithoutHidingRealSwap() {
        let key = "com.apple.keyboard.modifiermapping.1-2-0"
        let evidence = ModifierMappingEvidence.evaluate(
            preferences: [key: [
                ["HIDKeyboardModifierMappingSrc": "0x7000000E3",
                 "HIDKeyboardModifierMappingDst": "0x7000000E0"],
                ["HIDKeyboardModifierMappingSrc": 0x7000000E2],
            ]],
            connectedKeyboards: [ModifierKeyboardIdentity(vendor: 1, product: 2, location: 1)]
        )
        let findings = MacOSModifierMappingConflictRule().findings(in: ConflictSnapshot(
            activeMacOSModifierMappingKeys: evidence.activeKeys,
            uncertainMacOSModifierMappingKeys: evidence.uncertainKeys
        ))

        XCTAssertEqual(evidence.activeKeys, [key])
        XCTAssertEqual(evidence.uncertainKeys, [key])
        XCTAssertEqual(findings.map(\.severity), [.blocking, .warning])
        XCTAssertEqual(findings.filter(\.blocksKeyboardTranslation).count, 1)

        let malformed = ModifierMappingEvidence.evaluate(
            preferences: [key: "unexpected value"],
            connectedKeyboards: [ModifierKeyboardIdentity(vendor: 1, product: 2, location: 1)]
        )
        XCTAssertTrue(malformed.activeKeys.isEmpty)
        XCTAssertEqual(malformed.uncertainKeys, [key])

        let malformedNumbers = ModifierMappingEvidence.evaluate(
            preferences: [key: [
                ["HIDKeyboardModifierMappingSrc": NSNumber(value: true),
                 "HIDKeyboardModifierMappingDst": 0x7000000E0],
                ["HIDKeyboardModifierMappingSrc": NSNumber(value: -1),
                 "HIDKeyboardModifierMappingDst": 0x7000000E0],
                ["HIDKeyboardModifierMappingSrc": NSNumber(value: 1.5),
                 "HIDKeyboardModifierMappingDst": 0x7000000E0],
            ]],
            connectedKeyboards: [ModifierKeyboardIdentity(vendor: 1, product: 2, location: 1)]
        )
        XCTAssertTrue(malformedNumbers.activeKeys.isEmpty)
        XCTAssertEqual(malformedNumbers.uncertainKeys, [key])
        XCTAssertEqual(MacOSModifierMappingConflictRule().findings(in: ConflictSnapshot(
            uncertainMacOSModifierMappingKeys: malformedNumbers.uncertainKeys
        )).first?.severity, .warning)

        for suffix in ["-1-2-0", "1--2-0", "1-2-0-"] {
            let malformedKey = "com.apple.keyboard.modifiermapping.\(suffix)"
            let evidence = ModifierMappingEvidence.evaluate(
                preferences: [malformedKey: [[
                    "HIDKeyboardModifierMappingSrc": 0x7000000E3,
                    "HIDKeyboardModifierMappingDst": 0x7000000E0,
                ]]],
                connectedKeyboards: [ModifierKeyboardIdentity(vendor: 1, product: 2, location: 0)]
            )
            XCTAssertTrue(evidence.activeKeys.isEmpty)
            XCTAssertEqual(evidence.uncertainKeys, [malformedKey])
        }
    }

    func testOnlyCurrentHostPreferenceFileIsConsidered() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let byHost = home.appendingPathComponent("Library/Preferences/ByHost")
        try FileManager.default.createDirectory(
            at: byHost, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }
        let key = "com.apple.keyboard.modifiermapping.1-2-0"
        let mapping: [String: Any] = [key: [[
            "HIDKeyboardModifierMappingSrc": 0x7000000E3,
            "HIDKeyboardModifierMappingDst": 0x7000000E0,
        ]]]
        let data = try PropertyListSerialization.data(
            fromPropertyList: mapping, format: .binary, options: 0
        )
        try data.write(to: byHost.appendingPathComponent(
            ".GlobalPreferences.OLD-HOST.plist"
        ))
        let provider = SystemConflictSnapshotProvider(
            homeDirectory: home,
            hostIdentifierOverride: "CURRENT-HOST",
            connectedKeyboardsOverride: [
                ModifierKeyboardIdentity(vendor: 1, product: 2, location: 0),
            ],
            globalDomainOverride: [:]
        )
        XCTAssertTrue(provider.macOSModifierMappingEvidence().activeKeys.isEmpty)
        XCTAssertTrue(provider.macOSModifierMappingEvidence().uncertainKeys.isEmpty)

        try data.write(to: byHost.appendingPathComponent(
            ".GlobalPreferences.CURRENT-HOST.plist"
        ))
        XCTAssertEqual(provider.macOSModifierMappingEvidence().activeKeys, [key])

        let defaultData = try PropertyListSerialization.data(
            fromPropertyList: [key: []], format: .binary, options: 0
        )
        try defaultData.write(to: byHost.appendingPathComponent(
            ".GlobalPreferences.CURRENT-HOST.plist"
        ))
        try data.write(to: home.appendingPathComponent(
            "Library/Preferences/.GlobalPreferences.plist"
        ))
        XCTAssertTrue(provider.macOSModifierMappingEvidence().activeKeys.isEmpty)
    }

    func testKarabinerBlocksOnlyWhileUserRemappingProcessRuns() {
        let evaluator = ConflictRuleEvaluator(rules: ConflictRules.standard)

        let dormantFindings = evaluator.evaluate(
            ConflictSnapshot(
                installedApplicationBundleIdentifiers: [
                    "org.pqrs.karabiner-elements",
                ],
                runningProcessNames: [
                    "karabiner-core-service",
                    "karabiner-virtualhiddevice-daemon",
                ]
            )
        )
        let activeFindings = evaluator.evaluate(
            ConflictSnapshot(
                installedApplicationBundleIdentifiers: [
                    "org.pqrs.karabiner-elements",
                ],
                runningProcessNames: [
                    "karabiner_console_user_server",
                ]
            )
        )

        XCTAssertEqual(
            dormantFindings.first {
                $0.id == "app.karabiner-elements"
            }?.severity,
            .warning
        )
        XCTAssertEqual(
            activeFindings.first {
                $0.id == "app.karabiner-elements"
            }?.blocksKeyboardTranslation,
            true
        )
    }
}

private struct StubSnapshotProvider: ConflictSnapshotProviding {
    let value: ConflictSnapshot

    func snapshot() -> ConflictSnapshot {
        value
    }
}

private struct StubRule: ConflictRule {
    let id: String

    func findings(in snapshot: ConflictSnapshot) -> [ConflictFinding] {
        [
            ConflictFinding(
                id: id,
                title: id,
                message: "\(snapshot.hidutilUserKeyMappingCount)",
                recommendation: "No action",
                severity: .warning
            ),
        ]
    }
}
