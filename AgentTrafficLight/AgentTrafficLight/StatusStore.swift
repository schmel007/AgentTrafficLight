import Foundation
import Combine
import Darwin

func pidIsAlive(_ pid: Int32) -> Bool {
    if pid <= 0 { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}

/// GUID вкладки iTerm = часть ITERM_SESSION_ID после ":" (совпадает с `id of session`).
private func itermGUID(_ iterm: String?) -> String? {
    guard let g = iterm?.split(separator: ":").last.map(String.init),
          !g.isEmpty,
          g.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
    return g
}

final class StatusStore: ObservableObject {
    @Published var label: String = "💤"
    @Published var attention: [AttentionItem] = []

    private let dir: URL
    private var timer: Timer?

    private var rawAttention: [AttentionItem] = []   // подписи = имя проекта (из aggregate)
    private var tabNames: [String: String] = [:]     // GUID вкладки iTerm → имя
    private var queryingNames = false
    private var lastNamesQuery: TimeInterval = 0

    init(dir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/agent-traffic", isDirectory: true)) {
        self.dir = dir
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let records = loadRecords()
        let result = aggregate(records, now: Date().timeIntervalSince1970, isAlive: pidIsAlive)
        for id in result.idsToDelete {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
        }
        label = labelText(for: result.counts)
        rawAttention = result.attention
        attention = applyTabNames(rawAttention)
        if !result.attention.isEmpty { maybeRefreshTabNames() }
    }

    /// Удаляет лежащие файлы мёртвых сессий (снимает зависшие ⚠️).
    func clearErrors() {
        for r in loadRecords() where !pidIsAlive(r.pid) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(r.session_id).json"))
        }
        refresh()
    }

    /// Фокусирует вкладку iTerm по её session id через osascript.
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

    // MARK: - имена вкладок iTerm

    private func applyTabNames(_ items: [AttentionItem]) -> [AttentionItem] {
        items.map { item in
            var i = item
            if let guid = itermGUID(item.iterm), let name = tabNames[guid], !name.isEmpty {
                i.label = name
            }
            return i
        }
    }

    /// Асинхронно (вне main) опрашивает iTerm о именах вкладок, не чаще раза в ~4с.
    private func maybeRefreshTabNames() {
        let now = Date().timeIntervalSince1970
        guard !queryingNames, now - lastNamesQuery > 4 else { return }
        queryingNames = true
        lastNamesQuery = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let map = StatusStore.queryITermTabNames()
            DispatchQueue.main.async {
                guard let self else { return }
                self.queryingNames = false
                if map != self.tabNames {
                    self.tabNames = map
                    self.attention = self.applyTabNames(self.rawAttention)
                }
            }
        }
    }

    private static func queryITermTabNames() -> [String: String] {
        let script = """
        tell application "iTerm2"
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                set out to out & (id of s) & tab & (name of s) & linefeed
              end repeat
            end repeat
          end repeat
          return out
        end tell
        """
        guard let output = runOsascriptCapturing(script) else { return [:] }
        var map: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 {
                map[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return map
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
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func loadRecords() -> [SessionRecord] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(SessionRecord.self, from: $0) }
    }
}
