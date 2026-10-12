import Foundation
import SwiftUI

/// What the menu bar and the widget both render. Plain data, so the host app can write
/// it to the shared container and the sandboxed widget extension can read it back.
struct CopilotUsageData: Codable, Sendable, Equatable {
    /// "Individual Max" — GitHub's `copilot_plan`, made readable.
    let plan: String?
    /// What the allowance is counted in. GitHub labels it "credits" under token-based
    /// billing and "requests" otherwise; this follows whatever the API says.
    let unit: String
    let used: Double
    let limit: Double
    /// The plan has no cap on premium usage, so there is no percentage to show.
    let unlimited: Bool
    /// 0–100, or beyond if the allowance is exceeded. `nil` when `unlimited`.
    let percentage: Double?
    let overageCount: Int
    let overagePermitted: Bool
    let resetsAt: Date?
    /// Where usage will land at reset if the pace so far holds. Estimated when fetched.
    let projectedUsed: Double?

    var percentageInt: Int? { percentage.map { Int($0.rounded()) } }

    var projectedPercentage: Double? {
        guard let projectedUsed, limit > 0 else { return nil }
        return projectedUsed / limit * 100
    }

    /// "360 / 20,000 credits"
    var usageSummaryLine: String {
        if unlimited { return "Unlimited" }
        return "\(Self.format(used)) / \(Self.format(limit)) \(unit)"
    }

    /// "On pace for ~980 (5%)", or a warning when the pace would overrun the allowance.
    var paceLine: String? {
        guard let projectedUsed, let projectedPercentage else { return nil }
        if projectedPercentage >= 100 {
            return "On pace to run out before reset"
        }
        return "On pace for ~\(Self.format(projectedUsed)) (\(Int(projectedPercentage.rounded()))%)"
    }

    var overageLine: String? {
        guard overageCount > 0 else { return nil }
        return "Overage: \(Self.format(Double(overageCount))) \(unit)"
    }

    /// Truncates rather than rounds. The true figure can be fractional (360.7 used), and
    /// GitHub's own integer fields truncate it, so rounding up would show a number that
    /// disagrees with GitHub's by one.
    static func format(_ value: Double) -> String {
        Int(value.rounded(.down)).formatted()
    }
}

/// Coarse colour signal readable without opening anything. Same thresholds as the other
/// widgets in this family.
enum CopilotStatusColor {
    static func color(for percentage: Double?) -> Color {
        guard let percentage else { return .secondary }

        if percentage < 80 {
            return .green
        } else if percentage < 90 {
            return .orange
        } else if percentage < 95 {
            return .red
        } else {
            return Color(red: 0.3, green: 0.0, blue: 0.5)
        }
    }
}
