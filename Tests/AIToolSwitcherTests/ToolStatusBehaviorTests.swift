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
