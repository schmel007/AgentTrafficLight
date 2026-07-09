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

    func test_stale_done_dropped_even_if_pid_alive() {
        let r = aggregate([rec("a","done",1, ts: 0)], now: 10_000, staleAfter: 3600, isAlive: { _ in true })
        XCTAssertEqual(r.counts.done, 0)
        XCTAssertEqual(r.idsToDelete, ["a"])
        XCTAssertEqual(r.attention, [])
    }

    func test_stale_waiting_dropped_even_if_pid_alive() {
        let r = aggregate([rec("a","waiting",1, ts: 0)], now: 10_000, staleAfter: 3600, isAlive: { _ in true })
        XCTAssertEqual(r.counts.waiting, 0)
        XCTAssertEqual(r.idsToDelete, ["a"])
        XCTAssertEqual(r.attention, [])
    }

    func test_fresh_done_alive_counts() {
        let r = aggregate([rec("a","done",1, ts: 9_900)], now: 10_000, staleAfter: 3600, isAlive: { _ in true })
        XCTAssertEqual(r.counts.done, 1)
        XCTAssertEqual(r.idsToDelete, [])
    }

    func test_ts_exactly_staleAfter_is_kept() {
        // now - ts == staleAfter is not past the strict `>` threshold → still evaluated by state
        let r = aggregate([rec("a","done",1, ts: 6_400)], now: 10_000, staleAfter: 3600, isAlive: { _ in true })
        XCTAssertEqual(r.counts.done, 1)
        XCTAssertEqual(r.idsToDelete, [])
    }

    func test_future_ts_not_dropped() {
        // clock skew: ts ahead of now → negative age, never treated as stale
        let r = aggregate([rec("a","done",1, ts: 20_000)], now: 10_000, staleAfter: 3600, isAlive: { _ in true })
        XCTAssertEqual(r.counts.done, 1)
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

    func test_parseITermTabTitleMap_parsesGuidTitleLines() {
        let output = """
        GUID-A\tOKX session check
        GUID-B\tOKX session check
        GUID-C\tНаведение порядка

        """

        XCTAssertEqual(parseITermTabTitleMap(output), [
            "GUID-A": "OKX session check",
            "GUID-B": "OKX session check",
            "GUID-C": "Наведение порядка"
        ])
    }

    // MARK: visible terminal filter

    func test_filter_drops_every_agent_without_iterm_guid() {
        let recs = [rec("desktop","working",1, agent: "codex", iterm: ""),
                    rec("claude","working",2, agent: "claude", iterm: nil)]
        let r = filterVisibleTerminalRecords(recs)
        XCTAssertEqual(r.kept, [])
        XCTAssertEqual(r.staleIds, ["desktop", "claude"])
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

    func test_filter_keeps_record_from_same_second_as_snapshot() {
        let recs = [rec("racing","done",1, ts: 20, agent: "codex", iterm: "w0:AAAA")]
        let r = filterVisibleTerminalRecords(recs,
                                             liveITermGUIDs: Set(["BBBB"]),
                                             liveITermObservedAt: 20.9)
        XCTAssertEqual(r.kept.map(\.session_id), ["racing"])
        XCTAssertEqual(r.staleIds, [])
    }

    func test_filter_drops_record_from_second_before_snapshot() {
        let recs = [rec("closed","done",1, ts: 19, agent: "codex", iterm: "w0:AAAA")]
        let r = filterVisibleTerminalRecords(recs,
                                             liveITermGUIDs: Set(["BBBB"]),
                                             liveITermObservedAt: 20.9)
        XCTAssertEqual(r.kept, [])
        XCTAssertEqual(r.staleIds, ["closed"])
    }

    func test_defaultStatusDirectory_honors_test_override() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        XCTAssertEqual(defaultStatusDirectory(environment: ["AGENT_TRAFFIC_DIR": "/tmp/status"],
                                              homeDirectory: home).path,
                       "/tmp/status")
        XCTAssertEqual(defaultStatusDirectory(environment: [:], homeDirectory: home).path,
                       "/tmp/home/.claude/agent-traffic")
    }

    func test_isDirectStatusFile_rejects_parentTraversal() {
        let dir = URL(fileURLWithPath: "/tmp/status", isDirectory: true)
        XCTAssertTrue(isDirectStatusFile(dir.appendingPathComponent("safe.json"), in: dir))
        XCTAssertFalse(isDirectStatusFile(dir.appendingPathComponent("../outside.json"), in: dir))
        XCTAssertFalse(isDirectStatusFile(dir.appendingPathComponent("safe.txt"), in: dir))
    }

    func test_statusStore_deletes_enumerated_file_not_sessionId_path() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-signals-storage-\(UUID().uuidString)", isDirectory: true)
        let statusDirectory = root.appendingPathComponent("status", isDirectory: true)
        let outside = root.appendingPathComponent("outside.json")
        let enumerated = statusDirectory.appendingPathComponent("safe.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        let record = SessionRecord(session_id: "../outside",
                                   state: "working",
                                   pid: 1,
                                   ts: Int(Date().timeIntervalSince1970),
                                   agent: "claude",
                                   cwd: "/tmp",
                                   iterm: nil)
        try JSONEncoder().encode(record).write(to: enumerated)

        _ = StatusStore(dir: statusDirectory, startsTimer: false, iTermQueriesEnabled: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: enumerated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_statusStore_ignoresSymbolicLinkRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-signals-symlink-\(UUID().uuidString)", isDirectory: true)
        let statusDirectory = root.appendingPathComponent("status", isDirectory: true)
        let outside = root.appendingPathComponent("outside.json")
        let link = statusDirectory.appendingPathComponent("link.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
        let record = SessionRecord(session_id: "outside",
                                   state: "working",
                                   pid: 1,
                                   ts: Int(Date().timeIntervalSince1970),
                                   agent: "claude",
                                   cwd: "/tmp",
                                   iterm: "w0:AAAA")
        try JSONEncoder().encode(record).write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let store = StatusStore(dir: statusDirectory, startsTimer: false, iTermQueriesEnabled: false)

        XCTAssertEqual(store.diagnostics.decodedRecordCount, 0)
        XCTAssertEqual(store.diagnostics.invalidFileNames, ["link.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_statusStore_ignoresSymbolicLinkStatusDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-signals-directory-link-\(UUID().uuidString)", isDirectory: true)
        let targetDirectory = root.appendingPathComponent("target", isDirectory: true)
        let linkedDirectory = root.appendingPathComponent("status", isDirectory: true)
        let targetRecord = targetDirectory.appendingPathComponent("target.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let record = SessionRecord(session_id: "target",
                                   state: "working",
                                   pid: 1,
                                   ts: Int(Date().timeIntervalSince1970),
                                   agent: "claude",
                                   cwd: "/tmp",
                                   iterm: nil)
        try JSONEncoder().encode(record).write(to: targetRecord)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: targetDirectory)

        let store = StatusStore(dir: linkedDirectory, startsTimer: false, iTermQueriesEnabled: false)

        XCTAssertEqual(store.diagnostics.jsonFileCount, 0)
        XCTAssertEqual(store.diagnostics.decodedRecordCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetRecord.path))
    }

    // MARK: dedupByTab

    func test_dedup_keeps_newest_and_marks_losers_stale() {
        let recs = [rec("old","done",1, ts: 10, iterm: "w0:AAAA"),
                    rec("new","working",2, ts: 20, iterm: "w0:AAAA"),
                    rec("other","done",3, ts: 5, iterm: "w0:BBBB")]
        let r = dedupByTab(recs)
        XCTAssertEqual(r.kept.map(\.session_id).sorted(), ["new","other"])  // freshest per tab + the other tab
        XCTAssertEqual(r.staleIds, ["old"])   // same-tab loser → scheduled for deletion
    }

    func test_dedup_keeps_records_without_guid() {
        let recs = [rec("a","working",1), rec("b","done",2)]   // no iterm
        let r = dedupByTab(recs)
        XCTAssertEqual(r.kept.map(\.session_id).sorted(), ["a","b"])  // records without a GUID are not collapsed
        XCTAssertEqual(r.staleIds, [])
    }

    func test_dedup_never_drops_winner() {
        let recs = [rec("a","working",1, iterm: "w0:AAAA")]
        let r = dedupByTab(recs)
        XCTAssertEqual(r.kept.map(\.session_id), ["a"])
        XCTAssertEqual(r.staleIds, [])   // the only record is the winner, never deleted
    }
}
