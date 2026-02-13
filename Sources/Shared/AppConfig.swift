import Foundation

enum AppConfig {
    static let appGroupIdentifier = "group.com.usege.shared"
    static let widgetSnapshotFilename = "widget_snapshot.json"

    static let inboxDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("UsegeNativeHost", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
    }()

    static let fallbackSharedDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Usege", isDirectory: true)
    }()

    static let nativeHostName = "com.usege.sync.host"
    static let syncIntervalSeconds: TimeInterval = 300
    static let staleThresholdSeconds: TimeInterval = 600
}
