import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude
    case cursor
    case gemini
    case zai
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .cursor:
            return "Cursor"
        case .gemini:
            return "Gemini"
        case .zai:
            return "Z.ai"
        case .antigravity:
            return "Antigravity"
        }
    }

    var sourceURL: URL {
        switch self {
        case .codex:
            return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .claude:
            return URL(string: "https://claude.ai/settings/billing")!
        case .cursor:
            return URL(string: "https://cursor.com/settings/billing")!
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/settings/plan")!
        case .zai:
            return URL(string: "https://z.ai/manage-apikey/subscription")!
        case .antigravity:
            return URL(string: "https://antigravity.example.invalid")!
        }
    }
}

enum ProviderStatus: String, Codable {
    case ok
    case stale
    case missing
    case error
}

enum SyncErrorCode: String, Codable {
    case authRequired = "AUTH_REQUIRED"
    case parserBroken = "PARSER_BROKEN"
    case hostUnavailable = "HOST_UNAVAILABLE"
    case invalidPayload = "INVALID_PAYLOAD"
    case unknown = "UNKNOWN"
}

struct UsageMetrics: Codable {
    let costUSD: Double
    let deltaDayUSD: Double
    let rateLimit5h: Double?
    let rateLimit1w: Double?

    enum CodingKeys: String, CodingKey {
        case costUSD = "cost_usd"
        case deltaDayUSD = "delta_day_usd"
        case rateLimit5h = "rate_limit_5h"
        case rateLimit1w = "rate_limit_1w"
    }
}

struct NativeMessageV1: Codable {
    let v: Int
    let type: String
    let provider: Provider?
    let capturedAt: Date?
    let sourceURL: URL?
    let metrics: UsageMetrics?
    let parserVersion: String?
    let errorCode: SyncErrorCode?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case v
        case type
        case provider
        case capturedAt = "captured_at"
        case sourceURL = "source_url"
        case metrics
        case parserVersion = "parser_version"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

struct NativeHostResponse: Codable {
    let v: Int
    let ok: Bool
    let acceptedAt: Date
    let snapshotID: String?
    let errorCode: SyncErrorCode?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case v
        case ok
        case acceptedAt = "accepted_at"
        case snapshotID = "snapshot_id"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

struct ProviderSnapshot: Codable, Identifiable {
    var id: String { provider.rawValue }

    let provider: Provider
    let displayName: String
    let costUSD: Double?
    let deltaDayUSD: Double?
    let rateLimit5h: Double?
    let rateLimit1w: Double?
    let capturedAt: Date?
    let stale: Bool
    let status: ProviderStatus
    let errorCode: SyncErrorCode?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case displayName = "display_name"
        case costUSD = "cost_usd"
        case deltaDayUSD = "delta_day_usd"
        case rateLimit5h = "rate_limit_5h"
        case rateLimit1w = "rate_limit_1w"
        case capturedAt = "captured_at"
        case stale
        case status
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let providers: [ProviderSnapshot]
    let totalCostUSD: Double
    let totalDeltaDayUSD: Double
    let staleCount: Int

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case providers
        case totalCostUSD = "total_cost_usd"
        case totalDeltaDayUSD = "total_delta_day_usd"
        case staleCount = "stale_count"
    }

    static let empty = WidgetSnapshot(
        generatedAt: Date.distantPast,
        providers: [],
        totalCostUSD: 0,
        totalDeltaDayUSD: 0,
        staleCount: 0
    )
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractional.date(from: value) ?? ISO8601DateFormatter.defaultFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }
}

extension ISO8601DateFormatter {
    static let defaultFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum StalePolicy {
    static func isStale(capturedAt: Date?, now: Date = Date()) -> Bool {
        guard let capturedAt else {
            return true
        }
        return now.timeIntervalSince(capturedAt) > AppConfig.staleThresholdSeconds
    }
}
