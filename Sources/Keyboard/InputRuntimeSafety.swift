import Foundation

enum InputRuntimeSafety {
    enum Failure: Error, Equatable {
        case unitTestHostCannotControlInput
    }

    static func isTestHost(environment: [String: String], xctestLoaded: Bool) -> Bool {
        xctestLoaded || ["WINDSIFY_UNIT_TEST_HOST", "XCTestConfigurationFilePath",
                        "XCTestBundlePath", "XCInjectBundleInto"].contains {
            environment[$0] != nil
        }
    }

    static var isTestHost: Bool {
        isTestHost(environment: ProcessInfo.processInfo.environment,
                   xctestLoaded: NSClassFromString("XCTestCase") != nil)
    }

    /// Call before checking system permissions or installing any real input
    /// listener. Policy tests use injected fakes, never the user's keyboard.
    static func requireInteractiveInput() throws {
        guard !isTestHost else { throw Failure.unitTestHostCannotControlInput }
    }
}
