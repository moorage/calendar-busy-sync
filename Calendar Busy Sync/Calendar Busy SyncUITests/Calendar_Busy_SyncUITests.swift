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

        XCTAssertTrue(app.otherElements["accounts.list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["mirror-preview.list"].exists)
        XCTAssertTrue(app.staticTexts["sync-status.last-run"].exists)
        XCTAssertTrue(app.staticTexts["sync-status.pending-count"].exists)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
