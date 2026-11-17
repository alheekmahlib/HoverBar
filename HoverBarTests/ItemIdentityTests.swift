import XCTest
@testable import HoverBar

final class ItemIdentityTests: XCTestCase {
    func testEqualitySurvivesOwnerTitlePair() {
        let first = ItemIdentity(ownerBundleID: "com.apple.SystemUIServer", title: "Telegram")
        let second = ItemIdentity(ownerBundleID: "com.apple.SystemUIServer", title: "Telegram")
        let differentTitle = ItemIdentity(ownerBundleID: "com.apple.SystemUIServer", title: "Dropbox")
        let differentOwner = ItemIdentity(ownerBundleID: "com.other.app", title: "Telegram")

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
        XCTAssertNotEqual(first, differentTitle)
        XCTAssertNotEqual(first, differentOwner)
    }

    func testFallbackIdentityIsWindowStable() {
        let first = ItemIdentity.fallback(ownerBundleID: "com.apple.SystemUIServer", windowID: 77)
        let second = ItemIdentity.fallback(ownerBundleID: "com.apple.SystemUIServer", windowID: 77)
        let other = ItemIdentity.fallback(ownerBundleID: "com.apple.SystemUIServer", windowID: 78)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(first.title, "window-77")
    }

    func testProtectedItemsClassification() {
        func identity(_ title: String, owner: String = "com.apple.controlcenter") -> ItemIdentity {
            ItemIdentity(ownerBundleID: owner, title: title)
        }

        XCTAssertTrue(ProtectedItems.isImmovable(identity("Clock")))
        XCTAssertTrue(ProtectedItems.isImmovable(identity("Siri")))
        XCTAssertTrue(ProtectedItems.isImmovable(identity("BentoBox")))
        XCTAssertFalse(ProtectedItems.isImmovable(identity("WiFi")))
        XCTAssertFalse(ProtectedItems.isImmovable(identity("Clock", owner: "com.apple.SystemUIServer")))

        XCTAssertTrue(ProtectedItems.isNonHideable(identity("MusicRecognition")))
        XCTAssertFalse(ProtectedItems.isNonHideable(identity("Clock")))
    }
}
