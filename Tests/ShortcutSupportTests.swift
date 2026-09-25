import AppKit
import XCTest
@testable import WindsifyMac

final class ShortcutCaptureStateTests: XCTestCase {
    func testInactiveCaptureDoesNotConsumeNormalTyping() {
        var state = ShortcutCaptureState()
        XCTAssertFalse(state.consume(keyCode: MacKeyCode.c, auxiliaryKey: nil, isDown: true))
        XCTAssertFalse(state.captured)
    }

    func testOneChordConsumesRepeatAndReleaseWithoutCapturingMoreTyping() {
        var state = ShortcutCaptureState()
        state.start()
        state.modifierChanged()
        XCTAssertTrue(state.sawModifier)
        XCTAssertTrue(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: true))
        XCTAssertFalse(state.isListening)
        XCTAssertTrue(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: true, isRepeat: true))
        XCTAssertFalse(state.consume(keyCode: MacKeyCode.c, auxiliaryKey: nil, isDown: true))
        XCTAssertTrue(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: false))
        XCTAssertFalse(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: true))
    }

    func testCancellingDoesNotLeakHeldTestKeyRelease() {
        var state = ShortcutCaptureState()
        state.start()
        XCTAssertTrue(state.consume(keyCode: nil, auxiliaryKey: 999, isDown: true))
        state.cancel()
        XCTAssertTrue(state.consume(keyCode: nil, auxiliaryKey: 999, isDown: false))
        XCTAssertFalse(state.consume(keyCode: nil, auxiliaryKey: 999, isDown: true))
    }

    func testCancelBeforePressCollectsNothing() {
        var state = ShortcutCaptureState()
        state.start()
        state.cancel()
        XCTAssertFalse(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: true))
        XCTAssertFalse(state.captured)
    }

    func testMissingReleaseDoesNotSwallowNextFreshPressOrNextTest() {
        var state = ShortcutCaptureState()
        state.start()
        XCTAssertTrue(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: true))
        state.cancel()
        XCTAssertFalse(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: true))
        state.start()
        XCTAssertTrue(state.consume(keyCode: MacKeyCode.f4, auxiliaryKey: nil, isDown: true))
        XCTAssertTrue(state.captured)
    }
}

@MainActor
final class ShortcutSupportTests: XCTestCase {
    private let healthy = ShortcutSupportStatus(keyboardEnabled: true, keyboardRunning: true, accessibilityGranted: true)

    private func makeModel(status: ShortcutSupportStatus? = nil) -> ShortcutSupportModel {
        let model = ShortcutSupportModel()
        let snapshot = status ?? healthy
        model.statusProvider = { snapshot }
        model.isApplicationActive = { true }
        model.secureInputProvider = { false }
        return model
    }

    private func event(code: UInt16 = MacKeyCode.f4, down: Bool = true, flags: CGEventFlags = [.maskAlternate]) -> CGEvent {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: code, keyDown: down)!
        event.flags = flags
        return event
    }

    func testLiveClaudeCheckObservesOneActualDecisionWithoutChangingEvent() {
        let model = makeModel()
        model.kind = .liveChat
        model.isApplicationActive = { false }
        model.start()
        let key = event(code: MacKeyCode.c, flags: [.maskControl])
        let originalFlags = key.flags
        let stroke = KeyboardStroke(keyCode: MacKeyCode.c, modifiers: [.control])
        let context = CodeEditorPolicy.context(bundleIdentifier: "com.anthropic.claudefordesktop", focus: .unknown)
        let decision = RuleDecision(ruleID: "editor.unknown-native", action: .passThrough)
        XCTAssertNil(model.intercept(type: .keyDown, event: key))
        XCTAssertTrue(model.isListening)
        model.observeLive(event: key, stroke: stroke, context: context, decision: decision, contextMilliseconds: 76)
        XCTAssertEqual(model.result?.ruleID, "editor.unknown-native")
        XCTAssertEqual(model.result?.outcome, "live-decision-captured")
        XCTAssertEqual(key.flags, originalFlags)
        XCTAssertEqual(key.getIntegerValueField(.eventSourceUserData), 0)
        XCTAssertTrue(model.report.contains("Live focus: unknown"))
        XCTAssertTrue(model.report.contains("Context lookup ms: 76"))
        XCTAssertFalse(model.report.contains("Preview context: standard text input"))
        XCTAssertFalse(model.isListening)
        let report = model.report
        model.observeLive(event: key, stroke: stroke, context: context,
                          decision: .init(ruleID: "different", action: .suppress), contextMilliseconds: 0)
        XCTAssertEqual(model.report, report)
        XCTAssertNil(model.intercept(type: .keyUp, event: event(code: MacKeyCode.c, down: false, flags: [.maskControl])))
    }

    func testLiveChatGPTCheckCapturesOneDecisionWithoutConsumingTheShortcut() {
        let model = makeModel()
        model.kind = .liveChat
        model.isApplicationActive = { false }
        model.start()
        let key = event(code: MacKeyCode.v, flags: [.maskControl])
        let stroke = KeyboardStroke(keyCode: MacKeyCode.v, modifiers: [.control])
        let context = CodeEditorPolicy.context(bundleIdentifier: "com.openai.codex", focus: .textInput)
        let decision = RuleDecision(ruleID: "generic.control-to-command", action: .replace([
            .init(keyCode: MacKeyCode.v, modifiers: [.command])
        ]))
        XCTAssertNil(model.intercept(type: .keyDown, event: key))
        model.observeLive(event: key, stroke: stroke, context: context, decision: decision, contextMilliseconds: 3)
        XCTAssertEqual(model.result?.ruleID, "generic.control-to-command")
        XCTAssertTrue(model.report.contains("Live application: com.openai.codex"))
        XCTAssertFalse(model.isListening)
        XCTAssertEqual(key.flags, [.maskControl])
    }

    func testLiveCheckIgnoresUnarmedOtherAppTypingRepeatsAndSyntheticEvents() {
        let model = makeModel()
        model.kind = .liveChat
        let key = event(code: MacKeyCode.v, flags: [.maskControl])
        let stroke = KeyboardStroke(keyCode: MacKeyCode.v, modifiers: [.control])
        let context = CodeEditorPolicy.context(bundleIdentifier: "com.anthropic.claudefordesktop", focus: .textInput)
        let decision = KeyboardMappingEngine().evaluate(stroke, context: context)
        func observe(_ context: MappingContext, _ stroke: KeyboardStroke) {
            model.observeLive(event: key, stroke: stroke, context: context, decision: decision, contextMilliseconds: 1)
        }
        observe(context, stroke)
        XCTAssertNil(model.result)
        model.start()
        observe(.init(bundleIdentifier: "com.example.other"), stroke)
        observe(context, .init(keyCode: MacKeyCode.v))
        observe(context, .init(keyCode: MacKeyCode.a, modifiers: [.control]))
        observe(context, .init(keyCode: MacKeyCode.v, phase: .up, modifiers: [.control]))
        key.setIntegerValueField(.eventSourceUserData, value: CGEventTapController.syntheticEventMarker)
        observe(context, stroke)
        key.setIntegerValueField(.eventSourceUserData, value: 0)
        key.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        observe(context, stroke)
        XCTAssertNil(model.result)
        XCTAssertTrue(model.isListening)
        key.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        model.cancel()
        observe(context, stroke)
        XCTAssertNil(model.result)
    }

    func testAltF4PreviewCapturesMappingWithoutDispatchingAndRetainsSingleSample() {
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.intercept(type: .keyDown, event: event()), true)
        XCTAssertEqual(model.result?.outcome, "mapping-recognized-preview-only")
        XCTAssertEqual(model.result?.ruleID, "generic.alt-f4")
        XCTAssertEqual(model.result?.receivedShortcut, "Option + F4")
        XCTAssertEqual(model.result?.output, "Command + W")
        XCTAssertFalse(model.isListening)
        let report = model.report
        XCTAssertNil(model.intercept(type: .keyDown, event: event(code: MacKeyCode.c)))
        XCTAssertEqual(model.report, report)
        XCTAssertEqual(model.intercept(type: .keyUp, event: event(down: false)), true)
    }

    func testFnAltF4IsRecognized() {
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.intercept(type: .keyDown, event: event(flags: [.maskAlternate, .maskSecondaryFn])), true)
        XCTAssertEqual(model.result?.outcome, "mapping-recognized-preview-only")
        XCTAssertTrue(model.result?.sample?.modifiers.contains("function") == true)
    }

    func testModernSpotlightPreviewRetainsRawInputAndConsumesRelease() {
        let model = makeModel()
        model.start()
        let flags: CGEventFlags = [.maskAlternate, .maskSecondaryFn]
        XCTAssertEqual(model.intercept(type: .keyDown, event: event(code: 177, flags: flags)), true)
        XCTAssertEqual(model.result?.outcome, "mapping-recognized-preview-only")
        XCTAssertEqual(model.result?.sample?.keyCode, 177)
        XCTAssertTrue(model.result?.sample?.modifiers.contains("function") == true)
        XCTAssertEqual(model.result?.receivedShortcut, "Option + Spotlight")
        XCTAssertEqual(model.result?.ruleID, "generic.alt-f4")
        XCTAssertEqual(model.result?.output, "Command + W")
        XCTAssertEqual(model.intercept(type: .keyUp, event: event(code: 177, down: false, flags: flags)), true)
        XCTAssertFalse(model.isListening)
    }

    func testOrdinaryUnrelatedShortcutGetsActionableExplanation() {
        let model = makeModel()
        model.start()
        _ = model.intercept(type: .keyDown, event: event(code: MacKeyCode.c, flags: [.maskControl]))
        XCTAssertEqual(model.result?.outcome, "different-shortcut")
        XCTAssertTrue(model.result?.explanation.contains("Option") == true)
    }

    func testAnotherShortcutUsesSharedFreeEngine() {
        let model = makeModel()
        model.kind = .anotherShortcut
        model.start()
        _ = model.intercept(type: .keyDown, event: event(code: MacKeyCode.c, flags: [.maskControl]))
        XCTAssertEqual(model.result?.ruleID, "generic.control-to-command")
    }

    func testOffEngineIsNotMisreportedAsSuccessfulShortcut() {
        let model = makeModel(status: ShortcutSupportStatus(accessibilityGranted: true))
        model.start()
        _ = model.intercept(type: .keyDown, event: event())
        XCTAssertEqual(model.result?.outcome, "runtime-unavailable")
        XCTAssertTrue(model.result?.explanation.contains("switched off") == true)
    }

    func testDeniedPermissionAndConflictHaveDistinctAdvice() {
        XCTAssertTrue(ShortcutSupportStatus().explanation?.contains("Accessibility") == true)
        var status = healthy
        status.blockedByConflict = true
        status.conflictIDs = ["app.karabiner-elements"]
        XCTAssertTrue(status.explanation?.contains("pausing") == true)
        let report = ShortcutSupportModel.makeReport(kind: .closeWindow, result: nil, status: status, metadata: [])
        XCTAssertTrue(report.contains("app.karabiner-elements"))
    }

    func testUnknownAuxiliaryKeyReachesDiagnosticBeforeDecoder() {
        let model = makeModel()
        model.start()
        let nsEvent = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                         modifierFlags: [.option], timestamp: 0,
                                         windowNumber: 0, context: nil, subtype: 8,
                                         data1: (999 << 16) | (0xA << 8), data2: 0)!
        XCTAssertEqual(model.intercept(type: CGEventType(rawValue: 14)!, event: nsEvent.cgEvent!), true)
        XCTAssertEqual(model.result?.outcome, "unsupported-special-key")
        XCTAssertEqual(model.result?.sample?.auxiliaryKeyType, 999)
        XCTAssertNil(model.result?.ruleID)
    }

    func testReportDoesNotReadEventCharacters() {
        let model = makeModel()
        model.start()
        let key = event()
        let sensitive = Array("NEVER_EXPORT_THIS_TYPED_TEXT".utf16)
        sensitive.withUnsafeBufferPointer {
            key.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!)
        }
        _ = model.intercept(type: .keyDown, event: key)
        XCTAssertFalse(model.report.contains("NEVER_EXPORT_THIS_TYPED_TEXT"))
        XCTAssertTrue(model.report.contains("Input event:"))
        XCTAssertTrue(model.report.contains("no command executed"))
    }

    func testSyntheticEventsAreNeverCaptured() {
        let model = makeModel()
        model.start()
        let key = event()
        key.setIntegerValueField(.eventSourceUserData, value: CGEventTapController.syntheticEventMarker)
        XCTAssertNil(model.intercept(type: .keyDown, event: key))
        XCTAssertTrue(model.isListening)
        XCTAssertNil(model.result)
        model.cancel()
    }

    func testLosingFocusStopsCollectionAndDoesNotConsumeOtherAppsKeys() {
        let model = makeModel()
        model.start()
        model.isApplicationActive = { false }
        XCTAssertNil(model.intercept(type: .keyDown, event: event()))
        XCTAssertFalse(model.isListening)
        XCTAssertEqual(model.result?.outcome, "focus-lost")
        XCTAssertNil(model.result?.sample)
    }

    func testNoEventResultDoesNotClaimKeyboardSentNothing() {
        let result = ShortcutSupportResult.endedWithoutKey(sawModifier: true, lostFocus: false, status: healthy)
        XCTAssertEqual(result.outcome, "no-shortcut-observed")
        XCTAssertTrue(result.explanation.contains("no complete shortcut reached"))
        XCTAssertNil(result.sample)
    }

    func testHideCancelsPendingCapture() {
        let model = makeModel()
        model.start()
        model.hide()
        XCTAssertNil(model.intercept(type: .keyDown, event: event()))
        XCTAssertFalse(model.isListening)
        XCTAssertTrue(model.report.isEmpty)
    }
}
