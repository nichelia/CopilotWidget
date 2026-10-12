import WidgetKit
import SwiftUI
import OSLog

/// Read with `log stream`, not `log show`:
///   /usr/bin/log stream --predicate 'subsystem == "com.nichelia.copilotwidget"' --style compact
private let log = Logger(subsystem: "com.nichelia.copilotwidget", category: "widget")

struct CopilotEntry: TimelineEntry {
    let date: Date
    let snapshot: CopilotSnapshot?

    /// The host app refreshes every 15 minutes; much older than that and it is not running.
    var isStale: Bool {
        guard let snapshot else { return false }
        return date.timeIntervalSince(snapshot.updatedAt) > 45 * 60
    }

    static let sample = CopilotEntry(
        date: .now,
        snapshot: CopilotSnapshot(
            data: CopilotUsageData(
                plan: "Individual Max", unit: "credits", used: 12_400, limit: 20_000,
                unlimited: false, percentage: 62, overageCount: 0, overagePermitted: false,
                resetsAt: Calendar.current.date(byAdding: .day, value: 11, to: .now),
                projectedUsed: 16_800
            ),
            error: nil,
            updatedAt: .now
        )
    )
}

struct CopilotProvider: TimelineProvider {
    /// The host app asks for a reload after every fetch; this is only the fallback so the
    /// "paused" state appears if the app stops running.
    private let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> CopilotEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (CopilotEntry) -> Void) {
        completion(context.isPreview ? .sample : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CopilotEntry>) -> Void) {
        let entry = load()
        log.notice("getTimeline: haveSnapshot=\(entry.snapshot != nil, privacy: .public) haveData=\(entry.snapshot?.data != nil, privacy: .public)")
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(refreshInterval))))
    }

    private func load() -> CopilotEntry {
        CopilotEntry(date: .now, snapshot: CopilotSnapshotCache.load())
    }
}
