import WidgetKit
import SwiftUI

@main
struct CopilotWidgetBundle: WidgetBundle {
    var body: some Widget {
        CopilotUsageWidget()
    }
}

struct CopilotUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CopilotUsageWidget", provider: CopilotProvider()) { entry in
            CopilotWidgetView(entry: entry)
        }
        .configurationDisplayName("Copilot Usage")
        .description("How much of your GitHub Copilot premium allowance is used this cycle.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
