import ComposableArchitecture
import EvenCore
import Foundation
import ResetClient
@testable import ResetFeature
import XCTest

@MainActor
final class ResetFeatureTests: XCTestCase {
    private func partneredState() -> ResetReducer.State {
        ResetReducer.State(
            summary: PreviewData.summary,
            me: PreviewData.ada,
            partner: PreviewData.umut
        )
    }

    // MARK: Beats

    func testAppearLoadsReset() async {
        let store = TestStore(initialState: partneredState()) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.fetch = { PreviewData.resetSummary }
        }

        await store.send(.view(.appear))
        await store.receive(\.resetLoaded) {
            $0.isLoading = false
            $0.reset = PreviewData.resetSummary
        }
    }

    func testSoloHouseholdSkipsTheKindBeat() async {
        var state = ResetReducer.State(
            summary: PreviewData.summaryEmpty, me: PreviewData.ada, partner: nil
        )
        state.isLoading = false
        state.reset = PreviewData.resetSummarySolo

        XCTAssertEqual(state.beats, [.cover, .split, .carry, .pour])

        let store = TestStore(initialState: state) { ResetReducer() }

        await store.send(.view(.advance)) { $0.beat = .split }
        await store.send(.view(.advance)) { $0.beat = .carry }
        // Straight to the pour — there is nobody to exchange a kind thing with.
        await store.send(.view(.advance)) { $0.beat = .pour }
        await store.send(.view(.advance))
    }

    func testPartneredHouseholdWalksAllFiveBeats() async {
        var state = partneredState()
        state.isLoading = false
        state.reset = PreviewData.resetSummary

        XCTAssertEqual(state.beats, [.cover, .split, .carry, .kind, .pour])

        let store = TestStore(initialState: state) { ResetReducer() }
        await store.send(.view(.advance)) { $0.beat = .split }
        await store.send(.view(.advance)) { $0.beat = .carry }
        await store.send(.view(.advance)) { $0.beat = .kind }
        await store.send(.view(.advance)) { $0.beat = .pour }
        await store.send(.view(.back)) { $0.beat = .kind }
    }

    // MARK: The appreciation veil

    func testPartnerAppreciationStaysVeiledUntilMineIsWritten() async {
        var state = partneredState()
        state.isLoading = false
        state.beat = .kind

        let store = TestStore(initialState: state) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.fetch = { PreviewData.resetSummary }
            $0.resetClient.setMyAppreciation = { body, said in
                Appreciation(
                    id: PreviewData.appreciationFromMe.id,
                    fromMemberId: PreviewData.adaId,
                    toMemberId: PreviewData.umutId,
                    body: body,
                    said: said
                )
            }
        }

        await store.send(.view(.appear)) { $0.isLoading = true }
        await store.receive(\.resetLoaded) {
            $0.isLoading = false
            $0.reset = PreviewData.resetSummary
        }

        // Umut's note is loaded, but not readable yet.
        XCTAssertNotNil(store.state.partnerAppreciation)
        XCTAssertFalse(store.state.partnerAppreciationRevealed)

        await store.send(.binding(.set(\.appreciationDraft, "Thank you for the insurance call."))) {
            $0.appreciationDraft = "Thank you for the insurance call."
        }
        await store.send(.view(.saveAppreciationTapped)) { $0.isSavingAppreciation = true }
        await store.receive(\.appreciationSaved) {
            $0.isSavingAppreciation = false
            $0.appreciationSaved = true
            $0.reset?.appreciations = [
                PreviewData.appreciationFromPartner,
                Appreciation(
                    id: PreviewData.appreciationFromMe.id,
                    fromMemberId: PreviewData.adaId,
                    toMemberId: PreviewData.umutId,
                    body: "Thank you for the insurance call.",
                    said: false
                ),
            ]
        }

        XCTAssertTrue(store.state.partnerAppreciationRevealed)
    }

    func testAnAlreadyWrittenAppreciationRevealsOnLoad() async {
        var state = partneredState()
        let both = ResetSummary(
            week: PreviewData.week,
            rows: PreviewData.resetRows,
            biggestCarry: PreviewData.resetSummary.biggestCarry,
            appreciations: [PreviewData.appreciationFromPartner, PreviewData.appreciationFromMe],
            trades: []
        )
        state.beat = .kind

        let store = TestStore(initialState: state) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.fetch = { both }
        }

        await store.send(.view(.appear))
        await store.receive(\.resetLoaded) {
            $0.isLoading = false
            $0.reset = both
            $0.appreciationDraft = PreviewData.appreciationFromMe.body ?? ""
            $0.appreciationSaved = true
        }
        XCTAssertTrue(store.state.partnerAppreciationRevealed)
    }

    func testEmptyAppreciationCannotBeSent() {
        var state = partneredState()
        state.appreciationDraft = "   \n "
        XCTAssertFalse(state.canSaveAppreciation)
        state.appreciationDraft = "You did the bins."
        XCTAssertTrue(state.canSaveAppreciation)
    }

    // MARK: Trades

    func testOnlyTradesPointedAtMeAreOffered() {
        var state = partneredState()
        state.reset = PreviewData.resetSummary
        // The fixture trade hands Ada's vacuum to Umut — Ada cannot accept it.
        XCTAssertTrue(state.pendingTrades(for: PreviewData.ada).isEmpty)
        XCTAssertEqual(state.pendingTrades(for: PreviewData.umut).count, 1)

        state.acceptedTrades.insert(PreviewData.tradeId)
        XCTAssertTrue(state.pendingTrades(for: PreviewData.umut).isEmpty)
    }

    func testAcceptTrade() async {
        var state = partneredState()
        state.isLoading = false
        state.reset = PreviewData.resetSummary
        state.beat = .kind

        let accepted = Trade(
            id: PreviewData.tradeId,
            taskId: PreviewData.pendingTrade.taskId,
            taskTitle: PreviewData.pendingTrade.taskTitle,
            fromMemberId: PreviewData.pendingTrade.fromMemberId,
            toMemberId: PreviewData.pendingTrade.toMemberId,
            accepted: true
        )

        let store = TestStore(initialState: state) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.acceptTrade = { id, isAccepted in
                XCTAssertEqual(id, PreviewData.tradeId)
                XCTAssertTrue(isAccepted)
                return accepted
            }
        }

        await store.send(.view(.acceptTrade(PreviewData.tradeId))) {
            $0.busyTrade = PreviewData.tradeId
        }
        await store.receive(\.tradeAccepted) {
            $0.busyTrade = nil
            $0.acceptedTrades = [PreviewData.tradeId]
        }
    }

    // MARK: The pour

    func testHoldPoursTheWeekOutAndDelegates() async {
        var state = partneredState()
        state.isLoading = false
        state.reset = PreviewData.resetSummary
        state.beat = .pour

        let store = TestStore(initialState: state) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.closeWeek = { weekID in
                // The guard must carry the week we showed, not "whatever is open".
                XCTAssertEqual(weekID, PreviewData.weekId)
                return PreviewData.weekClose
            }
        }

        await store.send(.view(.holdCompleted)) { $0.pour = .pouring }
        await store.receive(\.weekClosed) { $0.pour = .poured }
        await store.receive(\.delegate)
    }

    func testAlreadyClosedWeekIsTreatedAsPoured() async {
        var state = partneredState()
        state.isLoading = false
        state.reset = PreviewData.resetSummary
        state.beat = .pour

        let store = TestStore(initialState: state) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.closeWeek = { _ in
                throw APIError.http(
                    status: 409,
                    code: "week_already_closed",
                    message: "that week was already poured out"
                )
            }
        }

        await store.send(.view(.holdCompleted)) { $0.pour = .pouring }
        // 409 is not a failure — someone already did the thing we wanted done.
        await store.receive(\.weekClosed) { $0.pour = .poured }
        await store.receive(\.delegate.poured)
    }

    func testCloseFailureLetsTheHoldBeRetried() async {
        var state = partneredState()
        state.isLoading = false
        state.reset = PreviewData.resetSummary
        state.beat = .pour

        let attempts = LockIsolated(0)
        let store = TestStore(initialState: state) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.closeWeek = { _ in
                let count = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if count == 1 { throw APIError.transport(URLError(.notConnectedToInternet)) }
                return PreviewData.weekClose
            }
        }

        await store.send(.view(.holdCompleted)) { $0.pour = .pouring }
        await store.receive(\.closeFailed) {
            $0.pour = .failed("Can't reach the house server.")
        }

        await store.send(.view(.holdCompleted)) { $0.pour = .pouring }
        await store.receive(\.weekClosed) { $0.pour = .poured }
        await store.receive(\.delegate)
        XCTAssertEqual(attempts.value, 2)
    }

    func testASecondHoldWhilePouringIsIgnored() async {
        var state = partneredState()
        state.isLoading = false
        state.reset = PreviewData.resetSummary
        state.beat = .pour
        state.pour = .pouring

        let store = TestStore(initialState: state) {
            ResetReducer()
        } withDependencies: {
            $0.resetClient.closeWeek = { _ in
                XCTFail("a second hold must not close a second week")
                return PreviewData.weekClose
            }
        }

        await store.send(.view(.holdCompleted))
    }

    func testDismissDelegates() async {
        let store = TestStore(initialState: partneredState()) { ResetReducer() }
        await store.send(.view(.dismissTapped))
        await store.receive(\.delegate.dismissed)
    }
}
