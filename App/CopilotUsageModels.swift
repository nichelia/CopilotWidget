import Foundation

/// `GET https://api.github.com/copilot_internal/user`
///
/// An undocumented endpoint — the one Copilot's editor integrations call. Every field is
/// optional and decoded leniently, so GitHub adding, renaming or retyping one degrades the
/// detail instead of breaking the widget.
struct CopilotUserResponse: Decodable {
    let login: String?
    let copilotPlan: String?
    let quotaResetDate: String?
    let quotaResetDateUTC: String?
    let tokenBasedBilling: Bool?
    let quotaSnapshots: [String: QuotaSnapshot]?

    enum CodingKeys: String, CodingKey {
        case login
        case copilotPlan = "copilot_plan"
        case quotaResetDate = "quota_reset_date"
        case quotaResetDateUTC = "quota_reset_date_utc"
        case tokenBasedBilling = "token_based_billing"
        case quotaSnapshots = "quota_snapshots"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        login = try? c.decodeIfPresent(String.self, forKey: .login)
        copilotPlan = try? c.decodeIfPresent(String.self, forKey: .copilotPlan)
        quotaResetDate = try? c.decodeIfPresent(String.self, forKey: .quotaResetDate)
        quotaResetDateUTC = try? c.decodeIfPresent(String.self, forKey: .quotaResetDateUTC)
        tokenBasedBilling = try? c.decodeIfPresent(Bool.self, forKey: .tokenBasedBilling)
        quotaSnapshots = try? c.decodeIfPresent([String: QuotaSnapshot].self, forKey: .quotaSnapshots)
    }

    struct QuotaSnapshot: Decodable {
        let unlimited: Bool?
        let entitlement: Double?
        let remaining: Double?
        let quotaRemaining: Double?
        let percentRemaining: Double?
        let creditsUsed: Double?
        let overageCount: Double?
        let overagePermitted: Bool?
        let tokenBasedBilling: Bool?

        enum CodingKeys: String, CodingKey {
            case unlimited, entitlement, remaining
            case quotaRemaining = "quota_remaining"
            case percentRemaining = "percent_remaining"
            case creditsUsed = "credits_used"
            case overageCount = "overage_count"
            case overagePermitted = "overage_permitted"
            case tokenBasedBilling = "token_based_billing"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            unlimited = try? c.decodeIfPresent(Bool.self, forKey: .unlimited)
            entitlement = try? c.decodeIfPresent(Double.self, forKey: .entitlement)
            remaining = try? c.decodeIfPresent(Double.self, forKey: .remaining)
            quotaRemaining = try? c.decodeIfPresent(Double.self, forKey: .quotaRemaining)
            percentRemaining = try? c.decodeIfPresent(Double.self, forKey: .percentRemaining)
            creditsUsed = try? c.decodeIfPresent(Double.self, forKey: .creditsUsed)
            overageCount = try? c.decodeIfPresent(Double.self, forKey: .overageCount)
            overagePermitted = try? c.decodeIfPresent(Bool.self, forKey: .overagePermitted)
            tokenBasedBilling = try? c.decodeIfPresent(Bool.self, forKey: .tokenBasedBilling)
        }
    }
}

enum CopilotUsageParser {
    /// `premium_interactions` is the metered allowance; `chat` and `completions` are
    /// reported as unlimited on the plan this was written against. If it is missing, any
    /// other metered snapshot stands in, and if everything is unlimited so is the result.
    static func parse(_ response: CopilotUserResponse, now: Date = .now) throws -> CopilotUsageData {
        let snapshots = response.quotaSnapshots ?? [:]
        guard !snapshots.isEmpty else { throw CopilotAPIError.noAllowance }

        let plan = response.copilotPlan.map(Self.readablePlan)
        let resetsAt = parseResetDate(response)

        let metered = snapshots["premium_interactions"]
            ?? snapshots.values.first { $0.unlimited != true }

        guard let quota = metered, quota.unlimited != true else {
            return CopilotUsageData(
                plan: plan, unit: "requests", used: 0, limit: 0, unlimited: true,
                percentage: nil, overageCount: 0, overagePermitted: false,
                resetsAt: resetsAt, projectedUsed: nil
            )
        }

        let limit = quota.entitlement ?? 0
        let remaining = quota.quotaRemaining ?? quota.remaining

        // Prefer the quantities: they keep the percentage and the "n / limit" line
        // consistent with each other. Fall back to what GitHub reports as a percentage.
        let used: Double
        let percentage: Double
        if limit > 0, let remaining {
            used = max(0, limit - remaining)
            percentage = used / limit * 100
        } else if limit > 0, let creditsUsed = quota.creditsUsed {
            used = creditsUsed
            percentage = creditsUsed / limit * 100
        } else if let percentRemaining = quota.percentRemaining {
            used = quota.creditsUsed ?? 0
            percentage = max(0, 100 - percentRemaining)
        } else {
            throw CopilotAPIError.noAllowance
        }

        let billedInCredits = quota.tokenBasedBilling ?? response.tokenBasedBilling ?? false

        return CopilotUsageData(
            plan: plan,
            unit: billedInCredits ? "credits" : "requests",
            used: used,
            limit: limit,
            unlimited: false,
            percentage: percentage,
            overageCount: Int(quota.overageCount ?? 0),
            overagePermitted: quota.overagePermitted ?? false,
            resetsAt: resetsAt,
            projectedUsed: project(used: used, resetsAt: resetsAt, now: now)
        )
    }

    /// "individual_max" → "Individual Max".
    static func readablePlan(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func parseResetDate(_ response: CopilotUserResponse) -> Date? {
        if let iso = response.quotaResetDateUTC {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: iso) { return date }
            if let date = ISO8601DateFormatter().date(from: iso) { return date }
        }
        if let day = response.quotaResetDate {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: day)
        }
        return nil
    }

    /// Straight-line estimate of usage at reset. The cycle is taken to start one calendar
    /// month before the reset date — inferred, not reported — and no estimate is made in
    /// the first day, when a handful of requests would extrapolate to nonsense.
    private static func project(used: Double, resetsAt: Date?, now: Date) -> Double? {
        guard let resetsAt else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let start = calendar.date(byAdding: .month, value: -1, to: resetsAt) else { return nil }

        let elapsed = now.timeIntervalSince(start)
        let length = resetsAt.timeIntervalSince(start)
        guard elapsed >= 86_400, length > 0, now < resetsAt else { return nil }

        return used / elapsed * length
    }
}
