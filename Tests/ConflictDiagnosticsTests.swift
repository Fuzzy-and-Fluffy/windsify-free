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
            macOSModifierMappingPreferenceKeys: [
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
