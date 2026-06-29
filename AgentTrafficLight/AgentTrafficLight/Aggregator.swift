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
    // Детерминированный порядок: сначала 🔴, потом ⚠️, потом 🟡; внутри — по подписи.
    let rank: (String) -> Int = { $0 == "🔴" ? 0 : ($0 == "⚠️" ? 1 : 2) }
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

/// GUID вкладки iTerm = часть ITERM_SESSION_ID после ":" (совпадает с `id of session`).
func itermGUID(_ iterm: String?) -> String? {
    guard let g = iterm?.split(separator: ":").last.map(String.init),
          !g.isEmpty,
          g.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
    return g
}

struct TabReconcileResult: Equatable {
    var kept: [SessionRecord] = []
    var deleteIds: [String] = []
}

/// Сводит записи к модели «одна запись = одна открытая вкладка iTerm».
/// - запись с GUID закрытой вкладки → на удаление (чистка Codex без SessionEnd);
/// - несколько записей одной живой вкладки → оставить свежую по `ts` (проигравшие
///   просто исключаются из показа, файлы не трогаем — уйдут при закрытии вкладки);
/// - запись без GUID → пропускается как есть (дальше решает pid-живость).
/// Если снимка вкладок нет (`hasTabData == false`, iTerm не виден/нет разрешения) —
/// ничего не фильтруем, откат на pid-поведение.
/// `gracePeriod`: запись с GUID не в снапшоте, но свежее grace, НЕ удаляется — снапшот
/// мог отстать от только что открытой вкладки. Дефолт 12с с запасом покрывает худший лаг:
/// throttle опроса (~4с) + время osascript до watchdog (до 5с).
func reconcileByTab(_ records: [SessionRecord], liveGUIDs: Set<String>, hasTabData: Bool,
                    now: TimeInterval, gracePeriod: TimeInterval = 12) -> TabReconcileResult {
    guard hasTabData else { return TabReconcileResult(kept: records, deleteIds: []) }
    var result = TabReconcileResult()
    var byTab: [String: SessionRecord] = [:]
    for r in records {
        guard let g = itermGUID(r.iterm) else { result.kept.append(r); continue }
        if !liveGUIDs.contains(g) {
            if now - TimeInterval(r.ts) > gracePeriod {
                result.deleteIds.append(r.session_id)   // вкладка закрыта
            } else {
                result.kept.append(r)                    // слишком свежая — снапшот мог отстать
            }
            continue
        }
        if let cur = byTab[g] {
            if r.ts >= cur.ts { byTab[g] = r }
        } else {
            byTab[g] = r
        }
    }
    result.kept.append(contentsOf: byTab.values)
    return result
}
