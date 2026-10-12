import Foundation

/// Where the host app and the widget extension exchange state.
///
/// Both processes are sandboxed, so they share nothing by default; the app group
/// container is the bridge. `UserDefaults(suiteName:)` is deliberately not used — the
/// container path is what both processes are guaranteed to agree on.
enum SharedStore {
    static let appGroup = "V7WWTGPQT3.com.nichelia.copilotwidget"

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func read(_ name: String) -> Data? {
        guard let url = directory?.appendingPathComponent(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    static func write(_ data: Data, to name: String) -> Bool {
        guard let directory else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// Last result of a refresh. On failure the last good reading is kept, so the widget can
/// show it beside the error instead of going blank.
struct CopilotSnapshot: Codable, Sendable {
    var data: CopilotUsageData?
    var error: String?
    var updatedAt: Date
}

enum CopilotSnapshotCache {
    private static let file = "snapshot.json"

    @discardableResult
    static func save(_ snapshot: CopilotSnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return SharedStore.write(data, to: file)
    }

    static func load() -> CopilotSnapshot? {
        guard let data = SharedStore.read(file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CopilotSnapshot.self, from: data)
    }
}
