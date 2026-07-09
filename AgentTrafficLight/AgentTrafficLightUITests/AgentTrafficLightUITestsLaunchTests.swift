import XCTest

final class AgentTrafficLightUITestsLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testApplicationCanRelaunchAfterTermination() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AGENT_TRAFFIC_DIR"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-signals-relaunch-\(UUID().uuidString)", isDirectory: true)
            .path

        app.launch()
        XCTAssertNotEqual(app.state, .notRunning)
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)

        app.launch()
        XCTAssertNotEqual(app.state, .notRunning)
    }
}
