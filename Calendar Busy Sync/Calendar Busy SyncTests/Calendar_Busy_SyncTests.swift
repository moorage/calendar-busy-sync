import XCTest
@testable import Calendar_Busy_Sync

final class Calendar_Busy_SyncTests: XCTestCase {
    func testLaunchOptionsParseScenarioArguments() {
        let stateURL = URL(fileURLWithPath: "/tmp/state.json")
        let perfURL = URL(fileURLWithPath: "/tmp/perf.json")
        let screenshotURL = URL(fileURLWithPath: "/tmp/window.png")

        let options = HarnessLaunchOptions.fromProcess(arguments: [
            "App",
            "--scenario-root", "/tmp/scenarios",
            "--scenario", "basic-cross-busy.json",
            "--window-size", "900x700",
            "--dump-visible-state", stateURL.path,
            "--dump-perf-state", perfURL.path,
            "--screenshot-path", screenshotURL.path,
            "--harness-command-dir", "/tmp/commands",
            "--platform-target", "ios",
            "--device-class", "ipad",
            "--ui-test-mode", "1",
        ])

        XCTAssertEqual(options.scenarioRoot?.path, "/tmp/scenarios")
        XCTAssertEqual(options.scenarioName, "basic-cross-busy.json")
        XCTAssertEqual(options.windowSize?.width, 900)
        XCTAssertEqual(options.windowSize?.height, 700)
        XCTAssertEqual(options.dumpVisibleStateURL, stateURL)
        XCTAssertEqual(options.dumpPerfStateURL, perfURL)
        XCTAssertEqual(options.screenshotPathURL, screenshotURL)
        XCTAssertEqual(options.commandDirectoryURL?.path, "/tmp/commands")
        XCTAssertEqual(options.platformTarget, .ios)
        XCTAssertEqual(options.deviceClass, .ipad)
        XCTAssertTrue(options.uiTestMode)
    }

    func testScenarioStateBuildsMirrorPreviewOnlyForBusyEvents() throws {
        let scenario = BusySyncScenario(
            scenarioName: "unit-test",
            accounts: [
                ConnectedAccountScenario(
                    id: "a",
                    provider: "google",
                    displayName: "Account A",
                    selectedCalendars: [
                        SelectedCalendar(id: "source", name: "Source", role: .sourceAndDestination),
                        SelectedCalendar(id: "dest1", name: "Destination 1", role: .destination),
                    ]
                ),
                ConnectedAccountScenario(
                    id: "b",
                    provider: "google",
                    displayName: "Account B",
                    selectedCalendars: [
                        SelectedCalendar(id: "dest2", name: "Destination 2", role: .destination),
                    ]
                ),
            ],
            sourceEvents: [
                SourceEventScenario(
                    calendarId: "source",
                    eventId: "evt-1",
                    title: "Busy event",
                    availability: "busy",
                    start: "2026-04-21T10:00:00-07:00",
                    end: "2026-04-21T11:00:00-07:00"
                ),
                SourceEventScenario(
                    calendarId: "source",
                    eventId: "evt-2",
                    title: "Free event",
                    availability: "free",
                    start: "2026-04-21T12:00:00-07:00",
                    end: "2026-04-21T13:00:00-07:00"
                ),
            ],
            expectedMirrorPreview: []
        )

        let state = ScenarioState.build(from: scenario)

        XCTAssertEqual(state.connectedAccountCount, 2)
        XCTAssertEqual(state.selectedCalendarCount, 3)
        XCTAssertEqual(state.mirrorPreview.count, 2)
        XCTAssertEqual(
            state.mirrorPreview,
            [
                MirrorPreviewEntry(sourceCalendar: "Source", targetCalendar: "Destination 1", availability: "busy"),
                MirrorPreviewEntry(sourceCalendar: "Source", targetCalendar: "Destination 2", availability: "busy"),
            ]
        )
    }

    func testIntegrationScenarioLoadsAndSnapshotMatches() throws {
        let state = try ScenarioLoader().load(
            rootURL: repoRootURL().appendingPathComponent("Fixtures/scenarios", isDirectory: true),
            scenarioName: "basic-cross-busy.json"
        )

        XCTAssertEqual(state.scenario.scenarioName, "basic-cross-busy")
        XCTAssertEqual(state.connectedAccountCount, 2)
        XCTAssertEqual(state.selectedCalendarCount, 4)
        XCTAssertEqual(state.pendingWriteCount, 3)
        XCTAssertEqual(state.failedWriteCount, 0)
        XCTAssertEqual(state.mirrorPreview, state.scenario.expectedMirrorPreview)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
