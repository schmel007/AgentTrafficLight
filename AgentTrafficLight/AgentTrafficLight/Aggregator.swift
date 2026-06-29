import Foundation

struct SessionRecord: Codable, Equatable {
    let session_id: String
    let state: String
    let pid: Int32
    let ts: Int
}

struct Counts: Equatable {
    var working = 0
    var waiting = 0
    var done = 0
    var error = 0
}

struct AggregationResult: Equatable {
    var counts = Counts()
    var idsToDelete: [String] = []
}

/// Сводит записи сессий в счётчики.
/// - `working`: если `ts` не обновлялся дольше `staleAfter` — сессия давно молчит,
///   запись удаляется (закрывает фантомный 🟢 при переиспользовании PID); иначе
///   живой pid → 🟢, мёртвый → ⚠️.
/// - `done`/`waiting`: живой pid → счёт; мёртвый → штатно закрыта, на удаление.
/// `now` инъектируется ради чистоты/тестируемости.
func aggregate(_ records: [SessionRecord],
               now: TimeInterval,
               staleAfter: TimeInterval = 3600,
               isAlive: (Int32) -> Bool) -> AggregationResult {
    var result = AggregationResult()
    for r in records {
        switch r.state {
        case "working":
            if now - TimeInterval(r.ts) > staleAfter {
                result.idsToDelete.append(r.session_id)
            } else if isAlive(r.pid) {
                result.counts.working += 1
            } else {
                result.counts.error += 1
            }
        case "waiting":
            if isAlive(r.pid) { result.counts.waiting += 1 } else { result.idsToDelete.append(r.session_id) }
        case "done":
            if isAlive(r.pid) { result.counts.done += 1 } else { result.idsToDelete.append(r.session_id) }
        default:
            break
        }
    }
    return result
}

func labelText(for c: Counts) -> String {
    var parts: [String] = []
    if c.waiting > 0 { parts.append("🔴\(c.waiting)") }
    if c.done > 0    { parts.append("🟡\(c.done)") }
    if c.working > 0 { parts.append("🟢\(c.working)") }
    if c.error > 0   { parts.append("⚠️\(c.error)") }
    return parts.isEmpty ? "💤" : parts.joined(separator: " ")
}

func summaryLines(for c: Counts) -> [String] {
    ["🔴 ждут ввода: \(c.waiting)",
     "🟡 готовы (мой ход): \(c.done)",
     "🟢 работают: \(c.working)",
     "⚠️ ошибки: \(c.error)"]
}
