import XCTest

final class AgentTrafficLightUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuBarApplicationLaunchesWithoutOpeningAWindow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AGENT_TRAFFIC_DIR"] = temporaryStatusDirectory()
        app.launch()

        waitUntilRunning(app)
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertEqual(app.windows.count, 0, "A menu bar utility must not open a regular window on launch")
    }

    private func temporaryStatusDirectory() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-signals-ui-\(UUID().uuidString)", isDirectory: true)
            .path
    }

    @MainActor
    private func waitUntilRunning(_ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
