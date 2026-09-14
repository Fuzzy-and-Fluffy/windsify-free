import Foundation

enum VSCodeInputContext: String, Equatable, Sendable {
    case unknown
    case textInput
    case terminal
}

/// Uses structural metadata, never localized labels or input contents. Only
/// the focused element and its ancestors count: a visible sibling terminal
/// must not turn an editor or a terminal Find box into shell input.
enum VSCodeFocusClassifier {
    struct Node: Equatable {
        var role: String
        var classes: Set<String>
    }

    static func supports(bundleIdentifier: String?) -> Bool {
        bundleIdentifier?.lowercased() == "com.microsoft.vscode"
    }

    static func classify(_ path: [Node]) -> VSCodeInputContext {
        guard let leaf = path.first,
              ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(leaf.role) else {
            return .unknown
        }
        if leaf.classes.contains("xterm-helper-textarea") {
            return path.dropFirst().contains { $0.classes.contains("xterm") }
                ? .terminal : .unknown
        }
        if !leaf.classes.isDisjoint(with: ["native-edit-context", "inputarea"]),
           path.dropFirst().contains(where: { $0.classes.contains("monaco-editor") }) {
            return .textInput
        }
        if leaf.classes.contains("input"),
           path.dropFirst().contains(where: { $0.classes.contains("monaco-inputbox") }) {
            return .textInput
        }
        return .unknown
    }
}

enum VSCodeKeyboardPolicy {
    static let nativeShortcutsPreference = "vscodeNativeShortcuts"

    static func decision(for stroke: KeyboardStroke, context: MappingContext) -> RuleDecision? {
        guard VSCodeFocusClassifier.supports(bundleIdentifier: context.bundleIdentifier),
              stroke.modifiers.contains(.control) else { return nil }
        switch context.vscodeInputContext {
        case .unknown:
            return RuleDecision(ruleID: "vscode.unknown-control", action: .passThrough)
        case .textInput:
            return nil
        case .terminal:
            // VS Code's terminalTextSelected condition owns copy vs interrupt.
            // Preserve physical Control so its bindings see the original chord.
            return RuleDecision(ruleID: "vscode.terminal-control", action: .passThrough)
        }
    }
}
