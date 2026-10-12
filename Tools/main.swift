import SwiftUI
import WidgetKit
import AppKit

// Renders the widget views offscreen to PNGs, so the layout can be inspected without
// installing the widget. Uses sample data: a plain CLI has no app-group access.

@MainActor
func render(_ view: some View, size: CGSize, dark: Bool, to path: String) {
    let renderer = ImageRenderer(content:
        view.frame(width: size.width, height: size.height)
            .background(Color(white: dark ? 0.16 : 0.94))
            .environment(\.colorScheme, dark ? .dark : .light))
    renderer.scale = 2
    guard
        let image = renderer.nsImage,
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else { print("render failed: \(path)"); return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func usage(used: Double, limit: Double = 20_000, projected: Double? = nil, overage: Int = 0) -> CopilotUsageData {
    CopilotUsageData(
        plan: "Individual Max", unit: "credits", used: used, limit: limit, unlimited: false,
        percentage: used / limit * 100, overageCount: overage, overagePermitted: overage > 0,
        resetsAt: Calendar.current.date(byAdding: .day, value: 20, to: .now), projectedUsed: projected
    )
}

func entry(_ data: CopilotUsageData?, error: String? = nil, age: TimeInterval = 0) -> CopilotEntry {
    CopilotEntry(date: .now, snapshot: CopilotSnapshot(data: data, error: error, updatedAt: .now.addingTimeInterval(-age)))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"

let unlimited = CopilotUsageData(
    plan: "Business", unit: "requests", used: 0, limit: 0, unlimited: true, percentage: nil,
    overageCount: 0, overagePermitted: false, resetsAt: Calendar.current.date(byAdding: .day, value: 20, to: .now),
    projectedUsed: nil
)

let states: [(String, CopilotEntry)] = [
    ("healthy", .sample),
    ("live", entry(usage(used: 360.7, projected: 979))),
    ("nearlimit", entry(usage(used: 18_400, projected: 24_100))),
    ("overage", entry(usage(used: 20_000, projected: 26_000, overage: 1_240))),
    ("unlimited", entry(unlimited)),
    ("failed", entry(usage(used: 12_400, projected: 16_800), error: "GitHub rejected the token. Import a fresh one.", age: 3_600)),
    ("paused", entry(usage(used: 12_400, projected: 16_800), age: 7_200)),
    ("notoken", entry(nil, error: "No GitHub token yet. Run `gh auth token | pbcopy`, then choose Import Token from Clipboard.")),
]

MainActor.assumeIsolated {
    for (name, e) in states {
        render(CopilotWidgetView(entry: e, familyOverride: .systemSmall).padding(14),
               size: CGSize(width: 155, height: 155), dark: true, to: "\(out)/copilot_\(name)_small.png")
        render(CopilotWidgetView(entry: e, familyOverride: .systemMedium).padding(14),
               size: CGSize(width: 329, height: 155), dark: true, to: "\(out)/copilot_\(name)_medium.png")
    }
    render(CopilotWidgetView(entry: .sample, familyOverride: .systemMedium).padding(14),
           size: CGSize(width: 329, height: 155), dark: false, to: "\(out)/copilot_healthy_medium_light.png")
}
