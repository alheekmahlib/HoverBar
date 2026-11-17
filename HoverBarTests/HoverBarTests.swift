import XCTest
@testable import HoverBar

final class HoverBarTests: XCTestCase {
    func testAppRunsAsAccessoryWithoutDockIcon() {
        let appBundle = Bundle(for: AppDelegate.self)
        XCTAssertEqual(
            appBundle.infoDictionary?["LSUIElement"] as? Bool,
            true,
            "LSUIElement must stay enabled: HoverBar must never show a Dock icon"
        )
    }
}
