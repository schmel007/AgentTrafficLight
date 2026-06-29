import Foundation
import Combine
import Darwin

func pidIsAlive(_ pid: Int32) -> Bool {
    if pid <= 0 { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}

final class StatusStore: ObservableObject {
    @Published var label: String = "💤"
    @Published var attention: [AttentionItem] = []

    private let dir: URL
    private var timer: Timer?

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
        attention = result.attention
    }

    /// Удаляет лежащие файлы мёртвых сессий (снимает зависшие ⚠️).
    func clearErrors() {
        for r in loadRecords() where !pidIsAlive(r.pid) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(r.session_id).json"))
        }
        refresh()
    }

    /// Фокусирует вкладку iTerm по её session id (часть после ":") через osascript.
    func focus(_ item: AttentionItem) {
        guard let iterm = item.iterm,
              let guid = iterm.split(separator: ":").last.map(String.init),
              !guid.isEmpty,
              guid.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return }
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
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
