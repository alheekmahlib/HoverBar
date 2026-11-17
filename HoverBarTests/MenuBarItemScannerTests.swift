import XCTest
@testable import HoverBar

final class MenuBarItemScannerTests: XCTestCase {
    private func windowInfo(
        layer: Int = 25,
        windowID: Int = 42,
        pid: Int = 123,
        title: String? = "Telegram",
        ownerName: String = "SystemUIServer",
        x: Double = 100,
        y: Double = 0,
        width: Double = 30,
        height: Double = 33,
        onScreen: Int = 1
    ) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowLayer as String: layer,
            kCGWindowNumber as String: windowID,
            kCGWindowOwnerPID as String: pid,
            kCGWindowOwnerName as String: ownerName,
            kCGWindowBounds as String: ["X": x, "Y": y, "Height": height, "Width": width] as [String: Any],
            kCGWindowIsOnscreen as String: onScreen,
        ]
        info[kCGWindowName as String] = title
        return info
    }

    func testParsesValidItemWindow() throws {
        let item = MenuBarItemScanner.item(fromWindowInfo: windowInfo(), layer: 25)
        let parsed = try XCTUnwrap(item)

        XCTAssertEqual(parsed.identity.ownerBundleID, "com.apple.SystemUIServer")
        XCTAssertEqual(parsed.identity.title, "Telegram")
        XCTAssertEqual(parsed.owner, .systemUIServer)
        XCTAssertEqual(parsed.windowID, 42)
        XCTAssertEqual(parsed.frame, CGRect(x: 100, y: 0, width: 30, height: 33))
        XCTAssertTrue(parsed.isOnScreen)
        XCTAssertEqual(parsed.displayName, "Telegram")
    }

    func testCanonicalizesControlCenterOwnerName() throws {
        let item = MenuBarItemScanner.item(
            fromWindowInfo: windowInfo(windowID: 7, title: "WiFi", ownerName: "ControlCenter"),
            layer: 25
        )
        let parsed = try XCTUnwrap(item)

        XCTAssertEqual(parsed.identity.ownerBundleID, "com.apple.controlcenter")
        XCTAssertEqual(parsed.owner, .controlCenter)
        XCTAssertEqual(parsed.displayName, "Wi-Fi")
    }

    func testHostedThirdPartyItemUnderControlCenterIsKeptForPolicy() throws {
        // macOS 26: third-party NSStatusItems live in ControlCenter as "Item-N".
        let item = MenuBarItemScanner.item(
            fromWindowInfo: windowInfo(windowID: 55, title: "Item-0", ownerName: "ControlCenter"),
            layer: 25
        )
        let parsed = try XCTUnwrap(item)

        XCTAssertEqual(parsed.owner, .controlCenter)
        XCTAssertEqual(parsed.identity.title, "Item-0")
        XCTAssertTrue(VisibilityPolicy().shouldHide(parsed))
    }

    func testAcceptsThirdPartyAppOwnedWindow() throws {
        let item = MenuBarItemScanner.item(
            fromWindowInfo: windowInfo(windowID: 66, title: nil, ownerName: "NexusIsland"),
            layer: 25
        )
        let parsed = try XCTUnwrap(item)

        XCTAssertEqual(parsed.owner, .other("NexusIsland"))
        XCTAssertEqual(parsed.identity.title, "window-66")
    }

    func testRejectsNonStatusBarLayers() {
        XCTAssertNil(MenuBarItemScanner.item(fromWindowInfo: windowInfo(layer: 0), layer: 25))
    }

    func testRejectsWindowsThatAreNotBarItemShaped() {
        XCTAssertNil(MenuBarItemScanner.item(fromWindowInfo: windowInfo(width: 0), layer: 25))
        XCTAssertNil(MenuBarItemScanner.item(fromWindowInfo: windowInfo(height: 200), layer: 25))
        XCTAssertNil(MenuBarItemScanner.item(fromWindowInfo: windowInfo(y: 300), layer: 25))
    }

    func testMissingTitleFallsBackToWindowID() throws {
        let item = MenuBarItemScanner.item(
            fromWindowInfo: windowInfo(windowID: 99, title: nil),
            layer: 25
        )
        let parsed = try XCTUnwrap(item)

        XCTAssertEqual(parsed.identity.title, "window-99")
        XCTAssertEqual(parsed.identity, ItemIdentity.fallback(ownerBundleID: "com.apple.SystemUIServer", windowID: 99))
    }

    func testUniquifyTitlesSuffixesDuplicates() {
        func makeTitledItem(_ title: String) -> MenuBarItem {
            MenuBarItemScanner.item(
                fromWindowInfo: windowInfo(windowID: 1, title: title, ownerName: "ControlCenter"),
                layer: 25
            )!
        }
        let items = MenuBarItemScanner.uniquifyTitles([makeTitledItem("Item-0"), makeTitledItem("Item-0"), makeTitledItem("Item-0")])

        XCTAssertEqual(items.map(\.identity.title), ["Item-0", "Item-0#2", "Item-0#3"])
    }
}
