import AppKit
import SwiftUI

private enum FreeWindowID {
    static let settings = "free-settings"
}

extension Notification.Name {
    static let windsifyFreeOpenSettingsRequested = Notification.Name(
        "app.windsify.mac.free-open-settings-requested"
    )
}

final class WindsifyFreeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        sender.activate(ignoringOtherApps: true)
        if !flag {
            NotificationCenter.default.post(
                name: .windsifyFreeOpenSettingsRequested,
                object: nil
            )
        }
        return true
    }
}

@main
struct WindsifyFreeApp: App {
    @NSApplicationDelegateAdaptor(WindsifyFreeAppDelegate.self)
    private var appDelegate
    @StateObject private var appState = FreeAppState()

    var body: some Scene {
        Window("Windsify Free", id: FreeWindowID.settings) {
            FreeSettingsView(appState: appState)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    appState.refresh()
                }
        }
        .defaultSize(width: 680, height: 620)

        MenuBarExtra {
            FreeMenuBarView(appState: appState)
        } label: {
            Image(systemName: "keyboard.fill")
                .accessibilityLabel("Windsify Free")
        }
    }
}

private struct FreeMenuBarView: View {
    @ObservedObject var appState: FreeAppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(
            "Windows keyboard shortcuts",
            isOn: Binding(
                get: { appState.keyboardTranslationEnabled },
                set: { appState.setKeyboardTranslationEnabled($0) }
            )
        )

        Divider()

        Button("Settings…") {
            openSettings()
        }

        Button("Refresh Status") {
            appState.refresh()
        }

        Divider()

        Button("Quit Windsify Free") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onReceive(
            NotificationCenter.default.publisher(
                for: .windsifyFreeOpenSettingsRequested
            )
        ) { _ in
            openSettings()
        }

        Text(AppVersionPresentation(bundle: .main).freeAppText)
            .foregroundStyle(.secondary)
            .disabled(true)
    }

    private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: FreeWindowID.settings)
    }
}
