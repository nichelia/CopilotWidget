import Foundation
import SwiftUI
import Combine // <--- This was missing

// 1. Define the data structure matching your Shortcut JSON
struct CopilotData: Codable {
    let percentage_int: Int
    let total_requests_int: Int
    let total_requests_limit: Int
    let percentage: Double
}

// 2. Create a Manager to fetch and store data
@MainActor
class CopilotManager: ObservableObject {
    @Published var data: CopilotData?
    @Published var isLoading = false
    
    // Timer to auto-refresh every 15 mins
    init() {
        fetchData()
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            Task { @MainActor in
                self.fetchData()
            }
        }
    }

    // Run the Apple Shortcut
    func fetchData() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", "Copilot Usage"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                
                // Decode JSON
                let decoded = try JSONDecoder().decode(CopilotData.self, from: outputData)
                
                DispatchQueue.main.async {
                    self.data = decoded
                    self.isLoading = false
                }
            } catch {
                print("Failed to fetch data: \(error)")
                DispatchQueue.main.async { self.isLoading = false }
            }
        }
    }
    
    // 3. Logic for the color
    var statusColor: Color {
        guard let p = data?.percentage else { return .secondary }
        
        if p < 80 {
            return .green
        } else if p < 90 {
            return .orange
        } else if p < 95 {
            return .red
        } else {
            // Custom Deep Purple (RGB values 0-1)
            return Color(red: 0.3, green: 0.0, blue: 0.5)
        }
    }
}
