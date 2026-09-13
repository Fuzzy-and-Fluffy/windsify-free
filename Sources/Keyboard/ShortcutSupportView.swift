import SwiftUI

struct ShortcutSupportView: View {
    @ObservedObject var model: ShortcutSupportModel
    let enableKeyboard: () -> Void
    let openAccessibility: () -> Void
    @State private var showsReport = false
    @State private var showsReportDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Shortcut help", systemImage: "keyboard.badge.ellipsis")
                    .font(.title2.bold())
                Text("Press a shortcut once. Windsify will check what your Mac receives and explain what to do next.")
                    .foregroundStyle(.secondary)
                Picker("What would you like to check?", selection: $model.kind) {
                    ForEach(ShortcutTestKind.allCases) { kind in Text(L10n.text(kind.rawValue)).tag(kind) }
                }
                .disabled(model.isListening)

                VStack(alignment: .leading, spacing: 12) {
                    if model.isListening {
                        Label("Press your shortcut now…", systemImage: "hand.tap")
                            .font(.headline)
                        Text("Keep this window active. The test stops after one shortcut or 10 seconds.")
                        Button("Cancel test") { model.cancel() }
                    } else {
                        Button(L10n.text(model.result == nil ? "Test shortcut" : "Test again")) { model.start() }
                            .buttonStyle(.borderedProminent)
                        Text("Safe preview: Windsify won't run the shortcut. macOS may still handle reserved system keys. Only this test's key details are collected, not typed text.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                if let result = model.result {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.text(result.title), systemImage: result.outcome == "mapping-recognized-preview-only" ? "checkmark.circle" : "info.circle")
                            .font(.headline)
                        Text(L10n.text(result.explanation)).fixedSize(horizontal: false, vertical: true)
                        if let received = result.receivedShortcut {
                            LabeledContent("Your Mac received", value: L10n.text(received)).font(.callout)
                        }
                        if let output = result.output, result.outcome == "mapping-recognized-preview-only" {
                            LabeledContent("Windsify would send", value: L10n.message(output)).font(.callout)
                        }
                    }
                } else if let explanation = model.status.explanation {
                    Text(L10n.text(explanation)).fixedSize(horizontal: false, vertical: true)
                }

                if !model.status.accessibilityGranted {
                    Button("Open Accessibility Settings", action: openAccessibility)
                } else if !model.status.keyboardEnabled {
                    Button("Turn on Windows shortcuts", action: enableKeyboard)
                }

                Divider()
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Still need help?").font(.headline)
                        Text("Your app version, keyboard information and test result are filled in for you. You can review everything before sending.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Send feedback…") {
                        model.prepareFeedback()
                        showsReportDetails = false
                        showsReport = true
                    }
                    .disabled(model.isListening)
                }
            }
            .padding(16)
        }
        .onAppear { model.show() }
        .onDisappear { model.hide() }
        .sheet(isPresented: $showsReport) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Send to Windsify Support").font(.title2.bold())
                Text("We'll open an email draft to hello@windsify.com with this report. Nothing is sent until you send the email.")
                Text("Already included: Windsify and macOS versions, keyboard information, service status and your test result. No typing history or personal documents.")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("View report details", isExpanded: $showsReportDetails) {
                    ScrollView {
                        Text(model.report).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12).frame(height: 210)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                if let message = model.feedbackMessage { Text(L10n.text(message)).font(.caption) }
                HStack {
                    Button("Done") { showsReport = false }
                    Spacer()
                    Button("Copy report") { model.copyReport() }
                    Button("Open email draft") { model.openEmail() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(24).frame(width: 580)
        }
    }
}
