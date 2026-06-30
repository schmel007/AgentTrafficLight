import Foundation

struct SessionRecord: Codable, Equatable {
    let session_id: String
    let state: String
    let pid: Int32
    let ts: Int
    var agent: String? = nil   // "claude" | "codex" (старые файлы → nil → claude)
    var cwd: String? = nil
    var iterm: String? = nil
}

struct Counts: Equatable {
    var working = 0
    var waiting = 0
    var done = 0
    var error = 0
}

/// Одна сессия, требующая внимания (🔴/🟡/⚠️) — строка в выпадающем меню.
struct AttentionItem: Equatable, Identifiable {
    let id: String        // session_id
    let icon: String      // 🔴 | 🟡 | ⚠️
    let agent: String     // Claude | Codex
    var label: String     // имя вкладки iTerm, иначе имя папки проекта (basename cwd)
    let iterm: String?     // ITERM_SESSION_ID для фокуса вкладки, nil если неизвестен
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

/// Сводит записи сессий в счётчики + список требующих внимания.
/// - `working`: `ts` старше `staleAfter` → удалить (закрывает фантом при reuse PID);
///   иначе живой pid → 🟢, мёртвый → ⚠️ (в attention).
/// - `waiting`/`done`: живой pid → счёт + attention; мёртвый → на удаление.
/// 🟢 working в attention НЕ попадают. `now` инъектируется ради тестируемости.
func aggregate(_ records: [SessionRecord],
               now: TimeInterval,
               staleAfter: TimeInterval = 3600,
               isAlive: (Int32) -> Bool) -> AggregationResult {
    var result = AggregationResult()
    for r in records {
        let agent = displayAgent(r.agent)
        let label = displayLabel(r.cwd)
        switch r.state {
        case "working":
            if now - TimeInterval(r.ts) > staleAfter {
                result.idsToDelete.append(r.session_id)
            } else if isAlive(r.pid) {
                result.counts.working += 1
                result.attention.append(AttentionItem(id: r.session_id, icon: "🟢", agent: agent, label: label, iterm: r.iterm))
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
                result.attention.append(AttentionItem(id: r.session_id, icon: "🟡", agent: agent, label: label, iterm: r.iterm))
            } else {
                result.idsToDelete.append(r.session_id)
            }
        default:
            break
        }
    }
    // Детерминированный порядок: 🔴, ⚠️, 🟡, потом 🟢 (working — наименее срочное); внутри — по подписи.
    let rank: (String) -> Int = {
        switch $0 { case "🔴": return 0; case "⚠️": return 1; case "🟡": return 2; default: return 3 }
    }
    result.attention.sort { a, b in
        rank(a.icon) != rank(b.icon) ? rank(a.icon) < rank(b.icon) : (a.label != b.label ? a.label < b.label : a.id < b.id)
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

/// Чистит имя вкладки iTerm для меню: убирает ведущий badge-символ (✳/●/…),
/// обрезает до `maxLen` символов с «…» — чтобы ширина окна была фиксированной.
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

/// GUID вкладки iTerm = часть ITERM_SESSION_ID после ":" (совпадает с `id of session`).
func itermGUID(_ iterm: String?) -> String? {
    guard let g = iterm?.split(separator: ":").last.map(String.init),
          !g.isEmpty,
          g.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
    return g
}

struct DedupResult: Equatable {
    var kept: [SessionRecord] = []
    var staleIds: [String] = []   // проигравшие дедупа той же вкладки (вложенные дубли) — на удаление
}

/// Дедуп: одна запись на GUID вкладки iTerm (свежая по `ts`); записи без GUID — как есть.
/// Проигравшие той же вкладки (вложенные codex-rescue и пр. дубли) идут в `staleIds` на
/// удаление — победитель вкладки ВСЕГДА сохраняется, записи без GUID не трогаются, поэтому
/// «стереть всё» невозможно и нет зависимости от iTerm-запроса (источник прежнего 💤).
func dedupByTab(_ records: [SessionRecord]) -> DedupResult {
    var byTab: [String: SessionRecord] = [:]
    var noGuid: [SessionRecord] = []
    var stale: [String] = []
    for r in records {
        guard let g = itermGUID(r.iterm) else { noGuid.append(r); continue }
        if let cur = byTab[g] {
            if r.ts >= cur.ts {
                stale.append(cur.session_id)   // прежний победитель уступил более свежему
                byTab[g] = r
            } else {
                stale.append(r.session_id)     // текущий проиграл
            }
        } else {
            byTab[g] = r
        }
    }
    return DedupResult(kept: Array(byTab.values) + noGuid, staleIds: stale)
}
