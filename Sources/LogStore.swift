import Foundation

enum LogStore {
    private static let key = "debug_log_entries"
    private static let timersKey = "debug_timers"
    private static let lapsKey = "debug_laps"
    private static let statsKey = "debug_run_stats"
    private static let ctxKey = "debug_context"
    private static let lock = NSLock()
    private static let maxEntries = 1000
    static let exportName = "DebugKit-log.txt"

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

    static func append(label: String, message: String, level: LogLevel = .info) {
        let ctx = currentContextTag()
        lock.lock(); defer { lock.unlock() }
        var entries = loadUnlocked()
        entries.append(LogEntry(date: Date(), label: label, message: message, level: level, context: ctx))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: key)
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
            return "[\(f.string(from: e.date))] [\(lvl)]\(ctx) [\(e.label)] \(e.message)"
        }.joined(separator: "\n")
    }

    static func text(last n: Int, minLevel: LogLevel? = nil, contains q: String? = nil) -> String {
        format(filtered(last: n, minLevel: minLevel, contains: q))
    }

    static func exportToDocuments() throws -> Data {
        let all = format(load())
        let data = Data(all.utf8)
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try data.write(to: dir.appendingPathComponent(exportName), options: .atomic)
        }
        return data
    }

    // MARK: run context
    static func startRun(name: String) -> String {
        let id = String(UUID().uuidString.prefix(4))
        let c: [String: String] = ["name": name, "id": id, "start": String(Date().timeIntervalSince1970)]
        UserDefaults.standard.set(c, forKey: ctxKey)
        return id
    }

    static func currentContextTag() -> String? {
        guard let c = UserDefaults.standard.dictionary(forKey: ctxKey) as? [String: String],
              let n = c["name"], let i = c["id"] else { return nil }
        return "\(n)#\(i)"
    }

    static func endRun() -> (tag: String, seconds: Double)? {
        guard let tag = currentContextTag(),
              let c = UserDefaults.standard.dictionary(forKey: ctxKey) as? [String: String],
              let start = Double(c["start"] ?? "") else { return nil }
        UserDefaults.standard.removeObject(forKey: ctxKey)
        return (tag, Date().timeIntervalSince1970 - start)
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
}
