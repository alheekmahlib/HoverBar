import ApplicationServices
import XCTest
@testable import HoverBar

private final class ElementRegistry {
    private var elements: [ObjectIdentifier: String] = [:]

    func element(for title: String) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid_t(1000 + elements.count))
        elements[ObjectIdentifier(element)] = title
        return element
    }

    func title(of element: AXUIElement) -> String? {
        elements[ObjectIdentifier(element)]
    }
}

private final class FakeScanner: ScansItems {
    var items: [MenuBarItem] = []

    func scanAllItems() -> [MenuBarItem] { items }

    func setX(_ x: CGFloat, ofItemTitled title: String) {
        items = items.map { $0.identity.title == title ? $0.movingTo(x: x) : $0 }
    }
}

private final class FakeMover: MovesItems {
    weak var scanner: FakeScanner?
    var registry: ElementRegistry?
    var calls: [CGPoint] = []
    var failAll = false

    @discardableResult
    func move(_ element: AXUIElement, to point: CGPoint) -> Bool {
        guard !failAll else { return false }
        calls.append(point)
        if let title = registry?.title(of: element) {
            scanner?.setX(point.x < 0 ? -999 : point.x, ofItemTitled: title)
        }
        return true
    }
}

private func makeItem(
    title: String,
    owner: MenuBarItemOwner,
    x: CGFloat,
    width: CGFloat,
    windowID: CGWindowID
) -> MenuBarItem {
    let bundleID = owner.bundleIdentifier ?? "unknown"
    return MenuBarItem(
        identity: ItemIdentity(ownerBundleID: bundleID, title: title),
        owner: owner,
        ownerPID: 123,
        windowID: windowID,
        frame: CGRect(x: x, y: 8, width: width, height: 22),
        isOnScreen: true,
        displayName: title
    )
}

private extension MenuBarItem {
    func movingTo(x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            identity: identity,
            owner: owner,
            ownerPID: ownerPID,
            windowID: windowID,
            frame: CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height),
            isOnScreen: x >= 0,
            displayName: displayName
        )
    }
}

final class VisibilityControllerTests: XCTestCase {
    private var scanner: FakeScanner!
    private var mover: FakeMover!
    private var controller: VisibilityController!

    private var registry: ElementRegistry!

    override func setUp() {
        super.setUp()
        scanner = FakeScanner()
        registry = ElementRegistry()
        mover = FakeMover()
        mover.scanner = scanner
        mover.registry = registry
        controller = VisibilityController(scanner: scanner, mover: mover, policy: VisibilityPolicy())
        controller.elementResolver = { [registry] item in
            registry.element(for: item.identity.title)
        }
    }

    private func installSampleBar() {
        scanner.items = [
            makeItem(title: "WiFi", owner: .controlCenter, x: 1200, width: 26, windowID: 1),
            makeItem(title: "Clock", owner: .controlCenter, x: 1300, width: 60, windowID: 2),
            makeItem(title: "Telegram", owner: .other("ru.keepcoder.Telegram"), x: 1000, width: 30, windowID: 3),
            makeItem(title: "Dropbox", owner: .other("com.dropbox.Dropbox"), x: 1040, width: 28, windowID: 4),
            makeItem(title: "Raycast", owner: .other("com.raycast.macos"), x: 1080, width: 32, windowID: 5),
        ]
    }

    func testHidePassHidesOnlyThirdPartyItems() {
        installSampleBar()

        let summary = controller.applyHiddenState()

        XCTAssertEqual(summary.moved, 3)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(controller.hiddenItems.count, 3)
        XCTAssertEqual(mover.calls.count, 3)

        // Sequential offscreen slots.
        XCTAssertEqual(mover.calls.map(\.x), [-400, -500, -600])
    }

    func testRejectedMovesMarkItemsUnsupportedAndStayVisible() {
        installSampleBar()
        mover.failAll = true

        let summary = controller.applyHiddenState()

        XCTAssertEqual(summary.moved, 0)
        XCTAssertEqual(summary.failed, 3)
        XCTAssertTrue(controller.hiddenItems.isEmpty)
        XCTAssertTrue(mover.calls.isEmpty)

        // Failed items are never retried.
        mover.failAll = false
        let retry = controller.applyHiddenState()
        XCTAssertEqual(retry.moved, 0)
        XCTAssertTrue(mover.calls.isEmpty)
    }

    func testRestoreAllReturnsItemsToOriginalFrames() {
        installSampleBar()
        controller.applyHiddenState()

        let summary = controller.restoreAll()

        XCTAssertEqual(summary.moved, 3)
        XCTAssertEqual(mover.calls.suffix(3).map(\.x), [1000, 1040, 1080])
        XCTAssertTrue(controller.hiddenItems.isEmpty)
    }

    func testEscapedHiddenItemGetsRehidden() {
        installSampleBar()
        controller.applyHiddenState()
        XCTAssertEqual(controller.hiddenItems.count, 3)

        // One app brings its item back on screen; the others stay parked.
        scanner.items = scanner.items.map { item in
            switch item.identity.title {
            case "Telegram":
                return item.movingTo(x: 1010)
            case "Dropbox", "Raycast":
                return item.movingTo(x: -999)
            default:
                return item
            }
        }

        let summary = controller.applyHiddenState()

        XCTAssertEqual(summary.moved, 1)
        XCTAssertEqual(controller.hiddenItems.count, 3)
    }

    func testRescanMergesNewAndVanishedItems() {
        installSampleBar()
        controller.applyHiddenState()
        XCTAssertEqual(controller.tracked.count, 5)

        // Telegram quits (its item was hidden — it stays tracked as parked);
        // a new item appears.
        scanner.items = scanner.items.filter { $0.identity.title != "Telegram" }
            + [makeItem(title: "NewApp", owner: .other("com.new.app"), x: 1100, width: 24, windowID: 9)]

        controller.rescan()

        // Hidden items never drop out of tracking; only visible vanished ones do.
        XCTAssertEqual(controller.tracked.count, 6)
        XCTAssertTrue(controller.tracked.contains { $0.identity.title == "Telegram" && $0.isHidden })
        XCTAssertTrue(controller.tracked.contains { $0.identity.title == "NewApp" })

        // A visible item that quits is removed.
        scanner.items = scanner.items.filter { $0.identity.title != "NewApp" }
        controller.rescan()
        XCTAssertFalse(controller.tracked.contains { $0.identity.title == "NewApp" })
    }

    func testLeftmostVisibleAnchorIgnoresHiddenItems() {
        installSampleBar()
        controller.applyHiddenState()

        // Hidden third-party items (x 1000…) must not be anchors; the WiFi
        // item at 1200 is the leftmost always-visible one.
        XCTAssertEqual(controller.leftmostVisibleAnchor?.minX, 1200)
    }

    func testPolicySeparatesHostedThirdPartyFromSystemModules() {
        let policy = VisibilityPolicy()

        let hostedItem = makeItem(title: "", owner: .controlCenter, x: 700, width: 39, windowID: 10)
        let wifiItem = makeItem(title: "Wi-Fi, connected, 3 bars", owner: .controlCenter, x: 1100, width: 33, windowID: 11)
        let clockItem = makeItem(title: "Clock", owner: .controlCenter, x: 1300, width: 157, windowID: 12)
        let ownItem = MenuBarItem(
            identity: ItemIdentity(ownerBundleID: "com.hawazensameer.hoverbar", title: "Settings"),
            owner: .hoverBar,
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            windowID: 13,
            frame: CGRect(x: 1400, y: 8, width: 30, height: 22),
            isOnScreen: true,
            displayName: "HoverBar"
        )
        let externalOwner = MenuBarItem(
            identity: ItemIdentity(ownerBundleID: "is.nexus.app", title: "Nexus"),
            owner: .other("is.nexus.app"),
            ownerPID: 555,
            windowID: 77,
            frame: CGRect(x: 650, y: 8, width: 32, height: 22),
            isOnScreen: true,
            displayName: "Nexus"
        )

        XCTAssertTrue(policy.shouldHide(hostedItem))
        XCTAssertFalse(policy.shouldHide(wifiItem))
        XCTAssertFalse(policy.shouldHide(clockItem))
        XCTAssertFalse(policy.shouldHide(ownItem))
        XCTAssertTrue(policy.shouldHide(externalOwner))
    }
}
