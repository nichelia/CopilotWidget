import SwiftUI
import WidgetKit

struct CopilotWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: CopilotEntry
    /// `widgetFamily` is read-only, so the offscreen renderer passes the size here.
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let data = snapshot.data {
                if family == .systemSmall {
                    SmallView(entry: entry, snapshot: snapshot, data: data)
                } else {
                    MediumView(entry: entry, snapshot: snapshot, data: data)
                }
            } else {
                Placeholder(error: entry.snapshot?.error)
            }
        }
        .widgetContainerSurface()
    }
}

// MARK: - Pieces

private struct Ring: View {
    /// `nil` for an unlimited plan: a full, quiet ring with an infinity mark.
    let percentage: Double?
    var lineWidth: CGFloat = 10

    var body: some View {
        let tint = CopilotStatusColor.color(for: percentage)
        ZStack {
            Circle().stroke(.secondary.opacity(0.2), lineWidth: lineWidth)
            if let percentage {
                Circle()
                    .trim(from: 0, to: max(0.005, min(1, percentage / 100)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percentage.rounded()))%")
                    .font(.system(size: lineWidth * 2.6, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            } else {
                Text("∞")
                    .font(.system(size: lineWidth * 3.2, weight: .semibold, design: .rounded))
            }
        }
    }
}

private struct Freshness: View {
    let entry: CopilotEntry
    let snapshot: CopilotSnapshot

    var body: some View {
        let problem = snapshot.error != nil
        HStack(spacing: 4) {
            Circle()
                .fill(problem ? Color.red : entry.isStale ? Color.orange : Color.green)
                .frame(width: 5, height: 5)
            // Two Texts in a stack rather than `Text + Text`, which is deprecated in macOS 26.
            HStack(spacing: 0) {
                if problem || entry.isStale {
                    Text(problem ? "Refresh failed · " : "Paused · ")
                        .foregroundStyle(problem ? Color.red : Color.orange)
                }
                Text(snapshot.updatedAt, style: .relative)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 9))
        }
    }
}

// MARK: - Families

private struct SmallView: View {
    let entry: CopilotEntry
    let snapshot: CopilotSnapshot
    let data: CopilotUsageData

    var body: some View {
        VStack(spacing: 8) {
            Ring(percentage: data.percentage, lineWidth: 9)
                .padding(.horizontal, 10)
            Freshness(entry: entry, snapshot: snapshot)
        }
    }
}

private struct MediumView: View {
    let entry: CopilotEntry
    let snapshot: CopilotSnapshot
    let data: CopilotUsageData

    var body: some View {
        HStack(spacing: 18) {
            Ring(percentage: data.percentage, lineWidth: 11)
                .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 5) {
                Text("Copilot" + (data.plan.map { " · \($0)" } ?? ""))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(data.usageSummaryLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let pace = data.paceLine {
                    Text(pace)
                        .font(.system(size: 11))
                        .foregroundStyle((data.projectedPercentage ?? 0) >= 100 ? Color.orange : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                if let overage = data.overageLine {
                    Text(overage)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if let reset = data.resetsAt {
                    Text("Resets \(reset.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Freshness(entry: entry, snapshot: snapshot)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Placeholder: View {
    let error: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.50percent").font(.title2).foregroundStyle(.secondary)
            Text(error == nil ? "No usage yet" : "Couldn't load usage")
                .font(.system(size: 12, weight: .semibold))
            Text(error ?? "Open Copilot Widget to fetch your usage.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
    }
}

extension View {
    /// macOS 26 draws desktop widgets on its own glass container; painting over it would
    /// hide the material, so the background stays clear there. `glassEffect` is deliberately
    /// not used inside the widget: it draws nothing in a widget's out-of-process render.
    @ViewBuilder
    func widgetContainerSurface() -> some View {
        if #available(macOS 26.0, *) {
            containerBackground(.clear, for: .widget)
        } else {
            containerBackground(.fill.tertiary, for: .widget)
        }
    }
}
