import AppKit
import XCTest
@testable import WindsifyMac

@MainActor
final class InputRuntimeSafetyTests: XCTestCase {
    func testDetectsEveryTestHostSignalWithoutDisablingOrdinaryDebugUse() {
        XCTAssertFalse(InputRuntimeSafety.isTestHost(environment: [:], xctestLoaded: false))
        XCTAssertFalse(InputRuntimeSafety.isTestHost(environment: ["CONFIGURATION": "Debug"], xctestLoaded: false))
        XCTAssertTrue(InputRuntimeSafety.isTestHost(environment: [:], xctestLoaded: true))
        for key in ["WINDSIFY_UNIT_TEST_HOST", "XCTestConfigurationFilePath", "XCTestBundlePath", "XCInjectBundleInto"] {
            XCTAssertTrue(InputRuntimeSafety.isTestHost(environment: [key: "1"], xctestLoaded: false))
            XCTAssertTrue(InputRuntimeSafety.isTestHost(environment: [key: ""], xctestLoaded: false))
        }
    }

    func testHostedSuiteCannotReachAnInteractiveInputOperation() {
        XCTAssertTrue(InputRuntimeSafety.isTestHost)
        var reachedInputOperation = false
        XCTAssertThrowsError(try {
            try InputRuntimeSafety.requireInteractiveInput()
            // A harmless sentinel, never a real system keyboard operation.
            reachedInputOperation = true
        }()) { error in
            XCTAssertEqual(error as? InputRuntimeSafety.Failure, .unitTestHostCannotControlInput)
        }
        XCTAssertFalse(reachedInputOperation)
    }

    func testRealKeyboardAndHIDEntryPointsRejectTheTestHost() {
        let keyboard = CGEventTapController()
        let menu = ApplicationMenuKeyController()
        XCTAssertThrowsError(try keyboard.start()) { error in
            XCTAssertEqual(error as? InputRuntimeSafety.Failure, .unitTestHostCannotControlInput)
        }
        XCTAssertFalse(keyboard.isRunning)
        XCTAssertThrowsError(try menu.start()) { error in
            XCTAssertEqual(error as? InputRuntimeSafety.Failure, .unitTestHostCannotControlInput)
        }
    }

    func testHostedProcessOwnsNoSystemEventTaps() throws {
        // Reads only the WindowServer tap registry, never keyboard events.
        // Query a generous fixed capacity and reject truncated snapshots.
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: 256)
        var count: UInt32 = 0
        let status = taps.withUnsafeMutableBufferPointer { buffer in
            CGGetEventTapList(UInt32(buffer.count), buffer.baseAddress, &count)
        }
        XCTAssertEqual(status, .success)
        guard status == .success, count <= taps.count else {
            XCTFail("Could not read a complete system event-tap registry")
            return
        }
        let owned = taps.prefix(Int(count)).filter { $0.tappingProcess == ProcessInfo.processInfo.processIdentifier }
        XCTAssertTrue(owned.isEmpty, "Hosted XCTest must own no global event taps")
    }
}
