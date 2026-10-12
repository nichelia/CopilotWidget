import AppKit
import SwiftUI

@main
struct CopilotWidgetApp: App {
    @StateObject private var manager = CopilotManager()

    var body: some Scene {
        MenuBarExtra {
            if let data = manager.data {
                if let percentage = data.percentageInt {
                    Text("Usage: \(percentage)%")
                    Text(data.usageSummaryLine)
                } else {
                    Text("Usage: Unlimited")
                }
                if let plan = data.plan {
                    Text("Plan: \(plan)")
                }
                if let pace = data.paceLine {
                    Text(pace)
                }
                if let overage = data.overageLine {
                    Text(overage)
                }
                if let resetDate = data.resetsAt {
                    Text("Resets: \(resetDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }

            if let error = manager.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else if manager.data == nil {
                Text("Loading data...")
            }

            Divider()

            Button("Refresh Now") {
                manager.fetchData()
            }
            .keyboardShortcut("r")

            Button("Import Token from Clipboard") {
                manager.importTokenFromClipboard()
            }

            OpenSettingsButton()

            Toggle("Open at Login", isOn: Binding(
                get: { manager.launchAtLogin },
                set: { manager.setLaunchAtLogin($0) }
            ))

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            if let percentage = manager.data?.percentageInt {
                Text("\(percentage)%")
                    .monospacedDigit()
                    .foregroundStyle(manager.statusColor)
            } else if manager.data?.unlimited == true {
                Text("∞")
            } else {
                Text("--%")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            TokenSettingsView(manager: manager)
        }
    }
}

/// Opening Settings from a menu bar app needs two things that are easy to miss.
///
/// `NSApp.sendAction(Selector(("showSettingsWindow:")))` is a private-selector hack that
/// Apple replaced with the `openSettings` environment action in macOS 14 — it silently does
/// nothing. And because this is an `LSUIElement` accessory app, it has no regular activation
/// policy, so even a window that does open stays behind whatever is frontmost. Switching to
/// `.regular` for the lifetime of the window makes it appear and take focus.
private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Token Settings...") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()

            // The window is created asynchronously; raise it once it exists.
            DispatchQueue.main.async {
                NSApp.windows
                    .first { $0.canBecomeKey && $0.isVisible }?
                    .makeKeyAndOrderFront(nil)
            }
        }
        .keyboardShortcut(",")
    }
}
