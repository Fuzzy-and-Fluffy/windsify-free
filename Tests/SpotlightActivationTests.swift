import AppKit
import XCTest
@testable import WindsifyMac

final class SpotlightActivationTests: XCTestCase {
    private func entry(enabled: Any = true, keyCode: Any = 49,
                       flags: Any = CGEventFlags.maskCommand.rawValue,
                       type: String = "standard") -> [String: Any] {
        ["64": ["enabled": enabled,
                "value": ["type": type, "parameters": [32, keyCode, flags]]]]
    }

    func testEnabledConfiguredShortcutKeepsExactKeyAndModifiers() {
        let flags = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
        XCTAssertEqual(SpotlightShortcutPolicy.configuredShortcut(
            from: entry(keyCode: MacKeyCode.f4, flags: flags)),
            KeyboardStroke(keyCode: MacKeyCode.f4, modifiers: [.control, .option]))
        XCTAssertEqual(SpotlightShortcutPolicy.configuredShortcut(from: entry()),
                       KeyboardStroke(keyCode: MacKeyCode.space, modifiers: [.command]))
    }

    func testDisabledMissingOrUnreadableNeverInventsCommandSpace() {
        for preferences: Any? in [nil, [:] as [String: Any], "unreadable", entry(enabled: false),
                                 ["60": entry()["64"]!]] {
            XCTAssertNil(SpotlightShortcutPolicy.configuredShortcut(from: preferences))
        }
    }

    func testInvalidShortcutEvidenceRefusesInput() {
        let fixtures: [Any] = [
            entry(enabled: 2), entry(keyCode: 65535), entry(keyCode: -1),
            entry(keyCode: 49.5), entry(keyCode: true), entry(keyCode: "49"),
            entry(keyCode: MacKeyCode.leftCommand), entry(flags: -1),
            entry(flags: CGEventFlags.maskAlphaShift.rawValue), entry(flags: true),
            entry(type: "SAE1.0"),
            ["64": ["enabled": true, "value": ["type": "standard", "parameters": [32, 49]]]],
        ]
        for fixture in fixtures {
            XCTAssertNil(SpotlightShortcutPolicy.configuredShortcut(from: fixture))
        }
    }

    func testReadAdapterRefusesBeforeCopyWhenRefreshFailsOrInTestHost() {
        var synchronizations = 0
        XCTAssertNil(SystemSpotlightActivation.readConfiguredShortcut(isTestHost: { false }, synchronize: {
            synchronizations += 1
            return false
        }, read: { XCTFail("Failed refresh must not use cached preferences"); return self.entry() }))
        XCTAssertEqual(synchronizations, 1)
        XCTAssertNil(SystemSpotlightActivation.readConfiguredShortcut(isTestHost: { true }, synchronize: {
            XCTFail("Test host must refuse before synchronizing system preferences")
            return true
        }, read: { XCTFail("Test host must refuse before reading system preferences"); return self.entry() }))
    }

    func testEveryActivationRefreshesBeforeCopyAndObservesChangedShortcut() {
        var preferences: Any? = entry(enabled: false)
        var operations: [String] = []
        var publishedKeys: [Int64] = []
        var failures: [SystemSpotlightActivation.Failure] = []
        let activation = SystemSpotlightActivation(isTestHost: { false }, shortcutProvider: {
            SystemSpotlightActivation.readConfiguredShortcut(isTestHost: { false }, synchronize: {
                operations.append("refresh")
                return true
            }, read: { operations.append("copy"); return preferences })
        }, publish: { events in
            publishedKeys.append(events[0].getIntegerValueField(.keyboardEventKeycode))
        }, reportFailure: { failures.append($0) })
        XCTAssertEqual(activation.activate(), .shortcutUnavailable)
        preferences = entry(keyCode: MacKeyCode.space, flags: CGEventFlags.maskAlternate.rawValue)
        XCTAssertEqual(activation.activate(), .actionRequested)
        preferences = entry(keyCode: MacKeyCode.f4, flags: CGEventFlags.maskControl.rawValue)
        XCTAssertEqual(activation.activate(), .actionRequested)
        XCTAssertEqual(operations, ["refresh", "copy", "refresh", "copy", "refresh", "copy"])
        XCTAssertEqual(publishedKeys, [Int64(MacKeyCode.space), Int64(MacKeyCode.f4)])
        XCTAssertEqual(failures, [.shortcutUnavailable])
    }

    func testConfiguredShortcutBuildsOnlyMarkedDownUpWithExactFlags() throws {
        let strokes = [KeyPhase.down, .up].map {
            KeyboardStroke(keyCode: MacKeyCode.space, phase: $0, modifiers: [.option])
        }
        let events = try XCTUnwrap(SystemSpotlightActivation.events(for: strokes))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(MacKeyCode.space))
            XCTAssertEqual(event.flags, .maskAlternate)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),
                           CGEventTapController.syntheticEventMarker)
        }
    }

    func testEnabledShortcutPublishesOneConfiguredPairAndReportsOnlyActionRequested() {
        var publishedCount = 0
        let activation = SystemSpotlightActivation(
            isTestHost: { false },
            shortcutProvider: { KeyboardStroke(keyCode: MacKeyCode.space, modifiers: [.option]) },
            publish: { events in
                publishedCount += 1
                XCTAssertEqual(events.count, 2)
            },
            reportFailure: { _ in XCTFail("Configured shortcut must not report failure") })
        XCTAssertEqual(activation.activate(), .actionRequested)
        XCTAssertEqual(publishedCount, 1)
    }

    func testMissingDisabledInvalidAndInputSourceOnlyPreferencesReportSetupWithoutInput() {
        for preferences: Any? in [nil, entry(enabled: false), entry(keyCode: 65535),
                                 ["60": entry()["64"]!]] {
            var failures: [SystemSpotlightActivation.Failure] = []
            let activation = SystemSpotlightActivation(
                isTestHost: { false },
                shortcutProvider: { SpotlightShortcutPolicy.configuredShortcut(from: preferences) },
                eventBuilder: { _ in XCTFail("Missing shortcut must not synthesize events"); return nil },
                publish: { _ in XCTFail("Missing shortcut must not publish guessed input") },
                reportFailure: { failures.append($0) })
            XCTAssertEqual(activation.activate(), .shortcutUnavailable)
            XCTAssertEqual(activation.activate(), .shortcutUnavailable)
            XCTAssertEqual(failures, [.shortcutUnavailable])
        }
    }

    func testFailedEmptyAndPartialEventPairsNeverPublishAndReportOnce() throws {
        let singleEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil,
                                               virtualKey: MacKeyCode.space, keyDown: true))
        for events: [CGEvent]? in [nil, [], [singleEvent]] {
            var failures: [SystemSpotlightActivation.Failure] = []
            let activation = SystemSpotlightActivation(
                isTestHost: { false },
                shortcutProvider: { KeyboardStroke(keyCode: MacKeyCode.space, modifiers: [.option]) },
                eventBuilder: { strokes in
                    XCTAssertEqual(strokes, [
                        KeyboardStroke(keyCode: MacKeyCode.space, phase: .down, modifiers: [.option]),
                        KeyboardStroke(keyCode: MacKeyCode.space, phase: .up, modifiers: [.option])])
                    return events
                }, publish: { _ in XCTFail("Incomplete activation input must never be posted") },
                reportFailure: { failures.append($0) })
            XCTAssertEqual(activation.activate(), .eventCreationFailed)
            XCTAssertEqual(activation.activate(), .eventCreationFailed)
            XCTAssertEqual(failures, [.eventCreationFailed])
        }
    }

    func testFailuresStaySuppressedUntilConfiguredPairIsPublishedAndPreferencesAreReadAgain() {
        var shortcut: KeyboardStroke?
        var buildFails = true
        var failures: [SystemSpotlightActivation.Failure] = []
        var preferenceReads = 0
        var publications = 0
        let activation = SystemSpotlightActivation(
            isTestHost: { false }, shortcutProvider: { preferenceReads += 1; return shortcut },
            eventBuilder: { buildFails ? nil : SystemSpotlightActivation.events(for: $0) },
            publish: { events in publications += 1; XCTAssertEqual(events.count, 2) },
            reportFailure: { failures.append($0) })
        XCTAssertEqual(activation.activate(), .shortcutUnavailable)
        XCTAssertEqual(activation.activate(), .shortcutUnavailable)
        shortcut = KeyboardStroke(keyCode: MacKeyCode.space, modifiers: [.option])
        XCTAssertEqual(activation.activate(), .eventCreationFailed)
        XCTAssertEqual(failures, [.shortcutUnavailable])
        buildFails = false
        XCTAssertEqual(activation.activate(), .actionRequested)
        XCTAssertEqual(publications, 1)
        buildFails = true
        XCTAssertEqual(activation.activate(), .eventCreationFailed)
        XCTAssertEqual(activation.activate(), .eventCreationFailed)
        XCTAssertEqual(failures, [.shortcutUnavailable, .eventCreationFailed])
        buildFails = false
        XCTAssertEqual(activation.activate(), .actionRequested)
        shortcut = nil
        XCTAssertEqual(activation.activate(), .shortcutUnavailable)
        XCTAssertEqual(failures, [.shortcutUnavailable, .eventCreationFailed, .shortcutUnavailable])
        XCTAssertEqual(publications, 2)
        XCTAssertEqual(preferenceReads, 8)
    }

    func testTestHostRefusesBeforeReadingPreferencesOrTouchingSystem() {
        let activation = SystemSpotlightActivation(
            isTestHost: { true },
            shortcutProvider: { XCTFail("Test host must not read live shortcut preferences"); return nil },
            eventBuilder: { _ in XCTFail("Test host must not build activation input"); return nil },
            publish: { _ in XCTFail("Test host must not post activation input") },
            reportFailure: { _ in XCTFail("Test host must not present an alert") })
        XCTAssertEqual(activation.activate(), .testHost)
        // Exercise the production guard too. The hosted test environment must
        // return before reaching any real input, application, or alert adapter.
        XCTAssertTrue(InputRuntimeSafety.isTestHost)
        XCTAssertEqual(SystemSpotlightActivation.shared.activate(), .testHost)
    }
}
