import XCTest
@testable import AgentTrafficLight

@MainActor
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

    func test_attention_includes_all_sorted() {
        let recs = [rec("w","working",1), rec("d","done",2, cwd: "/x/proj"), rec("q","waiting",3, cwd: "/y/api")]
        let r = aggregate(recs, now: 0, isAlive: { _ in true })
        XCTAssertEqual(r.attention.map(\.id), ["q","d","w"])         // 🔴, 🟢, 🟡
        XCTAssertEqual(r.attention.map(\.icon), ["🔴","🟢","🟡"])
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
                       "🔴2 🟡3 🟢1 ⚠️1")
    }

    func test_diagnostics_report_includes_pipeline_counts() {
        let snapshot = DiagnosticsSnapshot(
            statusDirectory: "/tmp/agent-traffic",
            refreshedAt: 1,
            jsonFileCount: 4,
            decodedRecordCount: 3,
            invalidFileNames: ["bad.json"],
            terminalKeptCount: 2,
            terminalStaleIds: ["desktop"],
            dedupedKeptCount: 1,
            dedupStaleIds: ["old"],
            aggregateDeleteIds: ["dead"],
            counts: Counts(working: 1),
            shownItemCount: 1,
            liveITermGUIDCount: 2,
            liveITermObservedAt: 1,
            tabNameCount: 2
        )

        let report = diagnosticsReport(snapshot)

        XCTAssertTrue(report.contains("jsonFiles: 4"))
        XCTAssertTrue(report.contains("decodedRecords: 3"))
        XCTAssertTrue(report.contains("invalidFileNames: bad.json"))
        XCTAssertTrue(report.contains("terminalFilter.removedIds: desktop"))
        XCTAssertTrue(report.contains("dedup.removedIds: old"))
        XCTAssertTrue(report.contains("aggregate.removedIds: dead"))
    }

    func test_cleanTabName_strips_badge_and_truncates() {
        XCTAssertEqual(cleanTabName("✳ Проверить", maxLen: 50), "Проверить")
        let t = cleanTabName("Проверить журналы нагрузки MacBook (python)", maxLen: 22)
        XCTAssertLessThanOrEqual(t.count, 22)
        XCTAssertTrue(t.hasSuffix("…"))
        XCTAssertTrue(t.hasPrefix("Проверить"))
        XCTAssertEqual(cleanTabName("Fix bug", maxLen: 22), "Fix bug")
    }

    // MARK: visible terminal filter

    func test_filter_drops_codex_without_iterm_guid() {
        let recs = [rec("desktop","working",1, agent: "codex", iterm: ""),
                    rec("claude","working",2, agent: "claude", iterm: nil)]
        let r = filterVisibleTerminalRecords(recs)
        XCTAssertEqual(r.kept.map(\.session_id), ["claude"])
        XCTAssertEqual(r.staleIds, ["desktop"])
    }

    func test_filter_keeps_guid_records_when_iterm_snapshot_unavailable() {
        let recs = [rec("codex","working",1, ts: 10, agent: "codex", iterm: "w0:AAAA")]
        let r = filterVisibleTerminalRecords(recs, liveITermGUIDs: nil, liveITermObservedAt: nil)
        XCTAssertEqual(r.kept.map(\.session_id), ["codex"])
        XCTAssertEqual(r.staleIds, [])
    }

    func test_filter_drops_old_guid_missing_from_successful_iterm_snapshot() {
        let recs = [rec("closed","working",1, ts: 10, agent: "codex", iterm: "w0:AAAA"),
                    rec("open","done",2, ts: 10, agent: "claude", iterm: "w0:BBBB")]
        let r = filterVisibleTerminalRecords(recs, liveITermGUIDs: Set(["BBBB"]), liveITermObservedAt: 20)
        XCTAssertEqual(r.kept.map(\.session_id), ["open"])
        XCTAssertEqual(r.staleIds, ["closed"])
    }

    func test_filter_keeps_guid_record_newer_than_iterm_snapshot() {
        let recs = [rec("new","working",1, ts: 30, agent: "codex", iterm: "w0:AAAA")]
        let r = filterVisibleTerminalRecords(recs, liveITermGUIDs: Set(["BBBB"]), liveITermObservedAt: 20)
        XCTAssertEqual(r.kept.map(\.session_id), ["new"])
        XCTAssertEqual(r.staleIds, [])
    }

    // MARK: dedupByTab

    func test_dedup_keeps_newest_and_marks_losers_stale() {
        let recs = [rec("old","done",1, ts: 10, iterm: "w0:AAAA"),
                    rec("new","working",2, ts: 20, iterm: "w0:AAAA"),
                    rec("other","done",3, ts: 5, iterm: "w0:BBBB")]
        let r = dedupByTab(recs)
        XCTAssertEqual(r.kept.map(\.session_id).sorted(), ["new","other"])  // свежая на вкладку + другая вкладка
        XCTAssertEqual(r.staleIds, ["old"])   // проигравший той же вкладки → на удаление
    }

    func test_dedup_keeps_records_without_guid() {
        let recs = [rec("a","working",1), rec("b","done",2)]   // нет iterm
        let r = dedupByTab(recs)
        XCTAssertEqual(r.kept.map(\.session_id).sorted(), ["a","b"])  // без GUID не схлопываются
        XCTAssertEqual(r.staleIds, [])
    }

    func test_dedup_never_drops_winner() {
        let recs = [rec("a","working",1, iterm: "w0:AAAA")]
        let r = dedupByTab(recs)
        XCTAssertEqual(r.kept.map(\.session_id), ["a"])
        XCTAssertEqual(r.staleIds, [])   // единственный — победитель, не удаляется
    }
}
