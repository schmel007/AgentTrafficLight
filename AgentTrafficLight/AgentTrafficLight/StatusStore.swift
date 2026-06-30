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

    private var rawAttention: [AttentionItem] = []   // подписи = имя проекта (из aggregate)
    private var tabNames: [String: String] = [:]     // GUID вкладки iTerm → имя (косметика)
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
        let deduped = dedupByTab(records)   // одна строка на вкладку
        for id in deduped.staleIds { deleteFile(id) }   // чистим вложенные дубли той же вкладки
        let result = aggregate(deduped.kept, now: Date().timeIntervalSince1970, isAlive: pidIsAlive)
        for id in result.idsToDelete { deleteFile(id) }   // pid-мёртвые done/waiting + working-TTL
        label = labelText(for: result.counts)
        rawAttention = result.attention
        attention = applyTabNames(rawAttention)
        if !records.isEmpty { maybeRefreshTabNames() }
    }

    /// Снимает все показанные сейчас строки (🔴/🟡/⚠️): удаляет их файлы. Активные сессии
    /// пересоздадут файл на следующем событии хука; закрытые/зависшие (Codex без SessionEnd) уйдут.
    func clearShown() {
        for item in attention { deleteFile(item.id) }
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

    // MARK: - имена и живость вкладок iTerm

    private func applyTabNames(_ items: [AttentionItem]) -> [AttentionItem] {
        items.map { item in
            var i = item
            if let guid = itermGUID(item.iterm), let name = tabNames[guid], !name.isEmpty {
                i.label = cleanTabName(name)
            }
            return i
        }
    }

    /// Асинхронно (вне main) опрашивает iTerm о вкладках, не чаще раза в ~4с.
    private func maybeRefreshTabNames() {
        let now = Date().timeIntervalSince1970
        guard !queryingNames, now - lastNamesQuery > 10 else { return }
        queryingNames = true
        lastNamesQuery = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let map = StatusStore.queryITermTabNames()
            DispatchQueue.main.async {
                guard let self else { return }
                self.queryingNames = false
                if let map {                       // nil → osascript не сработал, оставляем прежние имена
                    self.tabNames = map
                    self.attention = self.applyTabNames(self.rawAttention)
                }
            }
        }
    }

    /// nil → osascript не сработал (нет разрешения/iTerm недоступен); пустой словарь →
    /// iTerm ответил, но открытых сессий нет.
    private static func queryITermTabNames() -> [String: String]? {
        let script = """
        tell application "iTerm2"
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                set out to out & (id of s) & (character id 9) & (name of s) & (character id 10)
              end repeat
            end repeat
          end repeat
          return out
        end tell
        """
        guard let output = runOsascriptCapturing(script) else { return nil }
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
        task.standardError = FileHandle.nullDevice   // не копим stderr → нет deadlock
        do { try task.run() } catch { return nil }
        // сторож: если osascript завис (диалог Automation / зависание iTerm) — убить через 5с,
        // иначе фоновый поток и флаг queryingNames застрянут навсегда
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            if task.isRunning { task.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }   // ошибка/нет разрешения/убит сторожем
        return String(data: data, encoding: .utf8)
    }

    private func deleteFile(_ sessionId: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(sessionId).json"))
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
