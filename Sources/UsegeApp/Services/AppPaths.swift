import Foundation

enum AppPaths {
    static func databaseURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? AppConfig.fallbackSharedDirectory
        let directory = support.appendingPathComponent("Usege", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("usege.sqlite3")
    }
}
