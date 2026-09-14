import ApplicationServices
import Foundation

enum EditorAccessibilityFocus {
    static func resolve(processIdentifier: pid_t) -> EditorInputContext {
        guard processIdentifier > 0 else { return .unknown }
        let application = AXUIElementCreateApplication(processIdentifier)
        let deadline = ProcessInfo.processInfo.systemUptime + EditorFocusTraversal.queryBudget
        guard AXUIElementSetMessagingTimeout(application, EditorFocusTraversal.messageTimeout) == .success else { return .unknown }
        func element(_ raw: CFTypeRef?) -> AXUIElement? {
            guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }
        func focusedElement() -> AXUIElement? {
            var raw: CFTypeRef?
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
                  ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            return element(raw)
        }
        guard let focused = focusedElement() else { return .unknown }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused, &pid) == .success, pid == processIdentifier else { return .unknown }
        return EditorFocusTraversal.resolve(focused: focused, deadline: deadline,
                                            now: { ProcessInfo.processInfo.systemUptime }, read: { current in
            var values: CFArray?
            let attributes = [kAXRoleAttribute, "AXDOMClassList", kAXParentAttribute] as CFArray
            guard AXUIElementCopyMultipleAttributeValues(current, attributes, [], &values) == .success,
                  ProcessInfo.processInfo.systemUptime < deadline,
                  let metadata = values as? [Any], metadata.count == 3,
                  let role = metadata[0] as? String else { return nil }
            // The web-area root itself need not expose a DOM class list.
            guard let classes = metadata[1] as? [String] ?? (role == "AXWebArea" ? [] : nil) else { return nil }
            let parent = element(metadata[2] as CFTypeRef)
            return (.init(role: role, classes: Set(classes)), parent.flatMap { CFEqual($0, current) ? nil : $0 })
        }, focusUnchanged: {
            guard let latest = focusedElement() else { return false }
            return CFEqual(latest, focused)
        })
    }
}
