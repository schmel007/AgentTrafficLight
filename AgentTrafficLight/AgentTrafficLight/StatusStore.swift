import Foundation
import Combine
import Darwin

func pidIsAlive(_ pid: Int32) -> Bool {
    if pid <= 0 { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}

final class StatusStore: ObservableObject {
    @Published var label: String = "💤"
    @Published var lines: [String] = summaryLines(for: Counts())

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

    func refresh() {
        let records = loadRecords()
        let result = aggregate(records, isAlive: pidIsAlive)
        for id in result.idsToDelete {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
        }
        label = labelText(for: result.counts)
        lines = summaryLines(for: result.counts)
    }

    deinit {
        timer?.invalidate()
    }

    /// Удаляет лежащие файлы мёртвых сессий (снимает зависшие ⚠️).
    func clearErrors() {
        for r in loadRecords() where !pidIsAlive(r.pid) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(r.session_id).json"))
        }
        refresh()
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
