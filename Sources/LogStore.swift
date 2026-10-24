import Foundation

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var label: String
    var message: String
}

struct DebugError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

enum LogStore {
    private static let key = "debug_log_entries"
    private static let timersKey = "debug_timers"
    private static let lock = NSLock()
    private static let maxEntries = 500

    static func load() -> [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return loadUnlocked()
    }

    private static func loadUnlocked() -> [LogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else { return [] }
        return entries
    }

    static func append(label: String, message: String) {
        lock.lock(); defer { lock.unlock() }
        var entries = loadUnlocked()
        entries.append(LogEntry(date: Date(), label: label, message: message))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func text(last n: Int) -> String {
        let entries = load().suffix(max(n, 1))
        if entries.isEmpty { return "(log is empty)" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { "[\(f.string(from: $0.date))] [\($0.label)] \($0.message)" }
            .joined(separator: "\n")
    }

    // MARK: timers
    static func startTimer(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        var t = UserDefaults.standard.dictionary(forKey: timersKey) as? [String: Double] ?? [:]
        t[name] = Date().timeIntervalSince1970
        UserDefaults.standard.set(t, forKey: timersKey)
    }

    static func stopTimer(_ name: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        var t = UserDefaults.standard.dictionary(forKey: timersKey) as? [String: Double] ?? [:]
        guard let start = t.removeValue(forKey: name) else { return nil }
        UserDefaults.standard.set(t, forKey: timersKey)
        return Date().timeIntervalSince1970 - start
    }
}
