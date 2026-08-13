import Carbon
import XCTest
@testable import WindsifyMac

final class KeyboardRuntimeHelpersTests: XCTestCase {
    func testShiftSelectionFastPathNeverQueriesAccessibilityContext() {
        var contextQueryCount = 0
        let controller = CGEventTapController(
            contextProvider: {
                contextQueryCount += 1
                return MappingContext(isTextInput: true)
            }
        )

        let strokes = [
            KeyboardStroke(
                keyCode: MacKeyCode.leftShift,
                phase: .flagsChanged,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.leftArrow,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.leftArrow,
                phase: .up,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.rightArrow,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.rightArrow,
                phase: .up,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.upArrow,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.upArrow,
                phase: .up,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.downArrow,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.downArrow,
                phase: .up,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.leftShift,
                phase: .flagsChanged
            ),
        ]

        for stroke in strokes {
            XCTAssertTrue(controller.passesThroughBeforeContext(stroke))
        }
        XCTAssertEqual(contextQueryCount, 0)
    }

    func testOnlyCompletedCommandTapQueriesContextOnModifierFastPath() {
        var contextQueryCount = 0
        let controller = CGEventTapController(
            contextProvider: {
                contextQueryCount += 1
                return MappingContext(isSecureInput: true)
            }
        )

        XCTAssertTrue(
            controller.passesThroughBeforeContext(
                KeyboardStroke(
                    keyCode: MacKeyCode.leftCommand,
                    phase: .flagsChanged,
                    modifiers: [.command]
                )
            )
        )
        XCTAssertEqual(contextQueryCount, 0)

        XCTAssertTrue(
            controller.passesThroughBeforeContext(
                KeyboardStroke(
                    keyCode: MacKeyCode.leftCommand,
                    phase: .flagsChanged
                )
            )
        )
        XCTAssertEqual(contextQueryCount, 1)
    }

    func testCGEventNavigationShapeNormalizationAndFastPathBoundaries() {
        let source = CGEventSource(stateID: .privateState)!
        let controller = CGEventTapController(
            contextProvider: {
                XCTFail("Context-free classification must not query AX")
                return MappingContext()
            }
        )

        for keyCode in [
            MacKeyCode.leftArrow,
            MacKeyCode.rightArrow,
            MacKeyCode.downArrow,
            MacKeyCode.upArrow,
        ] {
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: true
            )!
            event.flags = [
                .maskNumericPad,
                .maskSecondaryFn,
                .maskShift,
            ]
            let stroke = CGEventTapController.keyboardStroke(
                from: event,
                type: .keyDown
            )

            XCTAssertEqual(
                stroke,
                KeyboardStroke(
                    keyCode: keyCode,
                    modifiers: [.shift]
                )
            )
            XCTAssertTrue(
                stroke.map(controller.passesThroughBeforeContext) == true
            )

            for modifiers: Set<KeyModifier> in [
                [.control, .shift],
                [.command, .shift],
            ] {
                XCTAssertFalse(
                    controller.passesThroughBeforeContext(
                        KeyboardStroke(
                            keyCode: keyCode,
                            modifiers: modifiers
                        )
                    )
                )
            }
        }

        for keyCode in [MacKeyCode.home, MacKeyCode.end] {
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: true
            )!
            event.flags = [
                .maskNumericPad,
                .maskSecondaryFn,
                .maskShift,
            ]
            let stroke = CGEventTapController.keyboardStroke(
                from: event,
                type: .keyDown
            )
            XCTAssertEqual(
                stroke,
                KeyboardStroke(
                    keyCode: keyCode,
                    modifiers: [.shift]
                )
            )
            XCTAssertFalse(
                stroke.map(controller.passesThroughBeforeContext) == true
            )
        }

        let functionEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(MacKeyCode.f5),
            keyDown: true
        )!
        functionEvent.flags = [.maskSecondaryFn, .maskShift]
        XCTAssertEqual(
            CGEventTapController.keyboardStroke(
                from: functionEvent,
                type: .keyDown
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.f5,
                modifiers: [.function, .shift]
            )
        )
    }

    func testNativeShiftSelectionRemovesOnlySecondaryFnShapeFlag() {
        let source = CGEventSource(stateID: .privateState)!

        for keyCode in [
            MacKeyCode.leftArrow,
            MacKeyCode.rightArrow,
            MacKeyCode.downArrow,
            MacKeyCode.upArrow,
        ] {
            for phase in [KeyPhase.down, .up] {
                let event = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: CGKeyCode(keyCode),
                    keyDown: phase == .down
                )!
                event.flags = [
                    .maskAlphaShift,
                    .maskNonCoalesced,
                    .maskNumericPad,
                    .maskSecondaryFn,
                    .maskShift,
                ]
                let originalStateID = event.getIntegerValueField(
                    .eventSourceStateID
                )
                let stroke = KeyboardStroke(
                    keyCode: keyCode,
                    phase: phase,
                    modifiers: [.shift]
                )

                XCTAssertTrue(
                    CGEventTapController.normalizeNativeShiftSelectionEvent(
                        event,
                        stroke: stroke
                    )
                )
                XCTAssertFalse(event.flags.contains(.maskSecondaryFn))
                XCTAssertTrue(event.flags.contains(.maskShift))
                XCTAssertTrue(event.flags.contains(.maskNumericPad))
                XCTAssertTrue(event.flags.contains(.maskAlphaShift))
                XCTAssertTrue(event.flags.contains(.maskNonCoalesced))
                XCTAssertEqual(
                    event.getIntegerValueField(.eventSourceStateID),
                    originalStateID
                )
            }
        }
    }

    func testNativeShiftSelectionDoesNotNormalizeOtherShortcuts() {
        let source = CGEventSource(stateID: .privateState)!
        let cases = [
            KeyboardStroke(
                keyCode: MacKeyCode.rightArrow,
                modifiers: [.control, .shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.rightArrow,
                modifiers: [.command, .shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.home,
                modifiers: [.shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.rightShift,
                phase: .flagsChanged,
                modifiers: [.shift]
            ),
        ]

        for stroke in cases {
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(stroke.keyCode),
                keyDown: stroke.phase != .up
            )!
            event.flags = [.maskSecondaryFn, .maskShift]

            XCTAssertFalse(
                CGEventTapController.normalizeNativeShiftSelectionEvent(
                    event,
                    stroke: stroke
                )
            )
            XCTAssertTrue(event.flags.contains(.maskSecondaryFn))
        }
    }

    func testOneToOneRewriteKeepsSourceAndExactSelectionModifiers() {
        let source = CGEventSource(stateID: .privateState)!
        let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(MacKeyCode.leftArrow),
            keyDown: true
        )!
        event.flags = [
            .maskAlphaShift,
            .maskControl,
            .maskNumericPad,
            .maskSecondaryFn,
            .maskShift,
        ]
        let sourceStateID = event.getIntegerValueField(.eventSourceStateID)
        XCTAssertEqual(
            CGEventTapController.keyboardStroke(
                from: event,
                type: .keyDown
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.leftArrow,
                modifiers: [.control, .shift]
            ),
            "SecondaryFn and NumericPad describe the navigation key shape, "
                + "not extra shortcut modifiers"
        )
        let decision = KeyboardMappingEngine().evaluate(
            KeyboardStroke(
                keyCode: MacKeyCode.leftArrow,
                modifiers: [.control, .shift]
            ),
            context: MappingContext(isTextInput: true)
        )
        guard case let .replace(replacements) = decision.action,
              let replacement = replacements.first else {
            return XCTFail("Expected Ctrl+Shift+Left to be replaced")
        }

        XCTAssertTrue(
            CGEventTapController.rewrite(
                event,
                ofType: .keyDown,
                with: replacement
            )
        )
        XCTAssertEqual(
            CGEventTapController.keyboardStroke(
                from: event,
                type: .keyDown
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.leftArrow,
                modifiers: [.option, .shift]
            )
        )
        XCTAssertTrue(event.flags.contains(.maskAlphaShift))
        XCTAssertTrue(event.flags.contains(.maskNumericPad))
        XCTAssertTrue(event.flags.contains(.maskSecondaryFn))
        XCTAssertFalse(event.flags.contains(.maskControl))
        XCTAssertFalse(event.flags.contains(.maskCommand))
        XCTAssertEqual(
            event.getIntegerValueField(.eventSourceStateID),
            sourceStateID
        )
        XCTAssertEqual(
            event.getIntegerValueField(.eventSourceUserData),
            CGEventTapController.syntheticEventMarker
        )

        let differentKey = KeyboardStroke(
            keyCode: MacKeyCode.home,
            modifiers: [.command]
        )
        XCTAssertFalse(
            CGEventTapController.rewrite(
                event,
                ofType: .keyDown,
                with: differentKey
            )
        )
        XCTAssertEqual(
            event.getIntegerValueField(.keyboardEventKeycode),
            Int64(MacKeyCode.leftArrow)
        )
    }

    func testSyntheticBatchUsesOriginalSourceAndFailsAtomically() {
        let originalSource = CGEventSource(stateID: .privateState)!
        let original = CGEvent(
            keyboardEventSource: originalSource,
            virtualKey: CGKeyCode(MacKeyCode.c),
            keyDown: true
        )!
        original.flags = [.maskAlphaShift, .maskControl]
        original.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        let factory = SyntheticKeyboardEventFactory()
        let strokes = [
            KeyboardStroke(
                keyCode: MacKeyCode.c,
                modifiers: [.command, .shift]
            ),
            KeyboardStroke(
                keyCode: MacKeyCode.c,
                phase: .up,
                modifiers: [.command, .shift]
            ),
        ]

        let events = factory.events(
            for: strokes,
            preservingAutoRepeatFrom: original
        )
        XCTAssertEqual(events?.count, 2)
        let originalSourceStateID = original.getIntegerValueField(
            .eventSourceStateID
        )
        for (event, phase) in zip(events ?? [], [KeyPhase.down, .up]) {
            XCTAssertEqual(
                event.getIntegerValueField(.eventSourceStateID),
                originalSourceStateID
            )
            XCTAssertEqual(
                CGEventTapController.keyboardStroke(
                    from: event,
                    type: phase == .down ? .keyDown : .keyUp
                ),
                KeyboardStroke(
                    keyCode: MacKeyCode.c,
                    phase: phase,
                    modifiers: [.command, .shift]
                )
            )
            XCTAssertTrue(event.flags.contains(.maskAlphaShift))
            XCTAssertFalse(event.flags.contains(.maskControl))
            XCTAssertEqual(
                event.getIntegerValueField(.keyboardEventAutorepeat),
                1
            )
        }

        let unavailableFactory = SyntheticKeyboardEventFactory(
            sourceProvider: { _ in nil }
        )
        XCTAssertNil(
            unavailableFactory.events(
                for: strokes,
                preservingAutoRepeatFrom: original
            )
        )
    }

    func testChangedKeySyntheticEventUsesTargetShapeAndAmbientCapsLock() {
        let source = CGEventSource(stateID: .privateState)!
        let original = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(MacKeyCode.home),
            keyDown: true
        )!
        original.flags = [
            .maskAlphaShift,
            .maskControl,
            .maskSecondaryFn,
            .maskShift,
        ]
        let replacement = KeyboardStroke(
            keyCode: MacKeyCode.leftArrow,
            modifiers: [.command]
        )

        let event = SyntheticKeyboardEventFactory().events(
            for: [replacement],
            preservingAutoRepeatFrom: original
        )?.first

        XCTAssertEqual(
            event.flatMap {
                CGEventTapController.keyboardStroke(
                    from: $0,
                    type: .keyDown
                )
            },
            replacement
        )
        XCTAssertTrue(event?.flags.contains(.maskAlphaShift) == true)
        XCTAssertTrue(event?.flags.contains(.maskNumericPad) == true)
        XCTAssertTrue(event?.flags.contains(.maskSecondaryFn) == true)
        XCTAssertFalse(event?.flags.contains(.maskControl) == true)
        XCTAssertFalse(event?.flags.contains(.maskShift) == true)
    }

    func testReplacementTransactionUsesCommittedKeyUpMapping() {
        var transactions = KeyboardReplacementTransactionStore()
        let physicalDown = KeyboardStroke(
            keyCode: MacKeyCode.leftArrow,
            modifiers: [.control, .shift]
        )
        transactions.commit(
            physicalStroke: physicalDown,
            replacements: [
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    modifiers: [.option, .shift]
                ),
            ]
        )

        XCTAssertEqual(
            transactions.autoRepeatReplacements(for: physicalDown),
            [
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    modifiers: [.option, .shift]
                ),
            ]
        )
        XCTAssertEqual(
            transactions.keyUpReplacements(
                for: KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    phase: .up
                )
            ),
            [
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    phase: .up,
                    modifiers: [.option, .shift]
                ),
            ]
        )
        XCTAssertNotNil(
            transactions.keyUpReplacements(
                for: KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    phase: .up
                )
            )
        )
        transactions.complete(
            physicalStroke: KeyboardStroke(
                keyCode: MacKeyCode.leftArrow,
                phase: .up
            )
        )
        XCTAssertNil(
            transactions.keyUpReplacements(
                for: KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    phase: .up
                )
            )
        )
    }

    func testChangedKeyHomeTransactionKeepsDownRepeatAndUpMapping() {
        var transactions = KeyboardReplacementTransactionStore()
        let physicalDown = KeyboardStroke(keyCode: MacKeyCode.home)
        let replacementDown = KeyboardStroke(
            keyCode: MacKeyCode.leftArrow,
            modifiers: [.command]
        )
        transactions.commit(
            physicalStroke: physicalDown,
            replacements: [replacementDown]
        )

        XCTAssertEqual(
            transactions.autoRepeatReplacements(for: physicalDown),
            [replacementDown]
        )
        let physicalUp = KeyboardStroke(
            keyCode: MacKeyCode.home,
            phase: .up,
            modifiers: [.shift]
        )
        XCTAssertEqual(
            transactions.keyUpReplacements(for: physicalUp),
            [
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    phase: .up,
                    modifiers: [.command]
                ),
            ]
        )
        transactions.complete(physicalStroke: physicalUp)
        XCTAssertNil(transactions.keyUpReplacements(for: physicalUp))
    }

    func testReplacementTransactionsReleaseTargetsBeforeStop() {
        var transactions = KeyboardReplacementTransactionStore()
        let physicalDown = KeyboardStroke(keyCode: MacKeyCode.home)
        transactions.commit(
            physicalStroke: physicalDown,
            replacements: [
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    modifiers: [.command]
                ),
            ]
        )

        let releases = transactions.releaseAll()

        XCTAssertEqual(
            releases,
            [
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    phase: .up,
                    modifiers: [.command]
                ),
            ]
        )
        XCTAssertNil(
            transactions.autoRepeatReplacements(for: physicalDown)
        )
        XCTAssertNil(
            transactions.keyUpReplacements(
                for: KeyboardStroke(
                    keyCode: MacKeyCode.home,
                    phase: .up
                )
            )
        )

        let events = CGEventTapController.emergencyReleaseEvents(
            for: releases
        )
        XCTAssertEqual(events?.count, 1)
        guard let event = events?.first else {
            return XCTFail("Expected a complete emergency release batch")
        }
        XCTAssertEqual(
            CGEventTapController.keyboardStroke(
                from: event,
                type: .keyUp
            ),
            releases[0]
        )
        XCTAssertEqual(
            event.getIntegerValueField(.eventSourceStateID),
            Int64(CGEventSourceStateID.combinedSessionState.rawValue)
        )
        XCTAssertEqual(
            event.getIntegerValueField(.eventSourceUserData),
            CGEventTapController.syntheticEventMarker
        )
    }

    func testEmergencyReleaseCompletesOnlyAfterAFullBatchPublishes() {
        var transactions = KeyboardReplacementTransactionStore()
        let physicalDown = KeyboardStroke(keyCode: MacKeyCode.home)
        transactions.commit(
            physicalStroke: physicalDown,
            replacements: [
                KeyboardStroke(
                    keyCode: MacKeyCode.leftArrow,
                    modifiers: [.command]
                ),
                KeyboardStroke(
                    keyCode: MacKeyCode.upArrow,
                    modifiers: [.command]
                ),
            ]
        )
        let physicalUp = KeyboardStroke(
            keyCode: MacKeyCode.home,
            phase: .up
        )
        let releases = transactions.keyUpReplacements(for: physicalUp)!
        var published: [Int] = []

        XCTAssertFalse(
            KeyboardEmergencyRelease.perform(
                strokes: releases,
                makeEvents: { _ in [1] },
                publish: { published = $0 },
                complete: {
                    transactions.complete(physicalStroke: physicalUp)
                }
            )
        )
        XCTAssertTrue(published.isEmpty)
        XCTAssertNotNil(transactions.keyUpReplacements(for: physicalUp))

        XCTAssertTrue(
            KeyboardEmergencyRelease.perform(
                strokes: releases,
                makeEvents: { _ in [1, 2] },
                publish: { published = $0 },
                complete: {
                    transactions.complete(physicalStroke: physicalUp)
                }
            )
        )
        XCTAssertEqual(published, [1, 2])
        XCTAssertNil(transactions.keyUpReplacements(for: physicalUp))
    }

    func testComposedFlagsRetainIntentionalFunctionModifier() {
        let flags = CGEventTapController.composedFlags(
            targetShape: [],
            ambient: [],
            modifiers: [.function]
        )

        XCTAssertTrue(flags.contains(.maskSecondaryFn))
    }

    #if DEBUG
    func testHomeEndDiagnosticsPersistOnlyKeyCodeAndRuleIdentifier() {
        let suiteName = "app.windsify.tests.keyboard-focus-diagnostics."
            + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: KeyboardFocusDiagnostics.enabledDefaultsKey)
        defaults.set(
            [
                "frontmostBundleIdentifier": "com.example.private",
                "focusedProcessIdentifier": 123,
                "ancestry": [["role": "AXTextField"]],
            ],
            forKey: KeyboardFocusDiagnostics.snapshotDefaultsKey
        )

        KeyboardFocusDiagnostics.recordIfEnabled(
            stroke: KeyboardStroke(
                keyCode: MacKeyCode.home,
                modifiers: [.control, .shift]
            ),
            decision: RuleDecision(
                ruleID: "editing.control-home",
                action: .suppress
            ),
            defaults: defaults
        )

        let snapshot = defaults.dictionary(
            forKey: KeyboardFocusDiagnostics.snapshotDefaultsKey
        )
        XCTAssertEqual(
            Set(snapshot?.keys.map { $0 } ?? []),
            Set(["keyCode", "ruleID"])
        )
        XCTAssertEqual(snapshot?["keyCode"] as? Int, Int(MacKeyCode.home))
        XCTAssertEqual(
            snapshot?["ruleID"] as? String,
            "editing.control-home"
        )
    }

    func testHomeEndDiagnosticsRequireExplicitOptInAndRelevantKey() {
        let suiteName = "app.windsify.tests.keyboard-focus-diagnostics."
            + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let decision = RuleDecision(
            ruleID: "editing.home",
            action: .suppress
        )

        KeyboardFocusDiagnostics.recordIfEnabled(
            stroke: KeyboardStroke(keyCode: MacKeyCode.home),
            decision: decision,
            defaults: defaults
        )
        XCTAssertNil(
            defaults.object(
                forKey: KeyboardFocusDiagnostics.snapshotDefaultsKey
            )
        )

        defaults.set(true, forKey: KeyboardFocusDiagnostics.enabledDefaultsKey)
        KeyboardFocusDiagnostics.recordIfEnabled(
            stroke: KeyboardStroke(keyCode: MacKeyCode.a),
            decision: decision,
            defaults: defaults
        )
        XCTAssertNil(
            defaults.object(
                forKey: KeyboardFocusDiagnostics.snapshotDefaultsKey
            )
        )
    }
    #endif

    func testFocusResolverUsesKeyboardFocusApplicationForSystemPanel() {
        let focusedElements = [
            "open-save-panel-service": "new-folder-name-field",
            "frontmost-app": "background-control",
        ]

        let resolution = AccessibilityFocusResolver.resolve(
            systemWideElement: "system-wide",
            focusedElement: { focusedElements[$0] },
            focusedApplication: { element in
                element == "system-wide"
                    ? "open-save-panel-service"
                    : nil
            },
            frontmostApplication: { "frontmost-app" }
        )

        XCTAssertEqual(resolution?.element, "new-folder-name-field")
        XCTAssertEqual(resolution?.source, .keyboardFocusApplication)
    }

    func testFocusResolverFallsBackToSystemThenFrontmostElement() {
        XCTAssertEqual(
            AccessibilityFocusResolver.resolve(
                systemWideElement: "system-wide",
                focusedElement: { element in
                    element == "system-wide" ? "direct-focus" : nil
                },
                focusedApplication: { _ in nil },
                frontmostApplication: { "frontmost-app" }
            )?.element,
            "direct-focus"
        )

        XCTAssertEqual(
            AccessibilityFocusResolver.resolve(
                systemWideElement: "system-wide",
                focusedElement: { element in
                    element == "frontmost-app" ? "fallback-focus" : nil
                },
                focusedApplication: { _ in nil },
                frontmostApplication: { "frontmost-app" }
            )?.element,
            "fallback-focus"
        )
    }

    func testTextInputFocusResolverFindsEditableAncestor() {
        let parents = [
            "internal-field-child": "text-field",
            "text-field": "dialog",
        ]

        XCTAssertTrue(
            AccessibilityTextInputFocusResolver.isTextInput(
                startingAt: "internal-field-child",
                classifiesAsTextInput: { $0 == "text-field" },
                parent: { parents[$0] }
            )
        )
        XCTAssertFalse(
            AccessibilityTextInputFocusResolver.isTextInput(
                startingAt: "button-child",
                classifiesAsTextInput: { $0 == "text-field" },
                parent: { parents[$0] }
            )
        )
    }

    func testTextCaretResolverUsesCharacterCountWithoutTextContent() {
        XCTAssertEqual(
            AccessibilityTextCaretResolver.location(
                forRuleID: "editing.home",
                characterCount: 18
            ),
            0
        )
        XCTAssertEqual(
            AccessibilityTextCaretResolver.location(
                forRuleID: "editing.end",
                characterCount: 18
            ),
            18
        )
        XCTAssertEqual(
            AccessibilityTextCaretResolver.location(
                forRuleID: "editing.control-end",
                characterCount: 18
            ),
            18
        )
        XCTAssertNil(
            AccessibilityTextCaretResolver.location(
                forRuleID: "editing.shift-end",
                characterCount: 18
            )
        )
        XCTAssertNil(
            AccessibilityTextCaretResolver.location(
                forRuleID: "editing.end",
                characterCount: -1
            )
        )
    }

    func testTextInputClassifierRecognizesNativeAndWebEditors() {
        XCTAssertTrue(
            TextInputAccessibilityClassifier.isTextInput(
                role: "AXTextArea",
                subrole: nil,
                isEditable: false,
                valueIsSettable: false,
                selectedTextRangeIsSettable: false
            )
        )
        XCTAssertTrue(
            TextInputAccessibilityClassifier.isTextInput(
                role: "AXGroup",
                subrole: nil,
                isEditable: true,
                valueIsSettable: false,
                selectedTextRangeIsSettable: false
            )
        )
        XCTAssertTrue(
            TextInputAccessibilityClassifier.isTextInput(
                role: "AXWebArea",
                subrole: nil,
                isEditable: false,
                valueIsSettable: true,
                selectedTextRangeIsSettable: false
            )
        )
        XCTAssertTrue(
            TextInputAccessibilityClassifier.isTextInput(
                role: "AXGroup",
                subrole: nil,
                isEditable: false,
                valueIsSettable: false,
                selectedTextRangeIsSettable: true
            )
        )
    }

    func testTextInputClassifierRejectsNonTextControls() {
        XCTAssertFalse(
            TextInputAccessibilityClassifier.isTextInput(
                role: "AXSlider",
                subrole: nil,
                isEditable: false,
                valueIsSettable: true,
                selectedTextRangeIsSettable: false
            )
        )
        XCTAssertFalse(
            TextInputAccessibilityClassifier.isTextInput(
                role: "AXButton",
                subrole: nil,
                isEditable: false,
                valueIsSettable: false,
                selectedTextRangeIsSettable: false
            )
        )
    }

    func testWindowsKeyTapOpensOnlyForModifierOnlyTap() {
        var tracker = WindowsKeyTapTracker()
        XCTAssertFalse(
            tracker.observe(
                KeyboardStroke(
                    keyCode: MacKeyCode.leftCommand,
                    phase: .flagsChanged,
                    modifiers: [.command]
                )
            )
        )
        XCTAssertTrue(
            tracker.observe(
                KeyboardStroke(
                    keyCode: MacKeyCode.leftCommand,
                    phase: .flagsChanged
                )
            )
        )

        XCTAssertFalse(
            tracker.observe(
                KeyboardStroke(
                    keyCode: MacKeyCode.leftCommand,
                    phase: .flagsChanged,
                    modifiers: [.command]
                )
            )
        )
        XCTAssertFalse(
            tracker.observe(
                KeyboardStroke(
                    keyCode: MacKeyCode.e,
                    modifiers: [.command]
                )
            )
        )
        XCTAssertFalse(
            tracker.observe(
                KeyboardStroke(
                    keyCode: MacKeyCode.leftCommand,
                    phase: .flagsChanged
                )
            )
        )
    }

    func testSystemDefinedMediaKeysDecodeToFunctionKeys() {
        let cases: [(Int, UInt16)] = [
            (Int(NX_KEYTYPE_BRIGHTNESS_DOWN), MacKeyCode.f1),
            (Int(NX_KEYTYPE_BRIGHTNESS_UP), MacKeyCode.f2),
            (32, MacKeyCode.f3),
            (Int(NX_KEYTYPE_LAUNCH_PANEL), MacKeyCode.f4),
            (33, MacKeyCode.f4),
            (Int(NX_KEYTYPE_ILLUMINATION_DOWN), MacKeyCode.f5),
            (Int(NX_KEYTYPE_ILLUMINATION_UP), MacKeyCode.f6),
            (Int(NX_KEYTYPE_PREVIOUS), MacKeyCode.f7),
            (Int(NX_KEYTYPE_PLAY), MacKeyCode.f8),
            (Int(NX_KEYTYPE_NEXT), MacKeyCode.f9),
            (Int(NX_KEYTYPE_MUTE), MacKeyCode.f10),
            (Int(NX_KEYTYPE_SOUND_DOWN), MacKeyCode.f11),
            (Int(NX_KEYTYPE_SOUND_UP), MacKeyCode.f12),
        ]

        for (auxiliaryKeyType, keyCode) in cases {
            let downData = (auxiliaryKeyType << 16) | (0xA << 8)
            XCTAssertEqual(
                SystemDefinedKeyDecoder.decode(
                    data1: downData,
                    modifiers: [.option]
                ),
                KeyboardStroke(
                    keyCode: keyCode,
                    modifiers: [.option]
                )
            )

            let upData = (auxiliaryKeyType << 16) | (0xB << 8)
            XCTAssertEqual(
                SystemDefinedKeyDecoder.decode(
                    data1: upData,
                    modifiers: []
                ),
                KeyboardStroke(
                    keyCode: keyCode,
                    phase: .up
                )
            )
        }
    }

    func testUnknownSystemDefinedKeyFailsOpen() {
        XCTAssertNil(
            SystemDefinedKeyDecoder.decode(
                data1: (999 << 16) | (0xA << 8),
                modifiers: []
            )
        )
    }
}
