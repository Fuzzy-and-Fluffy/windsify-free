import AppKit
import ApplicationServices

/// A bounded, fresh focus query. No cached terminal state can leak into the
/// next pane/window. AX errors, missing metadata and timeouts preserve Control.
enum VSCodeAccessibilityFocus {
    static func resolve(processIdentifier: pid_t) -> VSCodeInputContext {
        let application = AXUIElementCreateApplication(processIdentifier)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.025
        // Set a per-application messaging timeout; also bound total traversal.
        guard AXUIElementSetMessagingTimeout(application, 0.008) == .success else { return .unknown }

        func read(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success,
                  ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            return result
        }
        func element(_ raw: CFTypeRef?) -> AXUIElement? {
            guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }

        guard let focused = element(read(application, kAXFocusedUIElementAttribute)) else { return .unknown }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success,
              focusedPID == processIdentifier else { return .unknown }
        var current = focused
        var path: [VSCodeFocusClassifier.Node] = []
        for _ in 0..<5 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return .unknown }
            var rawMetadata: CFArray?
            let attributes = [kAXRoleAttribute, "AXDOMClassList", kAXParentAttribute] as CFArray
            guard AXUIElementCopyMultipleAttributeValues(current, attributes, [], &rawMetadata) == .success,
                  ProcessInfo.processInfo.systemUptime < deadline,
                  let metadata = rawMetadata as? [Any], metadata.count == 3,
                  let role = metadata[0] as? String,
                  let classes = metadata[1] as? [String] else { return .unknown }
            path.append(.init(role: role, classes: Set(classes)))
            let classification = VSCodeFocusClassifier.classify(path)
            if classification != .unknown {
                // Reject a focus switch during the query, even within one window.
                guard let latest = element(read(application, kAXFocusedUIElementAttribute)),
                      CFEqual(latest, focused) else { return .unknown }
                return classification
            }
            guard let parent = element(metadata[2] as CFTypeRef),
                  !CFEqual(parent, current) else { return .unknown }
            current = parent
        }
        return .unknown
    }
}
