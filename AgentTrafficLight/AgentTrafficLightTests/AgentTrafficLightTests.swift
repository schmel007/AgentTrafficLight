import XCTest
@testable import AgentTrafficLight

final class AggregatorTests: XCTestCase {
    private func rec(_ id: String, _ state: String, _ pid: Int32,
                     ts: Int = 0, agent: String? = nil, cwd: String? = nil, iterm: String? = nil) -> SessionRecord {
        SessionRecord(session_id: id, state: state, pid: pid, ts: ts, agent: agent, cwd: cwd, iterm: iterm)
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
        XCTAssertEqual(r.attention, [])
    }

    func test_unknown_state_ignored() {
        let r = aggregate([rec("a","banana",1)], now: 0, isAlive: { _ in true })
        XCTAssertEqual(r.counts, Counts())
    }

    func test_stale_working_dropped_even_if_pid_alive() {
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

    func test_attention_excludes_working_sorted() {
        let recs = [rec("w","working",1), rec("d","done",2, cwd: "/x/proj"), rec("q","waiting",3, cwd: "/y/api")]
        let r = aggregate(recs, now: 0, isAlive: { _ in true })
        XCTAssertEqual(r.attention.map(\.id), ["q","d"])      // 🔴 раньше 🟡
        XCTAssertEqual(r.attention.map(\.icon), ["🔴","🟡"])
        XCTAssertFalse(r.attention.contains { $0.id == "w" })  // working не в списке
    }

    func test_attention_agent_and_label() {
        let r = aggregate([rec("a","done",1, agent: "codex", cwd: "/Users/x/myproj", iterm: "w0:GUID")],
                          now: 0, isAlive: { _ in true })
        XCTAssertEqual(r.attention.first?.agent, "Codex")
        XCTAssertEqual(r.attention.first?.label, "myproj")
        XCTAssertEqual(r.attention.first?.iterm, "w0:GUID")
    }

    func test_error_in_attention() {
        let r = aggregate([rec("e","working",1, ts: 0)], now: 0, isAlive: { _ in false })
        XCTAssertEqual(r.counts.error, 1)
        XCTAssertEqual(r.attention.map(\.icon), ["⚠️"])
    }

    func test_label_idle_and_formatting() {
        XCTAssertEqual(labelText(for: Counts()), "💤")
        XCTAssertEqual(labelText(for: Counts(working: 3, waiting: 2, done: 1, error: 1)),
                       "🔴2 🟡1 🟢3 ⚠️1")
    }

    // MARK: reconcileByTab

    func test_reconcile_disabled_without_tabdata() {
        let recs = [rec("a","done",1, iterm: "w0:AAAA")]
        let r = reconcileByTab(recs, liveGUIDs: [], hasTabData: false, now: 100)
        XCTAssertEqual(r.kept.map(\.session_id), ["a"])
        XCTAssertEqual(r.deleteIds, [])
    }

    func test_reconcile_drops_closed_tab() {
        let recs = [rec("a","done",1, ts: 0, iterm: "w0:AAAA")]
        let r = reconcileByTab(recs, liveGUIDs: ["BBBB"], hasTabData: true, now: 100, gracePeriod: 6)
        XCTAssertEqual(r.kept, [])
        XCTAssertEqual(r.deleteIds, ["a"])   // age 100 > grace 6 → закрытая вкладка
    }

    func test_reconcile_keeps_new_record_within_grace() {
        let recs = [rec("fresh","working",1, ts: 98, iterm: "w0:AAAA")]   // нет в снапшоте, но свежая
        let r = reconcileByTab(recs, liveGUIDs: ["BBBB"], hasTabData: true, now: 100, gracePeriod: 6)
        XCTAssertEqual(r.kept.map(\.session_id), ["fresh"])   // age 2 < 6 → не удаляем
        XCTAssertEqual(r.deleteIds, [])
    }

    func test_reconcile_default_grace_covers_query_lag() {
        // запись возрастом 9с (худший лаг: throttle ~4с + watchdog ~5с) не должна удаляться при дефолтном grace
        let recs = [rec("x","working",1, ts: 0, iterm: "w0:AAAA")]
        let r = reconcileByTab(recs, liveGUIDs: ["BBBB"], hasTabData: true, now: 9)
        XCTAssertEqual(r.kept.map(\.session_id), ["x"])
        XCTAssertEqual(r.deleteIds, [])
    }

    func test_reconcile_empty_snapshot_is_safe() {
        // снимок «успешен», но пустой → НИЧЕГО не удаляем (предохранитель против массового стирания)
        let recs = [rec("a","done",1, ts: 0, iterm: "w0:AAAA")]
        let r = reconcileByTab(recs, liveGUIDs: [], hasTabData: true, now: 1000)
        XCTAssertEqual(r.kept.map(\.session_id), ["a"])
        XCTAssertEqual(r.deleteIds, [])
    }

    func test_reconcile_dedup_same_tab_keeps_newer() {
        let recs = [rec("old","done",1, ts: 10, iterm: "w0:AAAA"),
                    rec("new","working",2, ts: 20, iterm: "w0:AAAA")]
        let r = reconcileByTab(recs, liveGUIDs: ["AAAA"], hasTabData: true, now: 100, gracePeriod: 6)
        XCTAssertEqual(r.kept.map(\.session_id), ["new"])
        XCTAssertEqual(r.deleteIds, [])      // проигравший по ts не удаляется
    }

    func test_reconcile_keeps_records_without_guid() {
        let recs = [rec("a","working",1)]    // нет iterm
        let r = reconcileByTab(recs, liveGUIDs: ["AAAA"], hasTabData: true, now: 100, gracePeriod: 6)
        XCTAssertEqual(r.kept.map(\.session_id), ["a"])
        XCTAssertEqual(r.deleteIds, [])
    }
}
