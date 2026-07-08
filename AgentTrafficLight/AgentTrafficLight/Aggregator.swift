import Foundation

struct SessionRecord: Codable, Equatable {
    let session_id: String
    let state: String
    let pid: Int32
    let ts: Int
    var agent: String? = nil   // "claude" | "codex" (legacy files → nil → claude)
    var cwd: String? = nil
    var iterm: String? = nil
}

struct Counts: Equatable {
    var working = 0
    var waiting = 0
    var done = 0
    var error = 0
}

struct DiagnosticsSnapshot: Equatable {
    var statusDirectory: String = ""
    var refreshedAt: TimeInterval = 0
    var jsonFileCount = 0
    var decodedRecordCount = 0
    var invalidFileNames: [String] = []
    var terminalKeptCount = 0
    var terminalStaleIds: [String] = []
    var dedupedKeptCount = 0
    var dedupStaleIds: [String] = []
    var aggregateDeleteIds: [String] = []
    var counts = Counts()
    var shownItemCount = 0
    var liveITermGUIDCount: Int? = nil
    var liveITermObservedAt: TimeInterval? = nil
    var tabNameCount = 0

    var removedCount: Int {
        terminalStaleIds.count + dedupStaleIds.count + aggregateDeleteIds.count
    }

    static let empty = DiagnosticsSnapshot()
}

/// One active session — a row in the dropdown menu.
struct AttentionItem: Equatable, Identifiable {
    let id: String        // session_id
    let icon: String      // 🔴 | 🟡 | 🟢 | ⚠️
    let agent: String     // Claude | Codex
    var label: String     // iTerm tab name, else project folder name (basename of cwd)
    let iterm: String?     // ITERM_SESSION_ID for focusing the tab, nil if unknown
}

struct AggregationResult: Equatable {
    var counts = Counts()
    var idsToDelete: [String] = []
    var attention: [AttentionItem] = []
}

private func displayAgent(_ raw: String?) -> String {
    switch raw {
    case "codex": return "Codex"
    default:      return "Claude"
    }
}

private func displayLabel(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "?" }
    return (cwd as NSString).lastPathComponent
}

/// Reduces session records into counters + the attention list.
/// - Any record with `ts` older than `staleAfter` → delete, regardless of state. A stale `ts`
///   means the `pid` is no longer a trustworthy liveness proxy: the agent process may have
///   exited and its pid been reused, or the hook recorded a shared long-lived Claude Code
///   process (e.g. a background spare) that outlives the session. This closes the phantom
///   where a finished/waiting session lingers because an unrelated pid stays alive.
/// - `working`: live pid → 🟡, dead → ⚠️.
/// - `waiting`/`done`: live pid → count + attention; dead → scheduled for deletion.
/// `now` is injected for testability.
func aggregate(_ records: [SessionRecord],
               now: TimeInterval,
               staleAfter: TimeInterval = 3600,
               isAlive: (Int32) -> Bool) -> AggregationResult {
    var result = AggregationResult()
    for r in records {
        let agent = displayAgent(r.agent)
        let label = displayLabel(r.cwd)
        if now - TimeInterval(r.ts) > staleAfter {
            result.idsToDelete.append(r.session_id)
            continue
        }
        switch r.state {
        case "working":
            if isAlive(r.pid) {
                result.counts.working += 1
                result.attention.append(AttentionItem(id: r.session_id, icon: "🟡", agent: agent, label: label, iterm: r.iterm))
            } else {
                result.counts.error += 1
                result.attention.append(AttentionItem(id: r.session_id, icon: "⚠️", agent: agent, label: label, iterm: r.iterm))
            }
        case "waiting":
            if isAlive(r.pid) {
                result.counts.waiting += 1
                result.attention.append(AttentionItem(id: r.session_id, icon: "🔴", agent: agent, label: label, iterm: r.iterm))
            } else {
                result.idsToDelete.append(r.session_id)
            }
        case "done":
            if isAlive(r.pid) {
                result.counts.done += 1
                result.attention.append(AttentionItem(id: r.session_id, icon: "🟢", agent: agent, label: label, iterm: r.iterm))
            } else {
                result.idsToDelete.append(r.session_id)
            }
        default:
            break
        }
    }
    // Deterministic order: 🔴, ⚠️, 🟢 (done), then 🟡 (working); ties break by label.
    let rank: (String) -> Int = {
        switch $0 { case "🔴": return 0; case "⚠️": return 1; case "🟢": return 2; default: return 3 }
    }
    result.attention.sort { a, b in
        rank(a.icon) != rank(b.icon) ? rank(a.icon) < rank(b.icon) : (a.label != b.label ? a.label < b.label : a.id < b.id)
    }
    return result
}

func labelText(for c: Counts) -> String {
    var parts: [String] = []
    if c.waiting > 0 { parts.append("🔴\(c.waiting)") }
    if c.working > 0 { parts.append("🟡\(c.working)") }
    if c.done > 0    { parts.append("🟢\(c.done)") }
    if c.error > 0   { parts.append("⚠️\(c.error)") }
    return parts.isEmpty ? "💤" : parts.joined(separator: " ")
}

func diagnosticsReport(_ snapshot: DiagnosticsSnapshot) -> String {
    [
        "Agent Signals Diagnostics",
        "refreshedAt: \(diagnosticsTimestamp(snapshot.refreshedAt))",
        "statusDirectory: \(snapshot.statusDirectory)",
        "label: \(labelText(for: snapshot.counts))",
        "jsonFiles: \(snapshot.jsonFileCount)",
        "decodedRecords: \(snapshot.decodedRecordCount)",
        "invalidFiles: \(snapshot.invalidFileNames.count)",
        "terminalFilter.kept: \(snapshot.terminalKeptCount)",
        "terminalFilter.removed: \(snapshot.terminalStaleIds.count)",
        "dedup.kept: \(snapshot.dedupedKeptCount)",
        "dedup.removed: \(snapshot.dedupStaleIds.count)",
        "aggregate.removed: \(snapshot.aggregateDeleteIds.count)",
        "shownItems: \(snapshot.shownItemCount)",
        "iTerm.liveGUIDs: \(snapshot.liveITermGUIDCount.map(String.init) ?? "unknown")",
        "iTerm.observedAt: \(diagnosticsTimestamp(snapshot.liveITermObservedAt))",
        "iTerm.tabNames: \(snapshot.tabNameCount)",
        "invalidFileNames: \(diagnosticsList(snapshot.invalidFileNames))",
        "terminalFilter.removedIds: \(diagnosticsList(snapshot.terminalStaleIds))",
        "dedup.removedIds: \(diagnosticsList(snapshot.dedupStaleIds))",
        "aggregate.removedIds: \(diagnosticsList(snapshot.aggregateDeleteIds))"
    ].joined(separator: "\n")
}

private func diagnosticsTimestamp(_ value: TimeInterval?) -> String {
    guard let value, value > 0 else { return "unknown" }
    return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: value))
}

private func diagnosticsList(_ values: [String]) -> String {
    values.isEmpty ? "-" : values.sorted().joined(separator: ", ")
}

/// Cleans an iTerm tab name for the menu: strips the leading badge symbol (✳/●/…),
/// truncates to `maxLen` characters with "…" so the menu width stays fixed.
func cleanTabName(_ raw: String, maxLen: Int = 22) -> String {
    var s = raw.trimmingCharacters(in: .whitespaces)
    if let firstAlnum = s.firstIndex(where: { $0.isLetter || $0.isNumber }) {
        s = String(s[firstAlnum...])
    }
    if s.count > maxLen {
        s = String(s.prefix(maxLen - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
    return s
}

/// iTerm tab GUID = the part of ITERM_SESSION_ID after ":" (matches `id of session`).
func itermGUID(_ iterm: String?) -> String? {
    guard let g = iterm?.split(separator: ":").last.map(String.init),
          !g.isEmpty,
          g.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
    return g
}

struct DedupResult: Equatable {
    var kept: [SessionRecord] = []
    var staleIds: [String] = []   // same-tab dedup losers (nested duplicates) — scheduled for deletion
}

struct TerminalFilterResult: Equatable {
    var kept: [SessionRecord] = []
    var staleIds: [String] = []   // records that do not match any visible iTerm tab
}

/// Filter for the app's contract surface: the indicator counts iTerm tabs only.
/// - Codex without a GUID is Codex Desktop / a non-iTerm context and must be removed.
/// - If iTerm successfully returned the GUID list, older records with a missing GUID are
///   treated as closed tabs. Records newer than the snapshot are kept until the next snapshot.
func filterVisibleTerminalRecords(_ records: [SessionRecord],
                                  liveITermGUIDs: Set<String>? = nil,
                                  liveITermObservedAt: TimeInterval? = nil) -> TerminalFilterResult {
    var result = TerminalFilterResult()
    for r in records {
        let guid = itermGUID(r.iterm)
        if r.agent == "codex", guid == nil {
            result.staleIds.append(r.session_id)
        } else if let liveITermGUIDs,
                  let liveITermObservedAt,
                  let guid,
                  TimeInterval(r.ts) <= liveITermObservedAt,
                  !liveITermGUIDs.contains(guid) {
            result.staleIds.append(r.session_id)
        } else {
            result.kept.append(r)
        }
    }
    return result
}

/// Dedup: one record per iTerm tab GUID (freshest by `ts`); records without a GUID pass through.
/// Same-tab losers (nested codex-rescue runs and other duplicates) go to `staleIds` for
/// deletion — the tab winner is ALWAYS kept, records without a GUID are left untouched.
func dedupByTab(_ records: [SessionRecord]) -> DedupResult {
    var byTab: [String: SessionRecord] = [:]
    var noGuid: [SessionRecord] = []
    var stale: [String] = []
    for r in records {
        guard let g = itermGUID(r.iterm) else { noGuid.append(r); continue }
        if let cur = byTab[g] {
            if r.ts >= cur.ts {
                stale.append(cur.session_id)   // previous winner lost to a fresher record
                byTab[g] = r
            } else {
                stale.append(r.session_id)     // current record lost
            }
        } else {
            byTab[g] = r
        }
    }
    return DedupResult(kept: Array(byTab.values) + noGuid, staleIds: stale)
}
