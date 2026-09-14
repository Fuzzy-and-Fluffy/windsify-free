import Foundation
import CryptoKit

/// Removes only the exact, known 1.4.2 Windsify block. It never installs Pro
/// rules or examines terminal input. Edited blocks require user review.
enum VSCodeLegacyCleanup {
    static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Code/User/keybindings.json")
    static let begin = "\n// BEGIN WINDSIFY WINDOWS TERMINAL\n"
    static let end = "\n// END WINDSIFY WINDOWS TERMINAL\n"
    static let knownHashes: Set<String> = ["07e9297a689631da6e1bd0dcf6ca99d53d93b1f94f8ab8fac4747a9fe28bac3f", "30777aed36b18230b19f543942e9c2b0a721380bdc82e1cef8cc948910c1b549", "76fa2e56ea8310daa6d1b3909154fa0905a8dc05e4a786ceca9d28bb6024992e", "5980acdd4df9028c2faaf415e286214cdefdb81a191483cbaa38936bf8e43960"]
    enum CleanupError: LocalizedError {
        case edited, invalid, changed
        var errorDescription: String? {
            switch self {
            case .edited: return "The old Windsify VS Code block was edited. Review it manually; no configuration was changed."
            case .invalid: return "VS Code keybindings are invalid. No configuration was changed."
            case .changed: return "VS Code keybindings changed during cleanup. Please try again."
            }
        }
    }
    static func removingLegacyBlock(from text: String) throws -> String {
        guard text.contains(begin) || text.contains(end) else { return text }
        guard text.ranges(of: begin).count == 1, text.ranges(of: end).count == 1,
              let start = text.range(of: begin),
              let finish = text.range(of: end, range: start.upperBound..<text.endIndex) else { throw CleanupError.edited }
        let body = text[start.upperBound..<finish.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
        guard knownHashes.contains(hash) else { throw CleanupError.edited }
        var output = text; output.removeSubrange(start.lowerBound..<finish.upperBound)
        for value in [text, output] {
            guard let data = value.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [Any],
                  array.allSatisfy({ $0 is [String: Any] }) else { throw CleanupError.invalid }
        }
        return output
    }
    @discardableResult
    static func remove(to file: URL = defaultFile, backupDirectory: URL? = nil) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let data = try Data(contentsOf: file)
        guard let original = String(data: data, encoding: .utf8) else { throw CleanupError.invalid }
        let output = try removingLegacyBlock(from: original)
        guard output != original else { return false }
        let folder = backupDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Windsify Mac/VS Code Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("legacy-keybindings-\(UUID().uuidString).json"), options: .atomic)
        guard try Data(contentsOf: file) == data else { throw CleanupError.changed }
        try Data(output.utf8).write(to: file, options: .atomic)
        guard try Data(contentsOf: file) == Data(output.utf8) else { throw CleanupError.changed }
        return true
    }
}
