import XCTest
@testable import AgentTrafficLight

final class AggregatorTests: XCTestCase {
    private func rec(_ id: String, _ state: String, _ pid: Int32, ts: Int = 0) -> SessionRecord {
        SessionRecord(session_id: id, state: state, pid: pid, ts: ts)
    }

    func test_counts_alive_by_state() {
        let recs = [rec("a","working",1), rec("b","done",2), rec("c","waiting",3), rec("d","working",4)]
        let r = aggregate(recs, now: 0, isAlive: { _ in true })
        XCTAssertEqual(r.counts, Counts(working: 2, waiting: 1, done: 1, error: 0))
        XCTAssertEqual(r.idsToDelete, [])
    }

    func test_dead_working_is_error() {
        let r = aggregate([rec("a","working",1)], now: 0, isAlive: { _ in false })
        XCTAssertEqual(r.counts.error, 1)
        XCTAssertEqual(r.counts.working, 0)
        XCTAssertEqual(r.idsToDelete, [])
    }

    func test_dead_done_marked_for_deletion_not_counted() {
        let r = aggregate([rec("a","done",1), rec("b","waiting",2)], now: 0, isAlive: { _ in false })
        XCTAssertEqual(r.counts, Counts(working: 0, waiting: 0, done: 0, error: 0))
        XCTAssertEqual(Set(r.idsToDelete), Set(["a","b"]))
    }

    func test_unknown_state_ignored() {
        let r = aggregate([rec("a","banana",1)], now: 0, isAlive: { _ in true })
        XCTAssertEqual(r.counts, Counts())
    }

    func test_stale_working_dropped_even_if_pid_alive() {
        // ts старее staleAfter → реальная сессия молчит; даже "живой" (переиспользованный) pid не должен считаться 🟢
        let r = aggregate([rec("a","working",1, ts: 0)], now: 10_000, staleAfter: 3600, isAlive: { _ in true })
        XCTAssertEqual(r.counts.working, 0)
        XCTAssertEqual(r.counts.error, 0)
        XCTAssertEqual(r.idsToDelete, ["a"])
    }

    func test_fresh_working_alive_counts() {
        let r = aggregate([rec("a","working",1, ts: 9_900)], now: 10_000, staleAfter: 3600, isAlive: { _ in true })
        XCTAssertEqual(r.counts.working, 1)
        XCTAssertEqual(r.idsToDelete, [])
    }

    func test_label_idle_and_formatting() {
        XCTAssertEqual(labelText(for: Counts()), "💤")
        XCTAssertEqual(labelText(for: Counts(working: 3, waiting: 2, done: 1, error: 1)),
                       "🔴2 🟡1 🟢3 ⚠️1")
    }
}
