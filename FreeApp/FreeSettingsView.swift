import SwiftUI

struct FreeSettingsView: View {
    @ObservedObject var appState: FreeAppState
    @State private var showsShortcutHelp = false

    var body: some View {
        Form {
            LanguageSettingsSection()
            Section("Windows keyboard essentials") {
                VSCodeCompatibilityView()
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
                    Text(L10n.text(engineStatus))
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
                        "Keyboard translation is paused by a conflicting remapper.",
                        systemImage: "exclamationmark.octagon.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Included shortcuts") {
                Button("Shortcut Help…") { showsShortcutHelp = true }
                shortcut("Ctrl+C / X / V / Z", "Copy, cut, paste, undo")
                shortcut("Ctrl+Y", "Redo")
                shortcut("Home / End", "Start or end of the line")
                shortcut("Ctrl+Arrow", "Move by word or paragraph")
                shortcut("Alt+Tab", "Switch applications")
                shortcut("Alt+F4", "Close the active window")
                shortcut("Win+Space", "Switch input source")
                shortcut("Application / Menu", "Open contextual menu")

                Text(
                    "Ctrl+Space, Ctrl+Tab, Terminal Ctrl shortcuts, remote desktop input, secure input, and Shift+Arrow selection remain native."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !appState.relevantConflicts.isEmpty {
                Section("Compatibility") {
                    ForEach(appState.relevantConflicts) { conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text(conflict.title)).font(.headline)
                            Text(conflict.localizedMessage)
                            Text(L10n.text(conflict.recommendation))
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

            Section {
                Text(AppVersionPresentation(bundle: .main).freeAppText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 620, minHeight: 540)
        .onAppear {
            appState.activate()
        }
        .onChange(of: appState.keyboardEngineIsRunning) { _, _ in appState.shortcutSupport.refresh() }
        .onChange(of: appState.accessibilityStatus) { _, _ in appState.shortcutSupport.refresh() }
        .sheet(isPresented: $showsShortcutHelp) {
            VStack(alignment: .trailing) {
                Button("Done") { showsShortcutHelp = false }.padding(.trailing, 16)
                ShortcutSupportView(model: appState.shortcutSupport,
                                    enableKeyboard: { appState.setKeyboardTranslationEnabled(true); appState.shortcutSupport.refresh() },
                                    openAccessibility: { appState.requestAccessibilityAccess() })
            }
            .padding(.top, 16)
            .frame(width: 600, height: 580)
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
            Text(L10n.message(appState.lastErrorMessage ?? "Unknown error"))
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
            Text(L10n.text(action)).foregroundStyle(.secondary)
        }
    }
}
