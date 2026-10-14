import XCTest
@testable import ScreenshotApp

final class AppLoggerTests: XCTestCase {
    func testRedactionUtility() {
        let textWithBearer = "Authorization failed with Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let redactedBearer = AppLogger.redact(textWithBearer)
        XCTAssertFalse(redactedBearer.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
        XCTAssertTrue(redactedBearer.contains("[REDACTED]"))

        let textWithSecret = "Connecting with secret=super_secret_value_123"
        let redactedSecret = AppLogger.redact(textWithSecret)
        XCTAssertFalse(redactedSecret.contains("super_secret_value_123"))
        XCTAssertTrue(redactedSecret.contains("[REDACTED]"))
    }

    func testInMemoryLogBuffer() {
        let logger = AppLogger.shared
        logger.clearLogs()
        XCTAssertEqual(logger.getRecentLogs().count, 0)

        logger.log(category: "Test", level: .info, message: "Test message 1")
        logger.log(category: "Test", level: .error, message: "Test message 2")

        let logs = logger.getRecentLogs()
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs[0].message, "Test message 1")
        XCTAssertEqual(logs[1].level, .error)
    }
}
