import XCTest
@testable import Usege

final class NativeMessageSchemaTests: XCTestCase {
    func testDecodeUsageSnapshot() throws {
        let json = """
        {
          "v": 1,
          "type": "usage_snapshot",
          "provider": "codex",
          "captured_at": "2026-02-13T12:00:00Z",
          "source_url": "https://chatgpt.com/codex/settings/usage",
          "metrics": {
            "cost_usd": 10.5,
            "delta_day_usd": 1.2,
            "rate_limit_5h": 25,
            "rate_limit_1w": 40
          },
          "parser_version": "codex.v1"
        }
        """.data(using: .utf8)!

        let payload = try JSONCoding.decoder.decode(NativeMessageV1.self, from: json)

        XCTAssertEqual(payload.v, 1)
        XCTAssertEqual(payload.type, "usage_snapshot")
        XCTAssertEqual(payload.provider, .codex)
        XCTAssertEqual(payload.metrics?.costUSD, 10.5)
        XCTAssertEqual(payload.metrics?.deltaDayUSD, 1.2)
        XCTAssertEqual(payload.metrics?.rateLimit5h, 25)
        XCTAssertEqual(payload.metrics?.rateLimit1w, 40)
        XCTAssertEqual(payload.parserVersion, "codex.v1")
    }

    func testStalePolicy() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = Date(timeIntervalSince1970: 1_700_000_000 - 60)
        let stale = Date(timeIntervalSince1970: 1_700_000_000 - 3600)

        XCTAssertFalse(StalePolicy.isStale(capturedAt: fresh, now: now))
        XCTAssertTrue(StalePolicy.isStale(capturedAt: stale, now: now))
        XCTAssertTrue(StalePolicy.isStale(capturedAt: nil, now: now))
    }

    func testProviderMatchesUsageURL() {
        XCTAssertTrue(
            Provider.codex.matchesUsageURL(
                URL(string: "https://chatgpt.com/codex/settings/usage?tab=billing#limits")!
            )
        )
        XCTAssertTrue(
            Provider.codex.matchesUsageURL(
                URL(string: "https://chatgpt.com/codex/settings/usage/")!
            )
        )
        XCTAssertFalse(
            Provider.codex.matchesUsageURL(
                URL(string: "https://chatgpt.com/codex")!
            )
        )
        XCTAssertFalse(
            Provider.codex.matchesUsageURL(
                URL(string: "https://example.com/codex/settings/usage")!
            )
        )
    }

    func testInsertUsageSnapshotRejectsMismatchedSourceURL() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsegeAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let database = try UsageDatabase(databaseURL: tempDir.appendingPathComponent("usege.sqlite3"))
        let payload = NativeMessageV1(
            v: 1,
            type: "usage_snapshot",
            provider: .codex,
            capturedAt: Date(),
            sourceURL: URL(string: "https://chatgpt.com/pricing")!,
            metrics: UsageMetrics(
                costUSD: 10.5,
                deltaDayUSD: 1.2,
                rateLimit5h: 25,
                rateLimit1w: 40
            ),
            parserVersion: "codex.v2",
            errorCode: nil,
            errorMessage: nil
        )

        do {
            _ = try await database.insertUsageSnapshot(message: payload, rawJSON: "{}")
            XCTFail("Expected invalid payload error")
        } catch let error as DatabaseError {
            switch error {
            case .invalidPayload:
                break
            default:
                XCTFail("Unexpected DatabaseError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
