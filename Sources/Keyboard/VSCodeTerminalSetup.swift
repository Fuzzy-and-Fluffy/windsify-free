import Foundation

/// Explicit, reversible setup for VS Code's default user profile. The editor
/// owns selection state; Windsify never reads selected terminal text.
enum VSCodeTerminalSetup {
    static let begin = "\n// BEGIN WINDSIFY WINDOWS TERMINAL\n"
    static let end = "\n// END WINDSIFY WINDOWS TERMINAL\n"
    static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Code/User/keybindings.json")

    private static let versionOneBindings = """
    { "key": "ctrl+c", "command": "workbench.action.terminal.copyAndClearSelection", "when": "terminalFocus && terminalTextSelected" },
    { "key": "ctrl+c", "command": "workbench.action.terminal.sendSequence", "when": "terminalFocus && !terminalTextSelected", "args": { "text": "\\u0003" } },
    { "key": "ctrl+v", "command": "workbench.action.terminal.paste", "when": "terminalFocus" },
    { "key": "ctrl+shift+c", "command": "workbench.action.terminal.copySelection", "when": "terminalFocus && terminalTextSelected" },
    { "key": "ctrl+shift+c", "command": "", "when": "terminalFocus && !terminalTextSelected" },
    { "key": "ctrl+shift+v", "command": "workbench.action.terminal.paste", "when": "terminalFocus" },
    { "key": "ctrl+insert", "command": "workbench.action.terminal.copySelection", "when": "terminalFocus && terminalTextSelected" },
    { "key": "shift+insert", "command": "workbench.action.terminal.paste", "when": "terminalFocus" },
    { "key": "cmd+c", "command": "workbench.action.terminal.copySelection", "when": "terminalFocus && terminalTextSelected" },
    { "key": "cmd+c", "command": "", "when": "terminalFocus && !terminalTextSelected" },
    { "key": "cmd+v", "command": "workbench.action.terminal.paste", "when": "terminalFocus" }
    """

    // Match VS Code's native clipboard conditions, including the focused
    // terminal's scoped selection key (important while a process is running).
    static let bindings = versionOneBindings
        .replacingOccurrences(of: "\"terminalFocus && terminalTextSelected\"",
                              with: "\"(terminalFocus && terminalTextSelected) || terminalTextSelectedInFocused\"")
        .replacingOccurrences(of: "\"terminalFocus && !terminalTextSelected\"",
                              with: "\"terminalFocus && !terminalTextSelected && !terminalTextSelectedInFocused\"")

    enum SetupError: LocalizedError {
        case invalid, modifiedBlock, profileMissing, concurrentEdit
        var errorDescription: String? {
            switch self {
            case .invalid: return "VS Code keybindings must be a valid JSONC array. No changes were made."
            case .modifiedBlock: return "The Windsify settings block was edited. Review it in VS Code before changing setup."
            case .profileMissing: return "Open the default VS Code profile once before setting up terminal shortcuts."
            case .concurrentEdit: return "VS Code keybindings changed during setup. Please try again."
            }
        }
    }

    private static func parse(_ text: String) throws -> [Any] {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]),
              let array = value as? [Any], array.allSatisfy({ $0 is [String: Any] }) else {
            throw SetupError.invalid
        }
        return array
    }

    static func removingBlock(from text: String) throws -> String {
        _ = try parse(text)
        guard let start = text.range(of: begin) else {
            if text.contains(end) { throw SetupError.modifiedBlock }
            return text
        }
        guard let finish = text.range(of: end, range: start.upperBound..<text.endIndex),
              text.ranges(of: begin).count == 1, text.ranges(of: end).count == 1 else {
            throw SetupError.modifiedBlock
        }
        let block = String(text[start.upperBound..<finish.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard [bindings, ",\n" + bindings, versionOneBindings, ",\n" + versionOneBindings].contains(block) else { throw SetupError.modifiedBlock }
        var result = text
        result.removeSubrange(start.lowerBound..<finish.upperBound)
        _ = try parse(result) // Do not corrupt separators after a user edit.
        return result
    }

    static func configuring(_ text: String) throws -> String {
        let original = try removingBlock(from: text)
        let values = try parse(original)
        // Tokenize only enough to locate the root array close and its preceding
        // token. Preserve comments, formatting, strings and unrelated bindings.
        let chars = Array(original)
        var index = 0, depth = 0
        var quote: Character?, lineComment = false, blockComment = false, escaped = false
        var previous: Character?, closing: Int?, beforeClose: Character?
        while index < chars.count {
            let c = chars[index], next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            if lineComment { if c == "\n" || c == "\r" { lineComment = false }; index += 1; continue }
            if blockComment {
                if c == "*" && next == "/" { blockComment = false; index += 2 } else { index += 1 }
                continue
            }
            if let q = quote {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == q { quote = nil }
                index += 1; continue
            }
            if c == "/" && next == "/" { lineComment = true; index += 2; continue }
            if c == "/" && next == "*" { blockComment = true; index += 2; continue }
            if c == "\"" || c == "'" { quote = c }
            if c == "[" || c == "{" { depth += 1 }
            if c == "]" || c == "}" {
                depth -= 1
                if depth == 0 && c == "]" { closing = index; beforeClose = previous; break }
            }
            if !c.isWhitespace { previous = c }
            index += 1
        }
        guard let closing else { throw SetupError.invalid }
        let separator = !values.isEmpty && beforeClose != "," ? ",\n" : ""
        let output = String(chars[..<closing]) + begin + separator + bindings + end + String(chars[closing...])
        _ = try parse(output)
        return output
    }

    @discardableResult
    static func apply(to file: URL = defaultFile, enabled: Bool, backupDirectory: URL? = nil) throws -> URL? {
        let manager = FileManager.default
        let file = file.resolvingSymlinksInPath()
        guard manager.fileExists(atPath: file.deletingLastPathComponent().path) else { throw SetupError.profileMissing }
        let existed = manager.fileExists(atPath: file.path)
        let data = existed ? try Data(contentsOf: file) : Data("[\n]\n".utf8)
        guard let original = String(data: data, encoding: .utf8) else { throw SetupError.invalid }
        let updated = try enabled ? configuring(original) : removingBlock(from: original)
        guard updated != original else { return nil }
        let backups = backupDirectory ?? manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Windsify Mac/VS Code Backups")
        try manager.createDirectory(at: backups, withIntermediateDirectories: true)
        let backup = backups.appendingPathComponent("keybindings-\(UUID().uuidString).json")
        try data.write(to: backup, options: .atomic)
        // Preserve edits made by Settings Sync or a concurrent editor save.
        guard manager.fileExists(atPath: file.path) == existed,
              try (!existed || Data(contentsOf: file) == data) else { throw SetupError.concurrentEdit }
        let output = Data(updated.utf8)
        try output.write(to: file, options: .atomic)
        guard try Data(contentsOf: file) == output else { throw SetupError.concurrentEdit }
        return backup
    }
}
