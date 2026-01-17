import SwiftUI

@main
struct CopilotWidgetApp: App {
    @StateObject private var manager = CopilotManager()
    
    var body: some Scene {
        MenuBarExtra {
            // --- Content ---
            if let data = manager.data {
                Text("Usage: \(data.percentage_int)%")
                Text("\(data.total_requests_int) / \(data.total_requests_limit) requests")
            } else {
                Text("Loading data...")
            }
            
            Divider()
            
            Button("Refresh Now") {
                manager.fetchData()
            }
            .keyboardShortcut("r")
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            
        } label: {
            // --- Label (No dot, just colored text) ---
            if let data = manager.data {
                Text("\(data.percentage_int)%")
                    .monospacedDigit()
                    .foregroundColor(manager.statusColor)
            } else {
                Text("--%")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
