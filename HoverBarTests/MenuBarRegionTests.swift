import XCTest
@testable import HoverBar

final class MenuBarRegionTests: XCTestCase {
    func testMenuBarRectRunsAlongTopEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let rect = MenuBarRegion.menuBarRect(forScreenFrame: screen, barHeight: 24)

        XCTAssertEqual(rect.minX, 0)
        XCTAssertEqual(rect.maxY, 982)
        XCTAssertEqual(rect.width, 1512)
        XCTAssertEqual(rect.height, 24)
    }

    func testMenuBarRectOnSecondaryScreenWithOffset() {
        let screen = CGRect(x: 1512, y: 100, width: 1000, height: 800)
        let rect = MenuBarRegion.menuBarRect(forScreenFrame: screen, barHeight: 37)

        XCTAssertEqual(rect.minX, 1512)
        XCTAssertEqual(rect.maxY, 900)
        XCTAssertEqual(rect.height, 37)
    }

    func testBarHeightFallsBackWhenStatusBarUnavailable() {
        XCTAssertEqual(MenuBarRegion.barHeight(statusBarThickness: nil), 24)
        XCTAssertEqual(MenuBarRegion.barHeight(statusBarThickness: 37), 37)
    }

    func testContainsAcrossMultipleRegions() {
        let rects = [
            CGRect(x: 0, y: 958, width: 1512, height: 24),
            CGRect(x: 1512, y: 863, width: 1000, height: 37),
        ]

        XCTAssertTrue(MenuBarRegion.contains(CGPoint(x: 10, y: 970), inRects: rects))
        XCTAssertTrue(MenuBarRegion.contains(CGPoint(x: 2000, y: 880), inRects: rects))
        XCTAssertFalse(MenuBarRegion.contains(CGPoint(x: 10, y: 500), inRects: rects))
        XCTAssertFalse(MenuBarRegion.contains(CGPoint(x: -5, y: 970), inRects: rects))
    }
}
