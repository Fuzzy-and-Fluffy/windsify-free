import XCTest
@testable import WindsifyMac

final class CodeEditorPolicyTests: XCTestCase {
    private func traverse(_ path: [EditorFocusClassifier.Node], coldDelay: TimeInterval = 0,
                          focusUnchanged: Bool = true) -> EditorInputContext {
        var clock = coldDelay
        return EditorFocusTraversal.resolve(focused: 0, deadline: EditorFocusTraversal.queryBudget,
            now: { clock }, read: { index in
                clock += 0.0001
                guard path.indices.contains(index) else { return nil }
                return (path[index], index + 1 < path.count ? index + 1 : nil)
            }, focusUnchanged: { focusUnchanged })
    }

    func testObservedClaudeComposerDepthAndColdLookupStillUseOrdinaryMappings() {
        for depth in [25, 40, 64] {
            let path = [EditorFocusClassifier.Node(role: "AXTextArea", classes: [])] +
                Array(repeating: .init(role: "AXGroup", classes: []), count: depth - 2) +
                [.init(role: "AXWebArea", classes: [])]
            let focus = traverse(path, coldDelay: 0.040)
            XCTAssertEqual(focus, .textInput)
            let context = CodeEditorPolicy.context(bundleIdentifier: "com.anthropic.claudefordesktop", focus: focus)
            for key in [MacKeyCode.a, MacKeyCode.c, MacKeyCode.v] {
                XCTAssertEqual(KeyboardMappingEngine().evaluate(.init(keyCode: key, modifiers: [.control]), context: context).action,
                               .replace([.init(keyCode: key, modifiers: [.command])]))
            }
        }
    }

    func testDeeperTraversalStillDistinguishesTerminalFromMessageSelection() {
        let groups = Array(repeating: EditorFocusClassifier.Node(role: "AXGroup", classes: []), count: 30)
        let root = EditorFocusClassifier.Node(role: "AXWebArea", classes: [])
        let terminal = [EditorFocusClassifier.Node(role: "AXTextField", classes: ["xterm-helper-textarea"])] +
            groups + [.init(role: "AXGroup", classes: ["xterm"]), root]
        XCTAssertEqual(traverse(terminal, coldDelay: 0.040), .terminal)
        XCTAssertEqual(traverse([.init(role: "AXGroup", classes: [])] + groups + [root]), .textInput)
        XCTAssertEqual(traverse([.init(role: "AXGroup", classes: [])] + groups + [.init(role: "AXGroup", classes: ["xterm"]), root]), .unknown)
    }

    func testTraversalRejectsStaleIncompleteAndOverBudgetResults() {
        let root = EditorFocusClassifier.Node(role: "AXWebArea", classes: [])
        let group = EditorFocusClassifier.Node(role: "AXGroup", classes: [])
        XCTAssertEqual(traverse([group, root], focusUnchanged: false), .unknown)
        XCTAssertEqual(traverse([group, root], coldDelay: 0.076), .unknown)
        XCTAssertEqual(traverse([group]), .unknown)
        XCTAssertEqual(traverse(Array(repeating: group, count: 64) + [root]), .unknown)
        var reads = 0
        XCTAssertEqual(EditorFocusTraversal.resolve(focused: 0, deadline: 1, now: { 0 }, read: { index in
            reads += 1
            return (group, index)
        }, focusUnchanged: { true }), .unknown)
        XCTAssertEqual(reads, EditorFocusTraversal.maximumDepth)
    }

    func testFreePassesTerminalAndUnknownPanesThroughInEveryKnownEditor() {
        let free = KeyboardMappingEngine()
        for app in CodeEditorPolicy.bundleIdentifiers {
            let resolved = free.codeEditorContext(bundleIdentifier: app, processIdentifier: -1)
            XCTAssertEqual(resolved?.keyboardMappingExcluded, false)
            XCTAssertEqual(resolved?.editorInputContext, .unknown)
            for pane in [EditorInputContext.unknown, .terminal] {
                let context = CodeEditorPolicy.context(bundleIdentifier: app, focus: pane)
                XCTAssertFalse(free.permitsHostShortcut(in: context))
                for code in [MacKeyCode.a, MacKeyCode.c, MacKeyCode.v, MacKeyCode.home, MacKeyCode.end,
                             MacKeyCode.f4, MacKeyCode.space, MacKeyCode.leftArrow, MacKeyCode.insert,
                             MacKeyCode.four, MacKeyCode.tab] {
                    for mods: Set<KeyModifier> in [[], [.control], [.control, .shift], [.option], [.command], [.shift]] {
                        for phase in [KeyPhase.down, .up] {
                            XCTAssertEqual(free.evaluate(.init(keyCode: code, phase: phase, modifiers: mods), context: context).action, .passThrough, app)
                        }
                    }
                }
            }
        }
    }

    func testFreeMainViewsUseTheCompleteOrdinaryFreePolicy() {
        let free = KeyboardMappingEngine()
        let ordinary = MappingContext(bundleIdentifier: "com.example.editor", isTextInput: true)
        let flags: [KeyModifier] = [.control, .shift, .option, .command, .function]
        for app in CodeEditorPolicy.bundleIdentifiers {
            let main = CodeEditorPolicy.context(bundleIdentifier: app, focus: .textInput)
            XCTAssertTrue(free.permitsHostShortcut(in: main))
            for bits in 0..<(1 << flags.count) {
                let mods = Set(flags.enumerated().compactMap { bits & (1 << $0.offset) != 0 ? $0.element : nil })
                for code: UInt16 in 0..<128 {
                    for phase in [KeyPhase.down, .up] {
                        let stroke = KeyboardStroke(keyCode: code, phase: phase, modifiers: mods)
                        XCTAssertEqual(free.evaluate(stroke, context: main), free.evaluate(stroke, context: ordinary), app)
                    }
                }
            }
        }
    }

    func testSharedFocusClassifierSeparatesTerminalMainAndIncompletePaths() {
        let root = EditorFocusClassifier.Node(role: "AXWebArea", classes: [])
        let terminal = EditorFocusClassifier.Node(role: "AXGroup", classes: ["xterm"])
        let input = EditorFocusClassifier.Node(role: "AXTextArea", classes: ["xterm-helper-textarea"])
        XCTAssertEqual(EditorFocusClassifier.classify([input, terminal, root]), .terminal)
        XCTAssertEqual(EditorFocusClassifier.classify([input, root]), .unknown)
        XCTAssertEqual(EditorFocusClassifier.classify([input]), .unknown)
        XCTAssertEqual(EditorFocusClassifier.classify([]), .unknown)
        for role in ["AXTextArea", "AXTextField", "AXStaticText", "AXGroup", "AXButton"] {
            let main = EditorFocusClassifier.Node(role: role, classes: [])
            XCTAssertEqual(EditorFocusClassifier.classify([main, root]), .textInput)
            XCTAssertEqual(EditorFocusClassifier.classify([main]), .unknown)
            XCTAssertEqual(EditorFocusClassifier.classify([main, terminal, root]), .unknown)
        }
        let monaco = EditorFocusClassifier.Node(role: "AXGroup", classes: ["monaco-editor"])
        let editor = EditorFocusClassifier.Node(role: "AXTextArea", classes: ["inputarea"])
        XCTAssertEqual(EditorFocusClassifier.classify([editor, monaco]), .textInput)
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
