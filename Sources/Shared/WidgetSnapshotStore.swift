import Foundation

enum WidgetSnapshotStore {
    static func snapshotURL() -> URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier) {
            try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            return container.appendingPathComponent(AppConfig.widgetSnapshotFilename)
        }

        let fallbackDirectory = AppConfig.fallbackSharedDirectory
        try? FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        return fallbackDirectory.appendingPathComponent(AppConfig.widgetSnapshotFilename)
    }

    static func write(_ snapshot: WidgetSnapshot) throws {
        let data = try JSONCoding.encoder.encode(snapshot)
        try data.write(to: snapshotURL(), options: [.atomic])
    }

    static func read() -> WidgetSnapshot {
        let url = snapshotURL()
        guard
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONCoding.decoder.decode(WidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }
}
