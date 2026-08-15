import AppKit
import ApplicationServices
import Foundation
import IOKit.hid
import IOKit.hidsystem

enum ApplicationMenuKeyControllerError: Error, LocalizedError {
    case inputMonitoringPermissionMissing
    case managerOpenFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .inputMonitoringPermissionMissing:
            return "Input Monitoring permission is required for the Windows Menu key."
        case let .managerOpenFailed(result):
            return "The Windows Menu key listener could not start (IOKit \(result))."
        }
    }
}

/// Filters the one USB HID usage that macOS does not expose as a CGEvent.
/// Keeping this predicate separate makes the privacy boundary independently
/// testable: letters, modifiers, and every other HID usage are ignored.
enum ApplicationMenuKeyHIDFilter {
    static func matches(
        usagePage: UInt32,
        usage: UInt32
    ) -> Bool {
        usagePage == UInt32(kHIDPage_KeyboardOrKeypad)
            && usage == UInt32(kHIDUsage_KeyboardApplication)
    }
}

/// Arms on physical key-down and fires once on key-up. Opening an AX context
/// menu while the hardware key is still held lets the subsequent release
/// dismiss the menu immediately in Finder and text controls.
struct ApplicationMenuKeyPressTracker {
    private(set) var isPressed = false

    mutating func observe(integerValue: CFIndex) -> Bool {
        guard integerValue == 0 else {
            isPressed = true
            return false
        }

        guard isPressed else {
            return false
        }
        isPressed = false
        return true
    }
}

/// Finds the closest Accessibility element that can show a contextual menu.
/// Selected rows or children take priority over their containing table so a
/// Finder selection behaves like the Windows Application/Menu key.
enum AccessibilityContextMenuTargetResolver {
    static func resolve<Element>(
        startingAt focusedElement: Element,
        maximumAncestorDepth: Int = 4,
        selectedElements: (Element) -> [Element],
        parent: (Element) -> Element?,
        supportsShowMenu: (Element) -> Bool
    ) -> Element? {
        var current: Element? = focusedElement
        var depth = 0

        while let candidate = current,
              depth <= maximumAncestorDepth {
            if let selected = selectedElements(candidate).first(
                where: supportsShowMenu
            ) {
                return selected
            }
            if supportsShowMenu(candidate) {
                return candidate
            }
            current = parent(candidate)
            depth += 1
        }
        return nil
    }
}

enum AccessibilityContextMenuController {
    static func showForFocusedElement() -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard let resolution = AccessibilityFocusResolver.resolve(
            systemWideElement: systemWideElement,
            focusedElement: focusedElement,
            focusedApplication: focusedApplication,
            frontmostApplication: frontmostApplication
        ) else {
            return false
        }

        guard let target = AccessibilityContextMenuTargetResolver.resolve(
            startingAt: resolution.element,
            selectedElements: selectedElements,
            parent: parent,
            supportsShowMenu: supportsShowMenu
        ) else {
            return false
        }

        return AXUIElementPerformAction(
            target,
            kAXShowMenuAction as CFString
        ) == .success
    }

    private static func focusedElement(
        of element: AXUIElement
    ) -> AXUIElement? {
        elementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            of: element
        )
    }

    private static func focusedApplication(
        of element: AXUIElement
    ) -> AXUIElement? {
        elementAttribute(
            kAXFocusedApplicationAttribute as CFString,
            of: element
        )
    }

    private static func frontmostApplication() -> AXUIElement? {
        guard let processIdentifier = NSWorkspace.shared
            .frontmostApplication?
            .processIdentifier else {
            return nil
        }
        return AXUIElementCreateApplication(processIdentifier)
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXParentAttribute as CFString, of: element)
    }

    private static func selectedElements(
        of element: AXUIElement
    ) -> [AXUIElement] {
        for attribute in [
            kAXSelectedRowsAttribute as CFString,
            kAXSelectedChildrenAttribute as CFString,
        ] {
            var rawValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                attribute,
                &rawValue
            ) == .success,
                  let values = rawValue as? [AXUIElement],
                  !values.isEmpty else {
                continue
            }
            return values
        }
        return []
    }

    private static func supportsShowMenu(
        _ element: AXUIElement
    ) -> Bool {
        var rawActions: CFArray?
        guard AXUIElementCopyActionNames(
            element,
            &rawActions
        ) == .success,
              let actions = rawActions as? [String] else {
            return false
        }
        return actions.contains(kAXShowMenuAction)
    }

    private static func elementAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> AXUIElement? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &rawValue
        ) == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (rawValue as! AXUIElement)
    }
}

/// Observes only USB HID Keyboard Application (usage page 0x07, usage 0x65).
/// macOS does not convert that key into a CGEvent, so this narrow listener is
/// complementary to—rather than a second owner of—the normal event-tap rules.
final class ApplicationMenuKeyController {
    typealias ShowMenuHandler = () -> Bool

    private let showMenu: ShowMenuHandler
    private var manager: IOHIDManager?
    private var pressTracker = ApplicationMenuKeyPressTracker()

    var isRunning: Bool {
        manager != nil
    }

    init(
        showMenu: @escaping ShowMenuHandler =
            AccessibilityContextMenuController.showForFocusedElement
    ) {
        self.showMenu = showMenu
    }

    deinit {
        stop()
    }

    func start() throws {
        guard manager == nil else {
            return
        }

        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeUnknown {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            == kIOHIDAccessTypeGranted else {
            throw ApplicationMenuKeyControllerError
                .inputMonitoringPermissionMissing
        }

        let nextManager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        let keyboardDeviceMatching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String:
                Int(kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey as String:
                Int(kHIDUsage_GD_Keyboard),
        ]
        let applicationKeyMatching: [String: Any] = [
            kIOHIDElementUsagePageKey as String:
                Int(kHIDPage_KeyboardOrKeypad),
            kIOHIDElementUsageKey as String:
                Int(kHIDUsage_KeyboardApplication),
        ]

        IOHIDManagerSetDeviceMatching(
            nextManager,
            keyboardDeviceMatching as CFDictionary
        )
        IOHIDManagerSetInputValueMatching(
            nextManager,
            applicationKeyMatching as CFDictionary
        )
        IOHIDManagerRegisterInputValueCallback(
            nextManager,
            Self.inputValueCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(
            nextManager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(
            nextManager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                nextManager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            throw ApplicationMenuKeyControllerError
                .managerOpenFailed(result)
        }
        manager = nextManager
    }

    func stop() {
        guard let manager else {
            return
        }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        self.manager = nil
        pressTracker = ApplicationMenuKeyPressTracker()
    }

    private func receive(
        usagePage: UInt32,
        usage: UInt32,
        integerValue: CFIndex
    ) {
        guard ApplicationMenuKeyHIDFilter.matches(
            usagePage: usagePage,
            usage: usage
        ),
              pressTracker.observe(integerValue: integerValue) else {
            return
        }
        _ = showMenu()
    }

    private static let inputValueCallback: IOHIDValueCallback = {
        context,
        _,
        _,
        value in
        guard let context else {
            return
        }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)
        let controller = Unmanaged<ApplicationMenuKeyController>
            .fromOpaque(context)
            .takeUnretainedValue()

        DispatchQueue.main.async { [weak controller] in
            controller?.receive(
                usagePage: usagePage,
                usage: usage,
                integerValue: integerValue
            )
        }
    }
}
