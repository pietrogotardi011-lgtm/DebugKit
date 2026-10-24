import Foundation

enum LogStore {
    private static let key = "debug_log_entries"
    private static let timersKey = "debug_timers"
    private static let lapsKey = "debug_laps"
    private static let statsKey = "debug_run_stats"
    private static let ctxKey = "debug_context"
    private static let groupKey = "debug_group"
    private static let retriesKey = "debug_retries"
    private static let limitKey = "debug_limit"
    private static let expireKey = "debug_expire_days"
    private static let lock = NSLock()
    static let exportBase = "DebugKit-log"

    // MARK: settings
    static var maxEntries: Int {
        get { let v = UserDefaults.standard.integer(forKey: limitKey); return v > 0 ? v : 1000 }
        set { UserDefaults.standard.set(max(newValue, 50), forKey: limitKey) }
    }

    static var expireDays: Int {
        get { UserDefaults.standard.integer(forKey: expireKey) }
        set { UserDefaults.standard.set(max(newValue, 0), forKey: expireKey) }
    }

    // MARK: log
    static func load() -> [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return loadUnlocked()
    }

    private static func loadUnlocked() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else { return [] }
        return entries
    }

    private static func saveUnlocked(_ entries: [LogEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func append(label: String, message: String, level: LogLevel = .info) {
        let ctx = currentContextTag()
        let grp = currentGroup()
        lock.lock(); defer { lock.unlock() }
        var entries = loadUnlocked()
        entries.append(LogEntry(date: Date(), label: label, message: message, level: level, context: ctx, group: grp))
        let days = expireDays
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            entries.removeAll { $0.date < cutoff && !($0.pinned ?? false) }
        }
        let limit = maxEntries
        while entries.count > limit, let idx = entries.firstIndex(where: { !($0.pinned ?? false) }) {
            entries.remove(at: idx)
        }
        saveUnlocked(entries)
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func togglePin(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var entries = loadUnlocked()
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].pinned = !(entries[i].pinned ?? false)
            saveUnlocked(entries)
        }
    }

    /// Removes entries older than `days` (pinned entries are kept). Returns how many were removed.
    static func expire(days: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        var entries = loadUnlocked()
        let before = entries.count
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        entries.removeAll { $0.date < cutoff && !($0.pinned ?? false) }
        saveUnlocked(entries)
        return before - entries.count
    }

    static func filtered(last n: Int, minLevel: LogLevel? = nil, contains q: String? = nil) -> [LogEntry] {
        var e = load()
        if let m = minLevel { e = e.filter { ($0.level ?? .info).rank >= m.rank } }
        if let q = q, !q.isEmpty {
            let ql = q.lowercased()
            e = e.filter {
                $0.message.lowercased().contains(ql)
                    || $0.label.lowercased().contains(ql)
                    || ($0.context ?? "").lowercased().contains(ql)
                    || ($0.group ?? "").lowercased().contains(ql)
            }
        }
        return Array(e.suffix(max(n, 1)))
    }

    static func format(_ entries: [LogEntry]) -> String {
        if entries.isEmpty { return "(log is empty)" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { e in
            let lvl = (e.level ?? .info).rawValue.uppercased()
            let ctx = e.context.map { " [\($0)]" } ?? ""
            let grp = e.group.map { " {\($0)}" } ?? ""
            return "[\(f.string(from: e.date))] [\(lvl)]\(ctx)\(grp) [\(e.label)] \(e.message)"
        }.joined(separator: "\n")
    }

    static func json(_ entries: [LogEntry]) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(entries), let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }

    static func csv(_ entries: [LogEntry]) -> String {
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let iso = ISO8601DateFormatter()
        var lines = ["time,level,label,run,group,message"]
        for e in entries {
            lines.append([iso.string(from: e.date), (e.level ?? .info).rawValue, esc(e.label),
                          esc(e.context ?? ""), esc(e.group ?? ""), esc(e.message)].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func export(_ entries: [LogEntry], as f: ExportFormat) -> String {
        switch f {
        case .text: return format(entries)
        case .json: return json(entries)
        case .csv: return csv(entries)
        }
    }

    static func text(last n: Int, minLevel: LogLevel? = nil, contains q: String? = nil) -> String {
        format(filtered(last: n, minLevel: minLevel, contains: q))
    }

    static func exportToDocuments(_ f: ExportFormat) throws -> (data: Data, name: String) {
        let name = "\(exportBase).\(f.ext)"
        let data = Data(export(load(), as: f).utf8)
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        return (data, name)
    }

    // MARK: run context and trace
    static func startRun(name: String, trace: Bool) -> String {
        let id = String(UUID().uuidString.prefix(4))
        let c: [String: String] = ["name": name, "id": id, "start": String(Date().timeIntervalSince1970),
                                   "trace": trace ? "1" : "0", "step": "0"]
        UserDefaults.standard.set(c, forKey: ctxKey)
        return id
    }

    static func currentContextTag() -> String? {
        guard let c = UserDefaults.standard.dictionary(forKey: ctxKey) as? [String: String],
              let n = c["name"], let i = c["id"] else { return nil }
        return "\(n)#\(i)"
    }

    static func endRun() -> (tag: String, seconds: Double, steps: Int)? {
        guard let tag = currentContextTag(),
              let c = UserDefaults.standard.dictionary(forKey: ctxKey) as? [String: String],
              let start = Double(c["start"] ?? "") else { return nil }
        let steps = Int(c["step"] ?? "0") ?? 0
        UserDefaults.standard.removeObject(forKey: ctxKey)
        UserDefaults.standard.removeObject(forKey: groupKey)
        return (tag, Date().timeIntervalSince1970 - start, steps)
    }

    /// With Trace Mode on, logs "step N: <action>" so you can see how far a shortcut got.
    static func step(_ name: String) {
        guard var c = UserDefaults.standard.dictionary(forKey: ctxKey) as? [String: String],
              c["trace"] == "1" else { return }
        let n = (Int(c["step"] ?? "0") ?? 0) + 1
        c["step"] = String(n)
        UserDefaults.standard.set(c, forKey: ctxKey)
        append(label: "TRACE", message: "step \(n): \(name)", level: .info)
    }

    // MARK: groups
    static func startGroup(_ name: String) { UserDefaults.standard.set(name, forKey: groupKey) }
    static func currentGroup() -> String? { UserDefaults.standard.string(forKey: groupKey) }
    static func endGroup() -> String? {
        let g = currentGroup()
        UserDefaults.standard.removeObject(forKey: groupKey)
        return g
    }

    // MARK: runs overview
    static func runs() -> [RunSummary] {
        var map: [String: [LogEntry]] = [:]
        for e in load() { if let c = e.context { map[c, default: []].append(e) } }
        return map.map { tag, es in
            RunSummary(tag: tag, count: es.count,
                       errors: es.filter { ($0.level ?? .info) == .error }.count,
                       warnings: es.filter { ($0.level ?? .info) == .warning }.count,
                       start: es.map(\.date).min() ?? Date(), end: es.map(\.date).max() ?? Date())
        }.sorted { $0.end > $1.end }
    }

    static func entries(forRun tag: String) -> [LogEntry] {
        load().filter { $0.context == tag }
    }

    // MARK: timers and laps
    static func startTimer(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        var t = UserDefaults.standard.dictionary(forKey: timersKey) as? [String: Double] ?? [:]
        var l = UserDefaults.standard.dictionary(forKey: lapsKey) as? [String: Double] ?? [:]
        t[name] = Date().timeIntervalSince1970
        l.removeValue(forKey: name)
        UserDefaults.standard.set(t, forKey: timersKey)
        UserDefaults.standard.set(l, forKey: lapsKey)
    }

    static func stopTimer(_ name: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        var t = UserDefaults.standard.dictionary(forKey: timersKey) as? [String: Double] ?? [:]
        var l = UserDefaults.standard.dictionary(forKey: lapsKey) as? [String: Double] ?? [:]
        guard let start = t.removeValue(forKey: name) else { return nil }
        l.removeValue(forKey: name)
        UserDefaults.standard.set(t, forKey: timersKey)
        UserDefaults.standard.set(l, forKey: lapsKey)
        return Date().timeIntervalSince1970 - start
    }

    static func lap(_ name: String) -> (total: Double, split: Double)? {
        lock.lock(); defer { lock.unlock() }
        let t = UserDefaults.standard.dictionary(forKey: timersKey) as? [String: Double] ?? [:]
        var l = UserDefaults.standard.dictionary(forKey: lapsKey) as? [String: Double] ?? [:]
        guard let start = t[name] else { return nil }
        let now = Date().timeIntervalSince1970
        let last = l[name] ?? start
        l[name] = now
        UserDefaults.standard.set(l, forKey: lapsKey)
        return (now - start, now - last)
    }

    // MARK: run counters
    static func allStats() -> [String: RunStat] {
        guard let data = UserDefaults.standard.data(forKey: statsKey),
              let s = try? JSONDecoder().decode([String: RunStat].self, from: data) else { return [:] }
        return s
    }

    static func countRun(_ name: String, failed: Bool) -> RunStat {
        lock.lock(); defer { lock.unlock() }
        var all = allStats()
        var s = all[name] ?? RunStat()
        s.runs += 1
        if failed { s.fails += 1 }
        s.last = Date()
        all[name] = s
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
        return s
    }

    static func clearStats() {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: statsKey)
    }

    static func statsText() -> String {
        let all = allStats()
        if all.isEmpty { return "(no run counters yet)" }
        return all.sorted { $0.value.fails > $1.value.fails }
            .map { "\($0.key): \($0.value.runs) runs, \($0.value.fails) failed" }
            .joined(separator: "\n")
    }

    // MARK: retry counters
    static func retry(_ name: String, reset: Bool) -> Int {
        lock.lock(); defer { lock.unlock() }
        var r = UserDefaults.standard.dictionary(forKey: retriesKey) as? [String: Int] ?? [:]
        let n = reset ? 0 : (r[name] ?? 0) + 1
        r[name] = n
        UserDefaults.standard.set(r, forKey: retriesKey)
        return n
    }

    // MARK: maintenance
    static func clearEverything() {
        for k in [key, timersKey, lapsKey, statsKey, ctxKey, groupKey, retriesKey] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    static func storageWorks() -> Bool {
        let k = "debug_selftest"
        let token = UUID().uuidString
        UserDefaults.standard.set(token, forKey: k)
        let ok = UserDefaults.standard.string(forKey: k) == token
        UserDefaults.standard.removeObject(forKey: k)
        return ok
    }
}
