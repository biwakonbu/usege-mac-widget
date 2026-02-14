import Foundation
import WidgetKit

@MainActor
final class AppStore: ObservableObject {
    @Published var providerSnapshots: [ProviderSnapshot] = []
    @Published var totalCostUSD: Double = 0
    @Published var totalDeltaDayUSD: Double = 0
    @Published var generatedAt: Date?
    @Published var lastSyncAt: Date?
    @Published var statusMessage: String = "起動中"

    private let database: UsageDatabase
    private let keychainStore = KeychainStore()
    private let inboxProcessor = HostInboxProcessor()
    private let errorStateKey = "provider_error_state_v1"

    private var providerErrors: [Provider: PersistedError] = [:]
    private var ingestTimer: Timer?
    private var syncTimer: Timer?
    private var started = false

    struct PersistedError: Codable {
        let code: SyncErrorCode
        let message: String
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case updatedAt = "updated_at"
        }
    }

    init() {
        do {
            database = try UsageDatabase(databaseURL: AppPaths.databaseURL())
        } catch {
            fatalError("Database initialization failed: \(error)")
        }

        loadPersistedErrors()
        bootstrapInstallationID()

        Task { @MainActor [weak self] in
            self?.startIfNeeded()
        }
    }

    deinit {
        ingestTimer?.invalidate()
        syncTimer?.invalidate()
    }

    func startIfNeeded() {
        guard !started else {
            return
        }
        started = true

        Task {
            await ingestInbox(reason: "startup")
        }

        ingestTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.ingestInbox(reason: "poll")
            }
        }

        syncTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.syncIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runScheduledTick()
            }
        }
    }

    func syncNow() {
        Task {
            await ingestInbox(reason: "manual")
        }
    }

    private func runScheduledTick() async {
        do {
            try await database.insertSyncRun(status: "scheduled_tick", errorCode: nil, errorMessage: nil)
        } catch {
            statusMessage = "sync_runs 更新失敗: \(error.localizedDescription)"
        }
        await ingestInbox(reason: "scheduled")
    }

    private func ingestInbox(reason: String) async {
        do {
            let messages = try await inboxProcessor.drain()
            if messages.isEmpty {
                if reason == "manual" {
                    statusMessage = "新規メッセージはありません"
                }
                try await refreshUIAndWidget()
                return
            }

            var successCount = 0
            var failureCount = 0
            for message in messages {
                do {
                    try await process(message)
                    successCount += 1
                } catch {
                    failureCount += 1
                    await recordProcessFailure(error, for: message)
                }
            }

            lastSyncAt = Date()
            if failureCount == 0 {
                statusMessage = "同期完了: \(successCount) 件"
            } else {
                statusMessage = "同期完了: \(successCount) 件 / 失敗: \(failureCount) 件"
            }
            persistErrors()

            try await refreshUIAndWidget()
        } catch {
            statusMessage = "同期失敗: \(error.localizedDescription)"
            do {
                try await database.insertSyncRun(
                    status: "failure",
                    errorCode: .unknown,
                    errorMessage: error.localizedDescription
                )
            } catch {
                statusMessage = "同期失敗 / sync_runs 保存失敗"
            }
        }
    }

    private func recordProcessFailure(_ error: Error, for message: InboundMessage) async {
        let code: SyncErrorCode
        let detail: String

        switch error {
        case DatabaseError.invalidPayload(let detailMessage):
            code = .invalidPayload
            detail = detailMessage
        case DatabaseError.sqlite(let detailMessage):
            code = .unknown
            detail = "SQLite error: \(detailMessage)"
        default:
            code = .unknown
            detail = error.localizedDescription
        }

        let provider = message.payload.provider?.rawValue ?? "unknown"
        let fullMessage = "[\(provider)] inbox process failed (\(message.id)): \(detail)"

        do {
            try await database.insertSyncRun(
                status: "failure",
                errorCode: code,
                errorMessage: fullMessage
            )
        } catch {
            statusMessage = "同期失敗 / sync_runs 保存失敗"
        }
    }

    private func process(_ message: InboundMessage) async throws {
        let payload = message.payload

        switch payload.type {
        case "usage_snapshot":
            _ = try await database.insertUsageSnapshot(message: payload, rawJSON: message.rawJSON)
            if let provider = payload.provider {
                providerErrors.removeValue(forKey: provider)
            }
        case "sync_error":
            let provider = payload.provider
            let code = payload.errorCode ?? .unknown
            let detail = payload.errorMessage ?? "Unknown sync error"

            if let provider {
                providerErrors[provider] = PersistedError(
                    code: code,
                    message: detail,
                    updatedAt: Date()
                )
            }

            let fullMessage: String
            if let provider {
                fullMessage = "[\(provider.rawValue)] \(detail)"
            } else {
                fullMessage = detail
            }

            try await database.insertSyncRun(
                status: "failure",
                errorCode: code,
                errorMessage: fullMessage
            )
        default:
            try await database.insertSyncRun(
                status: "ignored",
                errorCode: .invalidPayload,
                errorMessage: "Unsupported type: \(payload.type)"
            )
        }
    }

    private func refreshUIAndWidget() async throws {
        let rows = try await database.fetchLatestRows()
        let now = Date()

        let snapshots = rows.map { row -> ProviderSnapshot in
            let error = providerErrors[row.provider]
            let stale = StalePolicy.isStale(capturedAt: row.capturedAt, now: now)

            if let error {
                return ProviderSnapshot(
                    provider: row.provider,
                    displayName: row.displayName,
                    costUSD: row.costUSD,
                    deltaDayUSD: row.deltaDayUSD,
                    rateLimit5h: row.rateLimit5h,
                    rateLimit1w: row.rateLimit1w,
                    capturedAt: row.capturedAt,
                    stale: true,
                    status: .error,
                    errorCode: error.code,
                    errorMessage: error.message
                )
            }

            let status: ProviderStatus
            if row.capturedAt == nil {
                status = .missing
            } else if stale {
                status = .stale
            } else {
                status = .ok
            }

            return ProviderSnapshot(
                provider: row.provider,
                displayName: row.displayName,
                costUSD: row.costUSD,
                deltaDayUSD: row.deltaDayUSD,
                rateLimit5h: row.rateLimit5h,
                rateLimit1w: row.rateLimit1w,
                capturedAt: row.capturedAt,
                stale: stale,
                status: status,
                errorCode: nil,
                errorMessage: nil
            )
        }

        providerSnapshots = snapshots
        totalCostUSD = snapshots.compactMap { $0.costUSD }.reduce(0, +)
        totalDeltaDayUSD = snapshots.compactMap { $0.deltaDayUSD }.reduce(0, +)
        generatedAt = now

        let widgetSnapshot = WidgetSnapshot(
            generatedAt: now,
            providers: snapshots,
            totalCostUSD: totalCostUSD,
            totalDeltaDayUSD: totalDeltaDayUSD,
            staleCount: snapshots.filter { $0.stale }.count
        )

        try WidgetSnapshotStore.write(widgetSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func bootstrapInstallationID() {
        if keychainStore.getString("installation_id") != nil {
            return
        }

        do {
            try keychainStore.setString(UUID().uuidString, for: "installation_id")
        } catch {
            statusMessage = "Keychain 初期化失敗: \(error.localizedDescription)"
        }
    }

    private func loadPersistedErrors() {
        guard let data = UserDefaults.standard.data(forKey: errorStateKey) else {
            providerErrors = [:]
            return
        }

        guard let stored = try? JSONCoding.decoder.decode([String: PersistedError].self, from: data) else {
            providerErrors = [:]
            return
        }

        providerErrors = stored.reduce(into: [:]) { partial, item in
            if let provider = Provider(rawValue: item.key) {
                partial[provider] = item.value
            }
        }
    }

    private func persistErrors() {
        let map = providerErrors.reduce(into: [String: PersistedError]()) { partial, item in
            partial[item.key.rawValue] = item.value
        }

        guard let data = try? JSONCoding.encoder.encode(map) else {
            return
        }

        UserDefaults.standard.set(data, forKey: errorStateKey)
    }
}
