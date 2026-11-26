import XCTest
@testable import AIToolSwitcher

final class ToolStatusBehaviorTests: XCTestCase {
    func testLauncherClickDoesNotCreateWorkingState() {
        XCTAssertEqual(ToolStatusBehavior.statusAfterLauncherClick(.idle), .idle)
    }

    func testLauncherClickKeepsExplicitWorkingState() {
        XCTAssertEqual(ToolStatusBehavior.statusAfterLauncherClick(.working), .working)
    }

    func testLauncherClickAcknowledgesCompletedState() {
        XCTAssertEqual(ToolStatusBehavior.statusAfterLauncherClick(.completed), .idle)
    }
}

final class ApplicationCandidateTests: XCTestCase {
    func testCodexResolvesTerminalWhenDesktopAppIsMissing() throws {
        let codex = try XCTUnwrap(AIToolCatalog.tools.first { $0.title == "Codex" })
        let available = ["com.apple.Terminal": "Terminal.app"]

        XCTAssertEqual(codex.firstMatchingApplication { available[$0] }, "Terminal.app")
    }

    func testCodexPrefersDesktopAppWhenBothAreAvailable() throws {
        let codex = try XCTUnwrap(AIToolCatalog.tools.first { $0.title == "Codex" })
        let available = ["com.apple.Terminal": "Terminal.app", "com.openai.codex": "Codex.app"]

        XCTAssertEqual(codex.firstMatchingApplication { available[$0] }, "Codex.app")
    }
}
