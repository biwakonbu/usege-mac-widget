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
}
