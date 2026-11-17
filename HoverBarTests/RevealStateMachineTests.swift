import XCTest
@testable import HoverBar

final class RevealStateMachineTests: XCTestCase {
    func testHappyPathCollapsedToExpandedAndBack() {
        var machine = RevealStateMachine()
        XCTAssertTrue(machine.send(.hoverEntered))
        XCTAssertEqual(machine.state, .revealing)
        XCTAssertTrue(machine.send(.didReveal))
        XCTAssertEqual(machine.state, .expanded)
        XCTAssertTrue(machine.send(.hoverExited))
        XCTAssertEqual(machine.state, .collapsing)
        XCTAssertTrue(machine.send(.didCollapse))
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testHoverDuringCollapseCancelsBackToRevealing() {
        var machine = RevealStateMachine()
        machine.send(.hoverEntered)
        machine.send(.didReveal)
        machine.send(.hoverExited)
        XCTAssertEqual(machine.state, .collapsing)
        XCTAssertTrue(machine.send(.hoverEntered))
        XCTAssertEqual(machine.state, .revealing)
    }

    func testForcedCollapseFromEveryState() {
        for state in [RevealStateMachine.State.revealing, .expanded, .collapsing] {
            let machine = RevealStateMachine(state: state)
            var mutable = machine
            XCTAssertTrue(mutable.send(.forcedCollapse), "forced collapse must apply from \(state)")
            XCTAssertEqual(mutable.state, .collapsed)
        }
    }

    func testInvalidEventsAreRejected() {
        var collapsedMachine = RevealStateMachine()
        XCTAssertFalse(collapsedMachine.send(.didReveal))
        XCTAssertFalse(collapsedMachine.send(.hoverExited))
        XCTAssertFalse(collapsedMachine.send(.didCollapse))
        XCTAssertEqual(collapsedMachine.state, .collapsed)

        var expandedMachine = RevealStateMachine(state: .expanded)
        XCTAssertFalse(expandedMachine.send(.hoverEntered))
        XCTAssertFalse(expandedMachine.send(.didReveal))
        XCTAssertEqual(expandedMachine.state, .expanded)

        var revealingMachine = RevealStateMachine(state: .revealing)
        XCTAssertFalse(revealingMachine.send(.hoverEntered))
        XCTAssertFalse(revealingMachine.send(.didCollapse))
        XCTAssertEqual(revealingMachine.state, .revealing)
    }
}

extension RevealStateMachine {
    init(state: RevealStateMachine.State) {
        self.init()
        while self.state != state {
            switch self.state {
            case .collapsed:
                _ = self.send(.hoverEntered)
            case .revealing:
                _ = self.send(state == .expanded || state == .collapsing ? .didReveal : .forcedCollapse)
            case .expanded:
                _ = self.send(.hoverExited)
            case .collapsing:
                _ = self.send(.didCollapse)
            }
        }
    }
}
