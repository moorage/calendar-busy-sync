import XCTest

final class Calendar_Busy_SyncUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSmokeLaunchShowsScenarioDashboard() throws {
        let app = XCUIApplication()
        let scenarioRoot = repoRootURL().appendingPathComponent("Fixtures/scenarios", isDirectory: true).path
        app.launchArguments = [
            "--scenario-root", scenarioRoot,
            "--scenario", "basic-cross-busy.json",
            "--ui-test-mode", "1",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["sync-status.sync-now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["audit-trail.open"].exists)
        XCTAssertTrue(app.buttons["google-auth.connect"].exists)
        XCTAssertTrue(app.switches["settings.advanced.google-oauth.use-custom"].exists)
        XCTAssertTrue(app.otherElements["mirror-preview.list"].exists)
        XCTAssertTrue(app.staticTexts["sync-status.detail"].exists)
        XCTAssertTrue(app.staticTexts["sync-status.pending-count"].exists)
        XCTAssertTrue(app.staticTexts["sync-status.failed-count"].exists)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
