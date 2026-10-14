import XCTest
@testable import ScreenshotApp

final class AppErrorTests: XCTestCase {
    func testErrorDomainAndCodes() {
        let permError = AppError.screenCapturePermissionDenied
        XCTAssertEqual(AppError.errorDomain, "com.screenshotapp.error")
        XCTAssertEqual(permError.errorCode, 1001)
        XCTAssertNotNil(permError.errorDescription)
        XCTAssertNotNil(permError.recoverySuggestion)
    }

    func testRedactedDescriptions() {
        let sensitivePathError = AppError.fileReadFailed(path: "/Users/secretuser/Documents/confidential.png")
        let redacted = sensitivePathError.redactedDescription
        XCTAssertFalse(redacted.contains("confidential.png"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))

        let cloudError = AppError.cloudUploadFailed(provider: "AmazonS3", reason: "Invalid token Bearer abc123secret")
        let cloudRedacted = cloudError.redactedDescription
        XCTAssertFalse(cloudRedacted.contains("abc123secret"))
    }
}
