import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - Logging

struct LogMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Debug Message"
    static let description = IntentDescription("Adds a timestamped message to the DebugKit log.")

    @Parameter(title: "Message") var message: String
    @Parameter(title: "Label", default: "Shortcut") var label: String
    @Parameter(title: "Level", default: .info) var level: LogLevel

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$message) as \(\.$label)") {
            \.$level
        }
    }

    func perform() async throws -> some IntentResult {
        LogStore.append(label: label, message: message, level: level)
        return .result()
    }
}

struct LogVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Variables"
    static let description = IntentDescription("Logs several values in a single entry, separated by ' | '.")

    @Parameter(title: "Values") var values: [String]
    @Parameter(title: "Label", default: "Vars") var label: String
    @Parameter(title: "Level", default: .info) var level: LogLevel

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$values)") {
            \.$label
            \.$level
        }
    }

    func perform() async throws -> some IntentResult {
        let text = values.isEmpty ? "(no values)" : values.joined(separator: " | ")
        LogStore.append(label: label, message: text, level: level)
        return .result()
    }
}

struct InspectValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Inspect Value"
    static let description = IntentDescription("Reports what a value really contains: length, type guess (numbers incl. Brazilian format, dates, lists, JSON), hidden whitespace and odd characters. Also logs the report.")

    @Parameter(title: "Value") var value: String
    @Parameter(title: "Label", default: "Inspect") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Inspect \(\.$value)") {
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let report = Inspector.report(for: value)
        let hasWarning = report.contains("WARNING") || report.contains("EMPTY") || report.contains("INVALID")
        LogStore.append(label: label, message: report, level: hasWarning ? .warning : .info)
        return .result(value: report)
    }
}

struct ValidateJSONIntent: AppIntent {
    static let title: LocalizedStringResource = "Validate JSON"
    static let description = IntentDescription("Checks whether text is valid JSON and says where it breaks. Returns true if valid.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Label", default: "JSON") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Validate JSON \(\.$text)") {
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let r = Inspector.validateJSON(text)
        LogStore.append(label: label, message: r.message, level: r.ok ? .info : .error)
        return .result(value: r.ok)
    }
}

struct FailWithMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Fail With Message"
    static let description = IntentDescription("Logs a failure with your message when the condition is true. By default the shortcut keeps running; turn on Stop Shortcut to halt it with that error. Returns true if a failure was logged.")

    @Parameter(title: "Message") var message: String
    @Parameter(title: "Fail", default: true) var condition: Bool
    @Parameter(title: "Stop Shortcut", default: false) var stopShortcut: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Log failure \(\.$message) if \(\.$condition), stop shortcut: \(\.$stopShortcut)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard condition else { return .result(value: false) }
        LogStore.append(label: "FAIL", message: message, level: .error)
        if stopShortcut { throw DebugError(message: message) }
        return .result(value: true)
    }
}

struct AssertIntent: AppIntent {
    static let title: LocalizedStringResource = "Assert Value"
    static let description = IntentDescription("Compares a value against an expected one (numbers in 1.234,56 and 1,234.56 formats are understood). Logs PASS or FAIL and returns true when it passes.")

    @Parameter(title: "Value") var value: String
    @Parameter(title: "Check", default: .equals) var op: AssertOp
    @Parameter(title: "Expected", default: "") var expected: String
    @Parameter(title: "Label", default: "Assert") var label: String
    @Parameter(title: "Stop Shortcut on Fail", default: false) var stopShortcut: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Assert \(\.$value) \(\.$op) \(\.$expected)") {
            \.$label
            \.$stopShortcut
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let pass = Inspector.evaluate(value, op, expected)
        let verdict = pass ? "PASS" : "FAIL"
        let msg = "\(verdict): '\(value)' \(op.rawValue) '\(expected)'"
        LogStore.append(label: label, message: msg, level: pass ? .info : .error)
        if !pass && stopShortcut { throw DebugError(message: msg) }
        return .result(value: pass)
    }
}

// MARK: - Notifications

struct NotifyIntent: AppIntent {
    static let title: LocalizedStringResource = "Notify"
    static let description = IntentDescription("Shows a notification (optionally after a delay) and writes it to the log. Returns true if it was delivered.")

    @Parameter(title: "Message") var message: String
    @Parameter(title: "Title", default: "DebugKit") var heading: String
    @Parameter(title: "Delay (seconds)", default: 0) var delay: Int
    @Parameter(title: "Level", default: .info) var level: LogLevel

    static var parameterSummary: some ParameterSummary {
        Summary("Notify \(\.$message)") {
            \.$heading
            \.$delay
            \.$level
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let ok = await Notifier.send(title: heading, body: message, delay: delay)
        if ok {
            LogStore.append(label: "NOTIFY", message: "\(heading): \(message)", level: level)
        } else {
            LogStore.append(label: "NOTIFY", message: "Not delivered (notifications off for DebugKit?): \(message)", level: .warning)
        }
        return .result(value: ok)
    }
}

struct NotifyOnFailureIntent: AppIntent {
    static let title: LocalizedStringResource = "Notify on Failure"
    static let description = IntentDescription("When the condition is true, logs an error and shows a notification. Returns true if it triggered.")

    @Parameter(title: "Message") var message: String
    @Parameter(title: "Fail", default: true) var condition: Bool
    @Parameter(title: "Title", default: "Shortcut failed") var heading: String

    static var parameterSummary: some ParameterSummary {
        Summary("Notify \(\.$message) if \(\.$condition)") {
            \.$heading
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard condition else { return .result(value: false) }
        LogStore.append(label: "FAIL", message: message, level: .error)
        _ = await Notifier.send(title: heading, body: message, delay: 0)
        return .result(value: true)
    }
}

// MARK: - Timers, laps, runs, counters

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Debug Timer"
    static let description = IntentDescription("Starts a named stopwatch.")

    @Parameter(title: "Name", default: "timer") var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start timer \(\.$name)")
    }

    func perform() async throws -> some IntentResult {
        LogStore.startTimer(name)
        return .result()
    }
}

struct LapTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Lap Debug Timer"
    static let description = IntentDescription("Records a lap on a running timer without stopping it. Returns seconds since the previous lap (or start).")

    @Parameter(title: "Name", default: "timer") var name: String
    @Parameter(title: "Note", default: "") var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Lap timer \(\.$name)") {
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        guard let r = LogStore.lap(name) else {
            throw DebugError(message: "No running timer named '\(name)'. Did Start Debug Timer run first?")
        }
        let split = (r.split * 1000).rounded() / 1000
        let total = (r.total * 1000).rounded() / 1000
        let extra = note.isEmpty ? "" : " (\(note))"
        LogStore.append(label: "LAP", message: "\(name)\(extra): +\(split)s, total \(total)s")
        return .result(value: split)
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Debug Timer"
    static let description = IntentDescription("Stops a named stopwatch and returns the elapsed seconds.")

    @Parameter(title: "Name", default: "timer") var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Stop timer \(\.$name)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        guard let secs = LogStore.stopTimer(name) else {
            throw DebugError(message: "No running timer named '\(name)'. Did Start Debug Timer run first?")
        }
        let rounded = (secs * 1000).rounded() / 1000
        LogStore.append(label: "TIMER", message: "\(name): \(rounded)s")
        return .result(value: rounded)
    }
}

struct StartRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Debug Run"
    static let description = IntentDescription("Marks the start of a shortcut run. Every log entry after this is tagged with the shortcut name and a short run ID. Returns the run ID.")

    @Parameter(title: "Shortcut Name") var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start debug run for \(\.$name)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let id = LogStore.startRun(name: name)
        LogStore.append(label: "RUN", message: "Started")
        return .result(value: id)
    }
}

struct EndRunIntent: AppIntent {
    static let title: LocalizedStringResource = "End Debug Run"
    static let description = IntentDescription("Ends the current run, logs how long it took and stops tagging entries. Returns elapsed seconds.")

    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        guard let r = LogStore.endRun() else {
            LogStore.append(label: "RUN", message: "End Debug Run called but no run was started", level: .warning)
            return .result(value: 0)
        }
        let secs = (r.seconds * 1000).rounded() / 1000
        LogStore.append(label: "RUN", message: "Finished \(r.tag) in \(secs)s")
        return .result(value: secs)
    }
}

struct CountRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Count Run"
    static let description = IntentDescription("Counts a run (and optionally a failure) for a name. Returns the total number of runs.")

    @Parameter(title: "Name", default: "shortcut") var name: String
    @Parameter(title: "Failed", default: false) var failed: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Count run for \(\.$name)") {
            \.$failed
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let s = LogStore.countRun(name, failed: failed)
        return .result(value: s.runs)
    }
}

struct GetRunStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Run Stats"
    static let description = IntentDescription("Returns run and failure counts per name, most failing first.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: LogStore.statsText())
    }
}

// MARK: - Reading the log

struct GetLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Debug Log"
    static let description = IntentDescription("Returns recent log entries as text, optionally filtered by minimum level or by text.")

    @Parameter(title: "Entries", default: 20) var count: Int
    @Parameter(title: "Minimum Level") var minimumLevel: LogLevel?
    @Parameter(title: "Contains") var contains: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Get last \(\.$count) log entries") {
            \.$minimumLevel
            \.$contains
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: LogStore.text(last: count, minLevel: minimumLevel, contains: contains))
    }
}

struct SearchLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Debug Log"
    static let description = IntentDescription("Returns log entries whose message, label or run tag contains your text.")

    @Parameter(title: "Text") var query: String
    @Parameter(title: "Max Entries", default: 50) var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search log for \(\.$query)") {
            \.$count
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: LogStore.text(last: count, minLevel: nil, contains: query))
    }
}

struct ExportLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Debug Log to File"
    static let description = IntentDescription("Saves the full log as DebugKit-log.txt (visible in Files under DebugKit) and returns it as a file you can save or share.")

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let data = try LogStore.exportToDocuments()
        let file = IntentFile(data: data, filename: LogStore.exportName, type: .plainText)
        return .result(value: file)
    }
}

struct ClearLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Clear Debug Log"
    static let description = IntentDescription("Deletes all log entries.")

    func perform() async throws -> some IntentResult {
        LogStore.clear()
        return .result()
    }
}
