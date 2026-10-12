import AppKit
import Combine
import ServiceManagement
import SwiftUI
import WidgetKit
import OSLog

private let log = Logger(subsystem: "com.nichelia.copilotwidget", category: "app")

@MainActor
final class CopilotManager: ObservableObject {
    /// The last good reading. Kept when a refresh fails, so the menu and widget show it
    /// beside the error instead of going blank.
    @Published var data: CopilotUsageData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasToken = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let tokenStore = TokenStore()
    private let apiClient = CopilotAPIClient()
    private var refreshTimer: Timer?
    /// When `data` was actually fetched, as opposed to when a refresh was last attempted.
    private var lastSuccess: Date?

    init() {
        hasToken = ((try? tokenStore.load()) ?? nil) != nil
        fetchData()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.fetchData()
            }
        }
    }

    func fetchData() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            do {
                guard let token = try tokenStore.load() else { throw CopilotAPIError.missingToken }
                let usage = try await apiClient.fetchUsage(token: token)
                data = usage
                lastSuccess = .now
                errorMessage = nil
                log.notice("fetch: ok percent=\(usage.percentageInt ?? -1, privacy: .public) unlimited=\(usage.unlimited, privacy: .public)")
            } catch {
                errorMessage = error.localizedDescription
                log.error("fetch: failed \(error.localizedDescription, privacy: .public)")
            }
            publishToWidget()
            isLoading = false
        }
    }

    func importTokenFromClipboard() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else {
            errorMessage = "Clipboard is empty."
            return
        }

        do {
            try saveToken(clipboard)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveToken(_ token: String) throws {
        try tokenStore.save(token)
        hasToken = true
        errorMessage = nil
        log.notice("token: saved")
        fetchData()
    }

    func clearToken() throws {
        try tokenStore.clear()
        hasToken = false
        data = nil
        lastSuccess = nil
        errorMessage = CopilotAPIError.missingToken.errorDescription
        log.notice("token: cleared")
        publishToWidget()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't change Open at Login: \(error.localizedDescription)"
        }

        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        log.notice("launch at login: requested=\(enabled, privacy: .public) status=\(String(describing: status), privacy: .public)")

        // macOS can hold a new login item until the user approves it.
        if enabled, status == .requiresApproval {
            errorMessage = "Approve Copilot Widget in System Settings → General → Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func publishToWidget() {
        let snapshot = CopilotSnapshot(data: data, error: errorMessage, updatedAt: lastSuccess ?? .now)
        let saved = CopilotSnapshotCache.save(snapshot)
        log.notice("publish: saved=\(saved, privacy: .public) haveData=\(self.data != nil, privacy: .public)")
        WidgetCenter.shared.reloadAllTimelines()
    }

    var statusColor: Color {
        CopilotStatusColor.color(for: data?.percentage)
    }
}
