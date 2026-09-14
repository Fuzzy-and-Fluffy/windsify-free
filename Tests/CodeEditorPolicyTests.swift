import XCTest
@testable import WindsifyMac

final class CodeEditorPolicyTests: XCTestCase {
    func testFreeNeverRequestsEditorPaneDiscovery() {
        let free = KeyboardMappingEngine()
        for app in CodeEditorPolicy.bundleIdentifiers {
            XCTAssertNil(free.codeEditorContext(bundleIdentifier: app, processIdentifier: -1))
            XCTAssertFalse(free.preservesCodeEditorKeyboard(bundleIdentifier: app))
        }
    }

    func testFreeUsesGenericClipboardAndSwitchingRegardlessOfPaneMetadata() {
        let free = KeyboardMappingEngine()
        for app in CodeEditorPolicy.bundleIdentifiers {
            for focus in [EditorInputContext.unknown, .terminal, .textInput] {
                let context = CodeEditorPolicy.context(bundleIdentifier: app, focus: focus)
                let ordinary = MappingContext(bundleIdentifier: "com.example.generic", isTextInput: context.isTextInput)
                XCTAssertTrue(free.permitsHostShortcut(in: context))
                for code: UInt16 in 0..<128 {
                    for mods: Set<KeyModifier> in [[], [.control], [.control, .shift], [.option], [.command], [.shift]] {
                        for phase in [KeyPhase.down, .up] {
                            let key = KeyboardStroke(keyCode: code, phase: phase, modifiers: mods)
                            XCTAssertEqual(free.evaluate(key, context: context), free.evaluate(key, context: ordinary), app)
                        }
                    }
                }
                for code in [MacKeyCode.a, MacKeyCode.c, MacKeyCode.v] {
                    XCTAssertEqual(free.evaluate(.init(keyCode: code, modifiers: [.control]), context: context).action,
                                   .replace([.init(keyCode: code, modifiers: [.command])]))
                }
            }
        }
    }

    func testFreeRetainsStandaloneTerminalAndExplicitSafetyGuards() {
        let free = KeyboardMappingEngine()
        let key = KeyboardStroke(keyCode: MacKeyCode.c, modifiers: [.control])
        for app in KeyboardMappingEngine.defaultTerminalBundleIdentifiers {
            XCTAssertEqual(free.evaluate(key, context: .init(bundleIdentifier: app)).action, .passThrough)
        }
        for context in [MappingContext(bundleIdentifier: "com.microsoft.vscode", isSecureInput: true),
                        .init(bundleIdentifier: "com.microsoft.vscode", keyboardMappingExcluded: true),
                        .init(bundleIdentifier: "com.microsoft.rdc.macos")] {
            XCTAssertEqual(free.evaluate(key, context: context).action, .passThrough)
            XCTAssertFalse(free.permitsHostShortcut(in: context))
        }
    }
}
