import Foundation

struct StoredInboundMessage {
    let id: String
    let rawData: Data
}

enum HostInboxStore {
    static func ensureInboxDirectory() throws {
        try FileManager.default.createDirectory(
            at: AppConfig.inboxDirectory,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    static func persistInboundMessage(_ data: Data) throws -> String {
        try ensureInboxDirectory()
        let id = UUID().uuidString
        let filename = "\(ISO8601DateFormatter.defaultFormatter.string(from: Date()))_\(id).json"
        let fileURL = AppConfig.inboxDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: [.atomic])
        return id
    }

    static func drainMessages() throws -> [StoredInboundMessage] {
        try ensureInboxDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: AppConfig.inboxDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var messages: [StoredInboundMessage] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            let id = url.deletingPathExtension().lastPathComponent
            messages.append(StoredInboundMessage(id: id, rawData: data))
            try? FileManager.default.removeItem(at: url)
        }
        return messages
    }
}
