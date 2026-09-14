import Foundation

/// Shared by the live AX adapter and traversal regression tests.
enum EditorFocusTraversal {
    // Claude's observed composer has 25 ancestors including its web root.
    // A cold AX lookup took 35–40 ms; keep headroom without an unbounded query.
    static let maximumDepth = 64
    static let queryBudget: TimeInterval = 0.075
    static let messageTimeout: Float = 0.050

    static func resolve<Element>(
        focused: Element,
        deadline: TimeInterval,
        now: () -> TimeInterval,
        read: (Element) -> (EditorFocusClassifier.Node, Element?)?,
        focusUnchanged: () -> Bool
    ) -> EditorInputContext {
        var current = focused
        var path: [EditorFocusClassifier.Node] = []
        for _ in 0..<maximumDepth {
            guard now() < deadline, let (node, parent) = read(current), now() < deadline else { return .unknown }
            path.append(node)
            let result = EditorFocusClassifier.classify(path)
            if result != .unknown {
                return focusUnchanged() && now() < deadline ? result : .unknown
            }
            guard let parent else { return .unknown }
            current = parent
        }
        return .unknown
    }
}

/// Shared pane detection contains no tier-specific mappings or terminal text.
enum EditorFocusClassifier {
    struct Node: Equatable {
        let role: String
        let classes: Set<String>
    }

    /// Only the focused DOM ancestry is inspected. Never read message text,
    /// terminal contents, clipboard contents, or selection values.
    static func classify(_ path: [Node]) -> EditorInputContext {
        guard let leaf = path.first else { return .unknown }
        let hasTerminalContainer = path.contains { $0.classes.contains("xterm") }
        let hasTerminalInput = path.contains { $0.classes.contains("xterm-helper-textarea") }
        if !hasTerminalInput, ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(leaf.role) {
            if !leaf.classes.isDisjoint(with: ["native-edit-context", "inputarea"]),
               path.dropFirst().contains(where: { $0.classes.contains("monaco-editor") }) {
                return .textInput
            }
            if leaf.classes.contains("input"),
               path.dropFirst().contains(where: { $0.classes.contains("monaco-inputbox") }) {
                return .textInput
            }
        }
        if hasTerminalContainer || hasTerminalInput {
            // A terminal Find box, toolbar or a partial path must not receive
            // shell clipboard rules. Require both the actual input and owner.
            return hasTerminalContainer && leaf.classes.contains("xterm-helper-textarea") &&
                ["AXTextArea", "AXTextField"].contains(leaf.role) ? .terminal : .unknown
        }
        // Do not assume a partially read text-area path is a chat composer:
        // xterm's terminal container might still be above it.
        guard path.last?.role == "AXWebArea",
              ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox",
               "AXStaticText", "AXGroup", "AXWebArea", "AXLink", "AXButton"].contains(leaf.role) else {
            return .unknown
        }
        return .textInput
    }
}
