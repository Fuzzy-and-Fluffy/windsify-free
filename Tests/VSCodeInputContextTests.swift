import XCTest
@testable import WindsifyMac

final class VSCodeInputContextTests: XCTestCase {
    func testFocusedTerminalRequiresBothInputAndTerminalStructure() {
        let leaf = VSCodeFocusClassifier.Node(role: "AXTextField", classes: ["xterm-helper-textarea"])
        let host = VSCodeFocusClassifier.Node(role: "AXGroup", classes: ["xterm", "terminal"])
        XCTAssertEqual(VSCodeFocusClassifier.classify([leaf, host]), .terminal)
        XCTAssertEqual(VSCodeFocusClassifier.classify([leaf]), .unknown)
        XCTAssertEqual(VSCodeFocusClassifier.classify([host]), .unknown)
        XCTAssertEqual(VSCodeFocusClassifier.classify([]), .unknown)
    }

    func testTerminalFindAndMonacoEditorAreTextInputsEvenWithTerminalAncestor() {
        let terminal = VSCodeFocusClassifier.Node(role: "AXGroup", classes: ["xterm"])
        XCTAssertEqual(VSCodeFocusClassifier.classify([
            .init(role: "AXTextField", classes: ["input", "empty"]),
            .init(role: "AXGroup", classes: ["monaco-inputbox"]), terminal,
        ]), .textInput)
        for inputClass in ["native-edit-context", "inputarea"] {
            XCTAssertEqual(VSCodeFocusClassifier.classify([
                .init(role: "AXTextArea", classes: [inputClass]),
                .init(role: "AXGroup", classes: ["monaco-editor"]), terminal,
            ]), .textInput)
        }
        XCTAssertEqual(VSCodeFocusClassifier.classify([
            .init(role: "AXTextField", classes: ["future-terminal-input"]), terminal,
        ]), .unknown)
    }

    func testFreeProtectsTerminalControlsAndKeepsEditorMapping() {
        verifyPolicy(KeyboardMappingEngine())
    }

    private func verifyPolicy(_ engine: any KeyboardMappingEvaluating) {
        let bundle = "com.microsoft.VSCode"
        let terminal = MappingContext(bundleIdentifier: bundle, vscodeInputContext: .terminal)
        for code in [MacKeyCode.c, MacKeyCode.v, MacKeyCode.r, MacKeyCode.a,
                     MacKeyCode.e, MacKeyCode.u, MacKeyCode.w, MacKeyCode.y,
                     MacKeyCode.d, MacKeyCode.z, MacKeyCode.leftArrow, MacKeyCode.f4] {
            for phase in [KeyPhase.down, .up] {
                XCTAssertEqual(engine.evaluate(.init(keyCode: code, phase: phase, modifiers: [.control]),
                                               context: terminal).action, .passThrough)
            }
        }
        for code in [MacKeyCode.c, MacKeyCode.v] {
            XCTAssertEqual(engine.evaluate(.init(keyCode: code, modifiers: [.control, .shift]), context: terminal).action,
                           .passThrough)
            XCTAssertEqual(engine.evaluate(.init(keyCode: code, modifiers: [.command]), context: terminal).action, .passThrough)
        }
        let editor = MappingContext(bundleIdentifier: bundle, isTextInput: true, vscodeInputContext: .textInput)
        XCTAssertEqual(engine.evaluate(.init(keyCode: MacKeyCode.c, modifiers: [.control]), context: editor).action,
                       .replace([.init(keyCode: MacKeyCode.c, modifiers: [.command])]))
        XCTAssertEqual(engine.evaluate(.init(keyCode: MacKeyCode.c, modifiers: [.control]),
                                       context: .init(bundleIdentifier: bundle)).action, .passThrough)
    }

    func testNativePreferenceAndSecurityTakePrecedence() {
        let engine = KeyboardMappingEngine()
        let stroke = KeyboardStroke(keyCode: MacKeyCode.c, modifiers: [.control, .shift])
        let excluded = MappingContext(bundleIdentifier: "com.microsoft.VSCode", vscodeInputContext: .terminal,
                                      keyboardMappingExcluded: true)
        XCTAssertEqual(engine.evaluate(stroke, context: excluded).ruleID, "native.application-excluded")
        XCTAssertFalse(engine.permitsHostShortcut(in: excluded))
        XCTAssertEqual(engine.evaluate(stroke, context: .init(bundleIdentifier: "com.microsoft.VSCode", isSecureInput: true,
                                                              vscodeInputContext: .terminal)).ruleID, "native.secure-input")
        XCTAssertEqual(engine.evaluate(stroke, context: .init(bundleIdentifier: "com.microsoft.windowsapp",
                                                              vscodeInputContext: .terminal)).ruleID, "native.remote-desktop")
        XCTAssertFalse(VSCodeFocusClassifier.supports(bundleIdentifier: "com.example.vscode"))
    }

    func testNativeDownStaysNativeAcrossFocusAndModifierChangesUntilRelease() {
        var transactions = NativeKeyboardTransactionStore()
        let down = KeyboardStroke(keyCode: MacKeyCode.c, modifiers: [.control])
        XCTAssertFalse(transactions.continues(down, isRepeat: false))
        transactions.begin(MacKeyCode.c)
        XCTAssertTrue(transactions.continues(down, isRepeat: true))
        XCTAssertTrue(transactions.continues(.init(keyCode: MacKeyCode.c, phase: .up), isRepeat: false))
        XCTAssertFalse(transactions.continues(down, isRepeat: false))
        transactions.begin(MacKeyCode.c)
        // A fresh nonrepeat down repairs an unmatched release without sticking.
        XCTAssertFalse(transactions.continues(down, isRepeat: false))
        XCTAssertFalse(transactions.continues(.init(keyCode: MacKeyCode.c, phase: .up), isRepeat: false))
    }

    func testTerminalSetupPreservesJSONCAndIsReversibleAndIdempotent() throws {
        for original in ["[]", "[\n// empty\n]\n", "[{\"key\":\"cmd+k\",\"command\":\"x\"}]",
                         "// title\n[{\"key\":\"cmd+k\",\"command\":\"bracket ] and // text\"}, // trailing\n]\n// footer"] {
            let configured = try VSCodeTerminalSetup.configuring(original)
            XCTAssertEqual(try VSCodeTerminalSetup.configuring(configured), configured)
            XCTAssertEqual(try VSCodeTerminalSetup.removingBlock(from: configured), original)
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(configured.utf8), options: [.json5Allowed]) as? [[String: Any]])
            let copy = values.first { $0["key"] as? String == "ctrl+c" }
            XCTAssertEqual(copy?["command"] as? String, "workbench.action.terminal.copyAndClearSelection")
            XCTAssertEqual(copy?["when"] as? String, "(terminalFocus && terminalTextSelected) || terminalTextSelectedInFocused")
            let interrupt = values.first { ($0["when"] as? String)?.contains("!terminalTextSelected") == true }
            XCTAssertEqual((interrupt?["args"] as? [String: String])?["text"], "\u{03}")
            XCTAssertEqual(interrupt?["when"] as? String, "terminalFocus && !terminalTextSelected && !terminalTextSelectedInFocused")
            XCTAssertTrue(values.suffix(11).allSatisfy { ($0["when"] as? String)?.contains("terminalFocus") == true })
        }
    }

    func testTerminalSetupRejectsMalformedOrEditedManagedConfiguration() throws {
        XCTAssertThrowsError(try VSCodeTerminalSetup.configuring("{}"))
        XCTAssertThrowsError(try VSCodeTerminalSetup.configuring("[invalid"))
        let configured = try VSCodeTerminalSetup.configuring("[]")
        let edited = configured.replacingOccurrences(of: "copyAndClearSelection", with: "userCommand")
        XCTAssertThrowsError(try VSCodeTerminalSetup.removingBlock(from: edited))
        XCTAssertThrowsError(try VSCodeTerminalSetup.configuring(edited))
    }

    func testTerminalSetupWritesBackupAndRestoresUnrelatedBindings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keybindings.json")
        let original = Data("[{\"key\":\"cmd+c\",\"command\":\"old-custom-copy\",\"when\":\"terminalFocus\"}]".utf8)
        try original.write(to: file)
        let backup = try XCTUnwrap(VSCodeTerminalSetup.apply(to: file, enabled: true, backupDirectory: root))
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertNil(try VSCodeTerminalSetup.apply(to: file, enabled: true, backupDirectory: root))
        try VSCodeTerminalSetup.apply(to: file, enabled: false, backupDirectory: root)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
