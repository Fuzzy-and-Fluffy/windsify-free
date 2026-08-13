import SwiftUI

struct FreeSettingsView: View {
    @ObservedObject var appState: FreeAppState

    var body: some View {
        Form {
            Section("Windows keyboard essentials") {
                Toggle(
                    "Enable Windows keyboard shortcuts",
                    isOn: Binding(
                        get: { appState.keyboardTranslationEnabled },
                        set: {
                            appState.setKeyboardTranslationEnabled($0)
                        }
                    )
                )

                LabeledContent("Keyboard engine") {
                    Text(engineStatus)
                }

                if appState.accessibilityStatus == .notGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Accessibility permission is required.",
                            systemImage: "hand.raised.fill"
                        )
                        Button("Open Accessibility Settings") {
                            appState.requestAccessibilityAccess()
                        }
                    }
                }

                if appState.keyboardIsBlockedByConflicts {
                    Label(
                        "Keyboard translation is paused by a conflicting "
                            + "remapper.",
                        systemImage: "exclamationmark.octagon.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Included shortcuts") {
                shortcut("Ctrl+C / X / V / Z", "Copy, cut, paste, undo")
                shortcut("Ctrl+Y", "Redo")
                shortcut("Home / End", "Start or end of the line")
                shortcut("Ctrl+Arrow", "Move by word or paragraph")
                shortcut("Alt+Tab", "Switch applications")
                shortcut("Alt+F4", "Close the active window")
                shortcut("Win+Space", "Switch input source")

                Text(
                    "Ctrl+Space, Ctrl+Tab, Terminal Ctrl shortcuts, remote "
                        + "desktop input, secure input, and Shift+Arrow "
                        + "selection remain native."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !appState.relevantConflicts.isEmpty {
                Section("Compatibility") {
                    ForEach(appState.relevantConflicts) { conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflict.title).font(.headline)
                            Text(conflict.message)
                            Text(conflict.recommendation)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }

                    Button("Refresh compatibility status") {
                        appState.refresh()
                    }
                }
            }

            Section("General") {
                Toggle(
                    "Launch Windsify at login",
                    isOn: Binding(
                        get: { appState.launchAtLoginEnabled },
                        set: { appState.setLaunchAtLoginEnabled($0) }
                    )
                )

                Link(
                    "Learn about Windsify Pro",
                    destination: URL(string: "https://windsify.com")!
                )
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 620, minHeight: 540)
        .onAppear {
            appState.activate()
        }
        .alert(
            "Windsify Free",
            isPresented: Binding(
                get: { appState.lastErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.clearError()
                    }
                }
            )
        ) {
            Button("OK") {
                appState.clearError()
            }
        } message: {
            Text(appState.lastErrorMessage ?? "Unknown error")
        }
    }

    private var engineStatus: String {
        if appState.keyboardEngineIsRunning {
            return "Running"
        }
        if appState.keyboardIsBlockedByConflicts {
            return "Paused by conflict"
        }
        if appState.accessibilityStatus == .notGranted {
            return "Waiting for permission"
        }
        return "Stopped"
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        LabeledContent(keys) {
            Text(action).foregroundStyle(.secondary)
        }
    }
}
