import SwiftUI

struct VSCodeCompatibilityView: View {
    @AppStorage(VSCodeKeyboardPolicy.nativeShortcutsPreference) private var nativeShortcuts = false
    @State private var setupMessage = ""

    var body: some View {
        Toggle(L10n.text("Use native keyboard shortcuts in VS Code"), isOn: $nativeShortcuts)
        Text(L10n.text(nativeShortcuts
            ? "Windsify leaves VS Code keyboard shortcuts unchanged."
            : "VS Code: Windows shortcuts in the editor; terminal Control keys are handled by VS Code."))
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(L10n.text("Set up Windows terminal shortcuts: Ctrl+C copies and clears a selection, or interrupts when nothing is selected. Ctrl+V pastes. Ctrl+Shift+C/V also work."))
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(L10n.text("Setup adds a removable block to the default VS Code profile and backs up the original file. It overrides older terminal copy/paste bindings while installed, including Cmd+C/V. These VS Code bindings remain active when Windsify is off."))
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack {
            Button(L10n.text("Set up VS Code terminal")) { configure(enabled: true) }
            Button(L10n.text("Remove terminal setup")) { configure(enabled: false) }
        }
        if !setupMessage.isEmpty { Text(setupMessage).font(.caption) }
    }

    private func configure(enabled: Bool) {
        do {
            try VSCodeTerminalSetup.apply(enabled: enabled)
            setupMessage = L10n.text(enabled ? "VS Code terminal shortcuts are installed. Reload the VS Code window to apply them." : "Terminal setup was removed. Reload the VS Code window to apply the change.")
        } catch { setupMessage = L10n.text(error.localizedDescription) }
    }
}
