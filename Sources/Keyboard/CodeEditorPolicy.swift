import Foundation

enum EditorInputContext: String, Equatable, Sendable {
    case unknown, textInput, terminal
}

/// Exact application identities, not window titles or user text. Unlisted apps
/// retain the ordinary policy; new identities require an explicit addition.
enum CodeEditorPolicy {
    static let bundleIdentifiers: Set<String> = [
        "com.microsoft.vscode", "com.microsoft.vscodeinsiders",
        "com.visualstudio.code.oss", "com.vscodium", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "dev.zed.zed", "dev.zed.zed-preview",
        "com.openai.codex", "com.anthropic.claudefordesktop",
        "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce", "com.jetbrains.webstorm", "com.jetbrains.goland",
        "com.jetbrains.rider", "com.jetbrains.clion", "com.jetbrains.rubymine",
        "com.jetbrains.phpstorm", "com.jetbrains.datagrip", "com.apple.dt.xcode"
    ]
    static func contains(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { bundleIdentifiers.contains($0.lowercased()) } ?? false
    }
    static func context(bundleIdentifier: String?, focus: EditorInputContext) -> MappingContext {
        MappingContext(bundleIdentifier: bundleIdentifier, isTextInput: focus == .textInput,
                       isEmbeddedTerminal: focus == .terminal, editorInputContext: focus)
    }

    static func isMainView(_ context: MappingContext) -> Bool {
        !context.isEmbeddedTerminal && context.editorInputContext != .terminal &&
            (context.isTextInput || context.editorInputContext == .textInput)
    }

    static func resolveContext(_ bundleIdentifier: String?, processIdentifier: Int32) -> MappingContext? {
        guard contains(bundleIdentifier) else { return nil }
        return context(bundleIdentifier: bundleIdentifier,
                       focus: EditorAccessibilityFocus.resolve(processIdentifier: processIdentifier))
    }
}
