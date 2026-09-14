import XCTest
@testable import WindsifyMac

final class CodeEditorPolicyTests: XCTestCase {
    func testFreeLeavesEveryKnownEditorKeyAndPaneNative() {
        let free = KeyboardMappingEngine()
        for app in CodeEditorPolicy.bundleIdentifiers {
            // An invalid PID proves Free never needs to query a running editor.
            let resolved = free.codeEditorContext(bundleIdentifier: app, processIdentifier: -1)
            XCTAssertEqual(resolved?.keyboardMappingExcluded, true)
            XCTAssertEqual(resolved?.vscodeInputContext, .unknown)
            for pane in [VSCodeInputContext.unknown, .terminal, .textInput] {
                let context = MappingContext(bundleIdentifier: app, isTextInput: true, vscodeInputContext: pane)
                XCTAssertFalse(free.permitsHostShortcut(in: context))
                for code in [MacKeyCode.c, MacKeyCode.v, MacKeyCode.home, MacKeyCode.end, MacKeyCode.f4, MacKeyCode.space, MacKeyCode.leftArrow, MacKeyCode.insert] {
                    for mods: Set<KeyModifier> in [[], [.control], [.control, .shift], [.option], [.command], [.shift]] {
                        for phase in [KeyPhase.down, .up] {
                            XCTAssertEqual(free.evaluate(.init(keyCode: code, phase: phase, modifiers: mods), context: context).action, .passThrough, app)
                        }
                    }
                }
            }
        }
    }
    func testOrdinaryAppStillGetsFreeEditingAndUnknownAppsAreNotMisclassified() {
        let free = KeyboardMappingEngine()
        XCTAssertFalse(CodeEditorPolicy.contains("com.example.not-vscode"))
        XCTAssertNil(free.codeEditorContext(bundleIdentifier: "com.apple.TextEdit", processIdentifier: -1))
        XCTAssertEqual(free.evaluate(.init(keyCode: MacKeyCode.c, modifiers: [.control]), context: .init(bundleIdentifier: "com.apple.TextEdit", isTextInput: true)).action,
                       .replace([.init(keyCode: MacKeyCode.c, modifiers: [.command])]))
    }
    func testLegacyCleanupNeverChangesUnrelatedOrEditedSettings() throws {
        let original = "[{\"key\":\"ctrl+c\",\"command\":\"user-command\"}]"
        XCTAssertEqual(try VSCodeLegacyCleanup.removingLegacyBlock(from: original), original)
        XCTAssertThrowsError(try VSCodeLegacyCleanup.removingLegacyBlock(from: "[" + VSCodeLegacyCleanup.begin + "{\"key\":\"ctrl+c\",\"command\":\"custom\"}" + VSCodeLegacyCleanup.end + "]"))
    }
}
