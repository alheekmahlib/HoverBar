import XCTest
@testable import HoverBar

final class LayoutEngineTests: XCTestCase {
    func testHiddenFramesLayItemsSequentiallyOffscreenLeft() {
        let frames = LayoutEngine.hiddenFrames(widths: [20, 30, 40], y: 8, height: 22, margin: 120)

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].minX, -210, accuracy: 0.001)
        XCTAssertEqual(frames[1].minX, -190, accuracy: 0.001)
        XCTAssertEqual(frames[2].minX, -160, accuracy: 0.001)
        XCTAssertTrue(frames.allSatisfy { $0.minX < 0 && $0.minY == 8 })
        XCTAssertEqual(frames.map(\.width), [20, 30, 40])
    }

    func testHiddenFramesWithNoItems() {
        XCTAssertEqual(LayoutEngine.hiddenFrames(widths: [], y: 0, height: 20), [])
    }

    func testStagingFrameSitsLeftOfAnchor() {
        let anchor = CGRect(x: 1000, y: 8, width: 30, height: 22)
        let staging = LayoutEngine.stagingFrame(width: 40, height: 22, leftOf: anchor)

        XCTAssertEqual(staging.maxX, anchor.minX - 2, accuracy: 0.001)
        XCTAssertEqual(staging.minY, anchor.minY)
        XCTAssertEqual(staging.width, 40)
        XCTAssertEqual(staging.height, 22)
    }

    func testEffectiveBarWidthExcludesNotch() {
        let bar = CGRect(x: 0, y: 0, width: 1512, height: 24)
        XCTAssertEqual(LayoutEngine.effectiveWidth(ofBar: bar, notchWidth: 200), 1312)
        XCTAssertEqual(LayoutEngine.effectiveWidth(ofBar: bar, notchWidth: 0), 1512)
        XCTAssertEqual(LayoutEngine.effectiveWidth(ofBar: bar, notchWidth: 5000), 0)
    }
}
