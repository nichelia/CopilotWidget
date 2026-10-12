import AppKit
import SwiftUI

struct TokenSettingsView: View {
    @ObservedObject var manager: CopilotManager
    @State private var token = ""
    @State private var saveError: String?
    @FocusState private var tokenFieldFocused: Bool

    var body: some View {
        Form {
            Section {
                Text("Run `gh auth token | pbcopy`, then choose Import from Clipboard — the token never appears on screen. Or paste one below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("GitHub token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .focused($tokenFieldFocused)
                    .onSubmit(saveToken)
            } header: {
                Text("GitHub Token")
            }

            Section {
                if let error = saveError ?? manager.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let data = manager.data {
                    Label("Connected · \(data.usageSummaryLine)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if manager.hasToken {
                    Label("Token saved in your Keychain", systemImage: "key.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Save Token") {
                    saveToken()
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Import from Clipboard") {
                    saveError = nil
                    manager.importTokenFromClipboard()
                }

                Button("Clear Stored Token", role: .destructive) {
                    clearToken()
                }
                .disabled(!manager.hasToken)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 330)
        .padding()
        .onAppear { tokenFieldFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            // Drop back to accessory once nothing is on screen, so the Dock icon
            // raised for the Settings window does not linger.
            DispatchQueue.main.async {
                let stillVisible = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
                if !stillVisible { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    private func saveToken() {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try manager.saveToken(token)
            token = ""
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clearToken() {
        do {
            try manager.clearToken()
            token = ""
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
