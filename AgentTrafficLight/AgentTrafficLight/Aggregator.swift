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

/// Сводит записи сессий в счётчики. Мёртвый pid + working = ошибка;
/// мёртвый pid + done/waiting = штатно закрытая сессия (на удаление).
func aggregate(_ records: [SessionRecord], isAlive: (Int32) -> Bool) -> AggregationResult {
    var result = AggregationResult()
    for r in records {
        if isAlive(r.pid) {
            switch r.state {
            case "working": result.counts.working += 1
            case "waiting": result.counts.waiting += 1
            case "done":    result.counts.done += 1
            default:        break
            }
        } else if r.state == "working" {
            result.counts.error += 1
        } else {
            result.idsToDelete.append(r.session_id)
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
