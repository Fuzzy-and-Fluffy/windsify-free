import Foundation
import IOKit.hid

/// Reads advertised key mappings, not input events. This adds no keyboard
/// monitor, system remapping, background history, or permission request.
enum FunctionRowMetadata {
    static func summary(for device: IOHIDDevice) -> String? {
        let service = IOHIDDeviceGetService(device)
        guard service != 0 else { return nil }
        var maps: [String] = []
        for key in ["FnFunctionUsageMap", "FnKeyboardUsageMap"] {
            guard let value = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively)
            ) as? String,
                  let summary = sanitizedSummary(value), !maps.contains(summary) else { continue }
            maps.append(summary)
        }
        return maps.isEmpty ? nil : maps.joined(separator: "; ")
    }

    /// Driver generations use either 16+16 or 32+32 page/usage packing.
    /// Export only numeric F1–F12 pairs; arbitrary property text is discarded.
    static func sanitizedSummary(_ value: String) -> String? {
        guard value.utf8.count <= 8192 else { return nil }
        let tokens = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !tokens.isEmpty, tokens.count.isMultiple(of: 2), tokens.count <= 128 else { return nil }
        var pairs: [String] = []
        for index in stride(from: 0, to: tokens.count, by: 2) {
            guard let source = unpack(tokens[index]), let target = unpack(tokens[index + 1]) else { return nil }
            guard source.page == 7, (0x3A...0x45).contains(source.usage) else { continue }
            pairs.append(String(format: "F%d=HID 0x%04X:0x%04X", source.usage - 0x39, target.page, target.usage))
            if pairs.count == 12 { break }
        }
        return pairs.isEmpty ? nil : pairs.joined(separator: ", ")
    }

    private static func unpack(_ token: String) -> (page: UInt32, usage: UInt32)? {
        guard token.lowercased().hasPrefix("0x"), let number = UInt64(token.dropFirst(2), radix: 16) else { return nil }
        let page = number > UInt32.max ? number >> 32 : number >> 16
        let usage = number > UInt32.max ? number & 0xFFFF_FFFF : number & 0xFFFF
        guard page <= 0xFFFF, usage <= 0xFFFF else { return nil }
        return (UInt32(page), UInt32(usage))
    }
}
