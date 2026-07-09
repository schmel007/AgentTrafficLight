import Foundation
import Combine
import Darwin
import AppKit

func pidIsAlive(_ pid: Int32) -> Bool {
    if pid <= 0 { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}

final class StatusStore: ObservableObject {
    @Published var label: String = "💤"
    @Published var attention: [AttentionItem] = []
    @Published var diagnostics: DiagnosticsSnapshot = .empty

    private let dir: URL
    private var timer: Timer?

    private var rawAttention: [AttentionItem] = []   // labels = project name (from aggregate)
    private var tabNames: [String: String] = [:]     // iTerm session GUID → displayed title (cosmetic)
    private var liveITermGUIDs: Set<String>? = nil   // nil = iTerm not queried / unavailable
    private var liveITermObservedAt: TimeInterval? = nil
    private var queryingNames = false
    private var lastNamesQuery: TimeInterval = 0
    private var fileURLsBySessionId: [String: [URL]] = [:]
    private let iTermQueriesEnabled: Bool

    init(dir: URL? = nil, startsTimer: Bool = true, iTermQueriesEnabled: Bool = true) {
        self.dir = dir ?? defaultStatusDirectory()
        self.iTermQueriesEnabled = iTermQueriesEnabled
        refresh()
        if startsTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let now = Date().timeIntervalSince1970
        let load = loadRecords()
        let records = load.records
        fileURLsBySessionId = load.fileURLsBySessionId
        let visible = filterVisibleTerminalRecords(records,
                                                   liveITermGUIDs: liveITermGUIDs,
                                                   liveITermObservedAt: liveITermObservedAt)
        deleteFiles(for: visible.staleIds, using: load.fileURLsBySessionId)   // non-iTerm + closed tabs
        let deduped = dedupByTab(visible.kept)   // one row per tab
        deleteFiles(for: deduped.staleIds, using: load.fileURLsBySessionId)   // nested same-tab duplicates
        let result = aggregate(deduped.kept, now: now, isAlive: pidIsAlive)
        deleteFiles(for: result.idsToDelete, using: load.fileURLsBySessionId)   // dead + past TTL
        label = labelText(for: result.counts)
        rawAttention = result.attention
        attention = applyTabNames(rawAttention)
        diagnostics = DiagnosticsSnapshot(
            statusDirectory: dir.path,
            refreshedAt: now,
            jsonFileCount: load.jsonFileCount,
            decodedRecordCount: records.count,
            invalidFileNames: load.invalidFileNames,
            terminalKeptCount: visible.kept.count,
            terminalStaleIds: visible.staleIds,
            dedupedKeptCount: deduped.kept.count,
            dedupStaleIds: deduped.staleIds,
            aggregateDeleteIds: result.idsToDelete,
            counts: result.counts,
            shownItemCount: result.attention.count,
            liveITermGUIDCount: liveITermGUIDs?.count,
            liveITermObservedAt: liveITermObservedAt,
            tabNameCount: tabNames.count
        )
        if iTermQueriesEnabled, !records.isEmpty { maybeRefreshTabNames() }
    }

    /// Dismisses all currently shown rows (🔴/🟡/🟢/⚠️): deletes their files. Active sessions
    /// recreate the file on the next hook event; closed/stuck ones (Codex without SessionEnd) go away.
    func clearShown() {
        deleteFiles(for: attention.map(\.id), using: fileURLsBySessionId)
        refresh()
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsReport(diagnostics), forType: .string)
    }

    func openStatusFolder() {
        NSWorkspace.shared.open(dir)
    }

    /// Focuses the iTerm tab by its session id via osascript.
    func focus(_ item: AttentionItem) {
        guard let guid = itermGUID(item.iterm) else { return }
        let script = """
        tell application "iTerm2"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if id of s is "\(guid)" then
                  select w
                  select t
                  select s
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
        runOsascript(script)
    }

    // MARK: - iTerm tab names and liveness

    private func applyTabNames(_ items: [AttentionItem]) -> [AttentionItem] {
        items.map { item in
            var i = item
            if let guid = itermGUID(item.iterm), let name = tabNames[guid], !name.isEmpty {
                i.label = cleanTabName(name)
            }
            return i
        }
    }

    /// Asynchronously (off the main thread) queries iTerm for tabs, at most once per ~10s.
    private func maybeRefreshTabNames() {
        let now = Date().timeIntervalSince1970
        guard !queryingNames, now - lastNamesQuery > 10 else { return }
        queryingNames = true
        lastNamesQuery = now
        let queryStartedAt = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let map = StatusStore.queryITermTabTitles()
            DispatchQueue.main.async {
                guard let self else { return }
                self.queryingNames = false
                if let map {                       // nil → osascript failed, keep the previous names
                    self.tabNames = map
                    self.liveITermGUIDs = Set(map.keys)
                    self.liveITermObservedAt = queryStartedAt
                    self.refresh()
                }
            }
        }
    }

    /// nil → osascript failed (no permission / iTerm unavailable); an empty dictionary →
    /// iTerm responded but has no open sessions.
    private static func queryITermTabTitles() -> [String: String]? {
        let script = """
        tell application "iTerm2"
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              set tabTitle to title of t
              repeat with s in sessions of t
                set label to tabTitle
                if label is "" then set label to name of s
                set out to out & (id of s) & (character id 9) & label & (character id 10)
              end repeat
            end repeat
          end repeat
          return out
        end tell
        """
        guard let output = runOsascriptCapturing(script) else { return nil }
        return parseITermTabTitleMap(output)
    }

    private func runOsascript(_ script: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    private static func runOsascriptCapturing(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice   // do not buffer stderr → no deadlock
        do { try task.run() } catch { return nil }
        // watchdog: if osascript hangs (Automation dialog / frozen iTerm) — kill it after 5s,
        // otherwise the background thread and the queryingNames flag would be stuck forever
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            if task.isRunning { task.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }   // error / no permission / killed by the watchdog
        return String(data: data, encoding: .utf8)
    }

    private func deleteFiles(for sessionIds: [String], using filesBySessionId: [String: [URL]]) {
        for sessionId in Set(sessionIds) {
            for file in filesBySessionId[sessionId] ?? [] where isDirectStatusFile(file, in: dir) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private struct LoadRecordsResult {
        var records: [SessionRecord]
        var jsonFileCount: Int
        var invalidFileNames: [String]
        var fileURLsBySessionId: [String: [URL]]
    }

    private func loadRecords() -> LoadRecordsResult {
        guard isSafeStatusDirectory(dir) else {
            return LoadRecordsResult(records: [], jsonFileCount: 0, invalidFileNames: [], fileURLsBySessionId: [:])
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return LoadRecordsResult(records: [], jsonFileCount: 0, invalidFileNames: [], fileURLsBySessionId: [:])
        }
        let decoder = JSONDecoder()
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        var records: [SessionRecord] = []
        var invalidFileNames: [String] = []
        var filesBySessionId: [String: [URL]] = [:]
        for file in jsonFiles {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard isDirectStatusFile(file, in: dir),
                  values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(SessionRecord.self, from: data) else {
                invalidFileNames.append(file.lastPathComponent)
                continue
            }
            records.append(record)
            filesBySessionId[record.session_id, default: []].append(file)
        }
        return LoadRecordsResult(records: records,
                                 jsonFileCount: jsonFiles.count,
                                 invalidFileNames: invalidFileNames,
                                 fileURLsBySessionId: filesBySessionId)
    }
}

func defaultStatusDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    if let override = environment["AGENT_TRAFFIC_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    return homeDirectory.appendingPathComponent(".claude/agent-traffic", isDirectory: true)
}

func isDirectStatusFile(_ file: URL, in directory: URL) -> Bool {
    guard file.pathExtension == "json" else { return false }
    return file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
}

func isSafeStatusDirectory(_ directory: URL) -> Bool {
    let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    return values?.isDirectory == true && values?.isSymbolicLink != true
}

func parseITermTabTitleMap(_ output: String) -> [String: String] {
    var map: [String: String] = [:]
    for line in output.split(separator: "\n") {
        let parts = line.split(separator: "\t", maxSplits: 1)
        if parts.count == 2 {
            map[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
    }
    return map
}
