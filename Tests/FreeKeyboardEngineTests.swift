import XCTest
@testable import WindsifyMac

final class FreeKeyboardEngineTests: XCTestCase {
    private let engine = KeyboardMappingEngine()

    func testFreeMapsOrdinaryControlShortcutToCommand() {
        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(
                    keyCode: MacKeyCode.c,
                    modifiers: [.control]
                )
            ),
            RuleDecision(
                ruleID: "generic.control-to-command",
                action: .replace([
                    KeyboardStroke(
                        keyCode: MacKeyCode.c,
                        modifiers: [.command]
                    ),
                ])
            )
        )
    }

    func testFreePreservesShiftArrowSelection() {
        for keyCode in [
            MacKeyCode.leftArrow,
            MacKeyCode.rightArrow,
            MacKeyCode.upArrow,
            MacKeyCode.downArrow,
        ] {
            XCTAssertEqual(
                engine.evaluate(
                    KeyboardStroke(
                        keyCode: keyCode,
                        modifiers: [.shift]
                    )
                ),
                RuleDecision(
                    ruleID: "native.shift-selection",
                    action: .passThrough
                )
            )
        }
    }

    func testFreeMapsHomeAndEndOnlyInTextInput() {
        let textContext = MappingContext(isTextInput: true)

        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(keyCode: MacKeyCode.home),
                context: textContext
            ).ruleID,
            "editing.home"
        )
        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(keyCode: MacKeyCode.end),
                context: textContext
            ).ruleID,
            "editing.end"
        )
        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(keyCode: MacKeyCode.home)
            ),
            RuleDecision(
                ruleID: "native.unmapped",
                action: .passThrough
            )
        )
    }

    func testFreePreservesTerminalControlAndRemoteDesktopShortcuts() {
        let stroke = KeyboardStroke(
            keyCode: MacKeyCode.c,
            modifiers: [.control]
        )

        XCTAssertEqual(
            engine.evaluate(
                stroke,
                context: MappingContext(
                    bundleIdentifier: "com.apple.Terminal"
                )
            ),
            RuleDecision(
                ruleID: "terminal.native-control",
                action: .passThrough
            )
        )
        XCTAssertEqual(
            engine.evaluate(
                stroke,
                context: MappingContext(
                    bundleIdentifier: "com.microsoft.rdc.macos"
                )
            ),
            RuleDecision(
                ruleID: "native.remote-desktop",
                action: .passThrough
            )
        )
    }

    func testFreeDoesNotContainProFinderSystemOrWindowRules() {
        let finderContext = MappingContext(
            bundleIdentifier: "com.apple.finder"
        )

        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(keyCode: MacKeyCode.f2),
                context: finderContext
            ),
            RuleDecision(
                ruleID: "native.unmapped",
                action: .passThrough
            )
        )
        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(
                    keyCode: MacKeyCode.e,
                    modifiers: [.command]
                )
            ),
            RuleDecision(
                ruleID: "native.unmapped",
                action: .passThrough
            )
        )
        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    modifiers: [.command]
                )
            ),
            RuleDecision(
                ruleID: "native.unmapped",
                action: .passThrough
            )
        )
    }

    func testFreeKeepsWindowsInputSourceShortcut() {
        XCTAssertEqual(
            engine.evaluate(
                KeyboardStroke(
                    keyCode: MacKeyCode.space,
                    modifiers: [.command]
                )
            ),
            RuleDecision(
                ruleID: "windows.input-source",
                action: .cycleInputSource
            )
        )
    }
}
