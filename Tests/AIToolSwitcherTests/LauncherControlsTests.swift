import CoreGraphics
import XCTest
@testable import AIToolSwitcher

final class LauncherControlsTests: XCTestCase {
    func testVisibilityCanBeRestoredAndLeavesOneTool() {
        let catalog = ["Codex", "Cursor"]
        var selection = ToolVisibility(catalog: catalog, savedHidden: [])
        XCTAssertEqual(selection.visibleTitles, catalog)
        XCTAssertTrue(selection.toggle("Cursor"))
        XCTAssertFalse(selection.toggle("Codex"))
        XCTAssertEqual(ToolVisibility(catalog: catalog, savedHidden: Array(selection.hidden)).visibleTitles, ["Codex"])
        XCTAssertTrue(selection.toggle("Cursor"))
        XCTAssertEqual(selection.visibleTitles, catalog)
    }

    func testVisibilityIgnoresUnknownSettingsAndRecoversFromAllHidden() {
        let selection = ToolVisibility(catalog: ["Codex", "Cursor"], savedHidden: ["old", "Codex", "Cursor"])
        XCTAssertEqual(selection.visibleTitles, ["Codex"])
        XCTAssertEqual(selection.hidden, ["Cursor"])
    }

    func testPanelPlacementKeepsTopLeftAndFitsOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let size = CGSize(width: 438, height: 74)
        XCTAssertEqual(PanelPlacement.frame(size: size, anchor: nil, in: screen), CGRect(x: 281, y: 614, width: 438, height: 74))
        XCTAssertEqual(PanelPlacement.frame(size: size, anchor: CGPoint(x: 100, y: 640), in: screen), CGRect(x: 100, y: 566, width: 438, height: 74))
        XCTAssertEqual(PanelPlacement.frame(size: size, anchor: CGPoint(x: 950, y: 800), in: screen), CGRect(x: 562, y: 626, width: 438, height: 74))
    }

    func testDesktopCodexDoesNotCompeteWithRunningTerminal() {
        let ids = ["com.openai.codex", "com.apple.Terminal"]
        XCTAssertEqual(ActivationRouting.candidates(ids, preferredAvailable: true), ["com.openai.codex"])
        XCTAssertEqual(ActivationRouting.candidates(ids, preferredAvailable: false), ids)
    }
}
