import AppIntents
import Foundation
import UniformTypeIdentifiers

private func r3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

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
        LogStore.step("Log Debug Message")
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
        LogStore.step("Log Variables")
        let text = values.isEmpty ? "(no values)" : values.joined(separator: " | ")
        LogStore.append(label: label, message: text, level: level)
        return .result()
    }
}

struct DumpVariablesIntent: AppIntent {
    static let title: LocalizedStringResource = "Dump All Variables"
    static let description = IntentDescription("Logs every value you pass in as 'name = value (type)', one per line. Names are optional and comma separated, in the same order as the values. Returns the dump.")

    @Parameter(title: "Values") var values: [String]
    @Parameter(title: "Names", default: "") var names: String
    @Parameter(title: "Number Format", default: .usa) var format: NumberFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Dump \(\.$values)") {
            \.$names
            \.$format
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        LogStore.step("Dump All Variables")
        let nameList = names.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var lines: [String] = []
        for (i, v) in values.enumerated() {
            let n = i < nameList.count && !nameList[i].isEmpty ? nameList[i] : "var\(i + 1)"
            let shown = v.count > 120 ? String(v.prefix(120)) + "..." : v
            lines.append("\(n) = \(shown.replacingOccurrences(of: "\n", with: "\\n")) (\(Inspector.typeName(v, format: format)), \(v.count) chars)")
        }
        let text = lines.isEmpty ? "(no values)" : lines.joined(separator: "\n")
        LogStore.append(label: "DUMP", message: text)
        return .result(value: text)
    }
}

struct StartGroupIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Log Group"
    static let description = IntentDescription("Groups the following log entries under a name until End Log Group.")

    @Parameter(title: "Name") var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start log group \(\.$name)")
    }

    func perform() async throws -> some IntentResult {
        LogStore.step("Start Log Group")
        LogStore.startGroup(name)
        LogStore.append(label: "GROUP", message: "Start \(name)")
        return .result()
    }
}

struct EndGroupIntent: AppIntent {
    static let title: LocalizedStringResource = "End Log Group"
    static let description = IntentDescription("Ends the current log group.")

    func perform() async throws -> some IntentResult {
        LogStore.step("End Log Group")
        let name = LogStore.currentGroup() ?? "(none)"
        LogStore.append(label: "GROUP", message: "End \(name)")
        _ = LogStore.endGroup()
        return .result()
    }
}

// MARK: - Checks

struct InspectValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Inspect Value"
    static let description = IntentDescription("Reports what a value really contains: length, type guess (numbers, currency, dates, lists, JSON), hidden whitespace and odd characters. Also logs the report.")

    @Parameter(title: "Value") var value: String
    @Parameter(title: "Number Format", default: .usa) var format: NumberFormat
    @Parameter(title: "Label", default: "Inspect") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Inspect \(\.$value)") {
            \.$format
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        LogStore.step("Inspect Value")
        let report = Inspector.report(for: value, format: format)
        let hasWarning = report.contains("WARNING") || report.contains("EMPTY") || report.contains("INVALID")
        LogStore.append(label: label, message: report, level: hasWarning ? .warning : .info)
        return .result(value: report)
    }
}

struct CompareTypesIntent: AppIntent {
    static let title: LocalizedStringResource = "Compare Types"
    static let description = IntentDescription("Checks whether two values are the same kind (number, date, text...) and warns if not, a common silent bug. Returns true if the types match.")

    @Parameter(title: "First") var first: String
    @Parameter(title: "Second") var second: String
    @Parameter(title: "Number Format", default: .usa) var format: NumberFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Compare types of \(\.$first) and \(\.$second)") {
            \.$format
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        LogStore.step("Compare Types")
        let a = Inspector.typeName(first, format: format)
        let b = Inspector.typeName(second, format: format)
        let same = a == b
        LogStore.append(label: "TYPES", message: same ? "Both are \(a)" : "MISMATCH: first is \(a), second is \(b)",
                        level: same ? .info : .warning)
        return .result(value: same)
    }
}

struct ValidateJSONIntent: AppIntent {
    static let title: LocalizedStringResource = "Validate JSON"
    static let description = IntentDescription("Checks whether text is valid JSON and says where it breaks (line and column). Returns true if valid.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Label", default: "JSON") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Validate JSON \(\.$text)") {
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        LogStore.step("Validate JSON")
        let r = Inspector.validateJSON(text)
        LogStore.append(label: label, message: r.message, level: r.ok ? .info : .error)
        return .result(value: r.ok)
    }
}

struct ValidateDateIntent: AppIntent {
    static let title: LocalizedStringResource = "Validate Date"
    static let description = IntentDescription("Checks text against a date format (default USA MM/dd/yyyy) and explains why it fails. Returns true if valid.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Format", default: "MM/dd/yyyy") var pattern: String
    @Parameter(title: "Label", default: "Date") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Validate date \(\.$text)") {
            \.$pattern
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        LogStore.step("Validate Date")
        let r = Inspector.validateDate(text, pattern: pattern)
        LogStore.append(label: label, message: r.message, level: r.ok ? .info : .error)
        return .result(value: r.ok)
    }
}

struct RegexMatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Regex Match"
    static let description = IntentDescription("Tests text against a regular expression and logs why it matched or not. Returns true if it matches.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Pattern") var pattern: String
    @Parameter(title: "Label", default: "Regex") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Does \(\.$text) match \(\.$pattern)") {
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        LogStore.step("Regex Match")
        let r = Inspector.regexMatch(text, pattern: pattern)
        LogStore.append(label: label, message: r.message, level: r.ok ? .info : .warning)
        return .result(value: r.ok)
    }
}

struct DiffValuesIntent: AppIntent {
    static let title: LocalizedStringResource = "Diff Values"
    static let description = IntentDescription("Compares two texts line by line. Lines only in the first start with '-', lines only in the second with '+'. Spaces show as dots. Returns the diff.")

    @Parameter(title: "First") var first: String
    @Parameter(title: "Second") var second: String
    @Parameter(title: "Label", default: "Diff") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Diff \(\.$first) against \(\.$second)") {
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        LogStore.step("Diff Values")
        let d = Inspector.diff(first, second)
        LogStore.append(label: label, message: d.text, level: d.same ? .info : .warning)
        return .result(value: d.text)
    }
}

struct AssertIntent: AppIntent {
    static let title: LocalizedStringResource = "Assert Value"
    static let description = IntentDescription("Compares a value against an expected one. Logs PASS or FAIL and returns true when it passes. Number Format decides how 1,234.56 vs 1.234,56 is read (default USA).")

    @Parameter(title: "Value") var value: String
    @Parameter(title: "Check", default: .equals) var op: AssertOp
    @Parameter(title: "Expected", default: "") var expected: String
    @Parameter(title: "Number Format", default: .usa) var format: NumberFormat
    @Parameter(title: "Label", default: "Assert") var label: String
    @Parameter(title: "Stop Shortcut on Fail", default: false) var stopShortcut: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Assert \(\.$value) \(\.$op) \(\.$expected)") {
            \.$format
            \.$label
            \.$stopShortcut
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        LogStore.step("Assert Value")
        let pass = Inspector.evaluate(value, op, expected, format: format)
        let verdict = pass ? "PASS" : "FAIL"
        let msg = "\(verdict): '\(value)' \(op.rawValue) '\(expected)'"
        LogStore.append(label: label, message: msg, level: pass ? .info : .error)
        if !pass && stopShortcut { throw DebugError(message: msg) }
        return .result(value: pass)
    }
}

struct AssertListIntent: AppIntent {
    static let title: LocalizedStringResource = "Assert List"
    static let description = IntentDescription("Checks a list's item count or whether it contains an item. Logs PASS or FAIL and returns true when it passes.")

    @Parameter(title: "Items") var items: [String]
    @Parameter(title: "Check", default: .isNotEmpty) var op: ListOp
    @Parameter(title: "Expected", default: "") var expected: String
    @Parameter(title: "Label", default: "AssertList") var label: String
    @Parameter(title: "Stop Shortcut on Fail", default: false) var stopShortcut: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Assert list \(\.$items) \(\.$op) \(\.$expected)") {
            \.$label
            \.$stopShortcut
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        LogStore.step("Assert List")
        let r = Inspector.evaluateList(items, op, expected)
        let msg = "\(r.ok ? "PASS" : "FAIL"): \(r.detail)"
        LogStore.append(label: label, message: msg, level: r.ok ? .info : .error)
        if !r.ok && stopShortcut { throw DebugError(message: msg) }
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
        LogStore.step("Fail With Message")
        guard condition else { return .result(value: false) }
        LogStore.append(label: "FAIL", message: message, level: .error)
        if stopShortcut { throw DebugError(message: message) }
        return .result(value: true)
    }
}

struct BreakpointIntent: AppIntent {
    static let title: LocalizedStringResource = "Breakpoint"
    static let description = IntentDescription("Pauses the shortcut and shows your values in a prompt. Continue to go on, Cancel to stop (or just return false if Stop on Cancel is off). Returns true if you continued.")

    @Parameter(title: "Values") var values: [String]
    @Parameter(title: "Message", default: "Paused") var message: String
    @Parameter(title: "Stop on Cancel", default: true) var stopOnCancel: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Break and show \(\.$values)") {
            \.$message
            \.$stopOnCancel
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        LogStore.step("Breakpoint")
        let shown = values.isEmpty ? "(no values)" : values.joined(separator: " | ")
        LogStore.append(label: "BREAK", message: "\(message): \(shown)")
        let text = "\(message)\n\(shown)"
        do {
            try await requestConfirmation(result: .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: text))))
        } catch {
            LogStore.append(label: "BREAK", message: "Cancelled at breakpoint", level: .warning)
            if stopOnCancel { throw DebugError(message: "Stopped at breakpoint: \(message)") }
            return .result(value: false)
        }
        return .result(value: true)
    }
}

struct GetLastErrorIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Error"
    static let description = IntentDescription("Returns the most recent error entry as text, or empty text if there is none, so a shortcut can react to its own failure.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        LogStore.step("Get Last Error")
        let e = LogStore.filtered(last: 1, minLevel: .error)
        guard let last = e.last, (last.level ?? .info) == .error else { return .result(value: "") }
        return .result(value: last.message)
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
        LogStore.step("Notify")
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
        LogStore.step("Notify on Failure")
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
        LogStore.step("Start Debug Timer")
        LogStore.startTimer(name)
        return .result()
    }
}

struct LapTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Lap Debug Timer"
    static let description = IntentDescription("Records a lap on a running timer without stopping it. Returns seconds since the previous lap (or start). Set Warn Above to log a warning when the lap is slower than that many seconds.")

    @Parameter(title: "Name", default: "timer") var name: String
    @Parameter(title: "Note", default: "") var note: String
    @Parameter(title: "Warn Above (seconds)", default: 0) var warnAbove: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Lap timer \(\.$name)") {
            \.$note
            \.$warnAbove
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        LogStore.step("Lap Debug Timer")
        guard let r = LogStore.lap(name) else {
            throw DebugError(message: "No running timer named '\(name)'. Did Start Debug Timer run first?")
        }
        let split = r3(r.split)
        let total = r3(r.total)
        let extra = note.isEmpty ? "" : " (\(note))"
        let slow = warnAbove > 0 && split > warnAbove
        let tail = slow ? " SLOW: over \(warnAbove)s" : ""
        LogStore.append(label: "LAP", message: "\(name)\(extra): +\(split)s, total \(total)s\(tail)", level: slow ? .warning : .info)
        return .result(value: split)
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Debug Timer"
    static let description = IntentDescription("Stops a named stopwatch and returns the elapsed seconds. Set Warn Above to log a warning when it took longer than that many seconds.")

    @Parameter(title: "Name", default: "timer") var name: String
    @Parameter(title: "Warn Above (seconds)", default: 0) var warnAbove: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Stop timer \(\.$name)") {
            \.$warnAbove
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        LogStore.step("Stop Debug Timer")
        guard let secs = LogStore.stopTimer(name) else {
            throw DebugError(message: "No running timer named '\(name)'. Did Start Debug Timer run first?")
        }
        let rounded = r3(secs)
        let slow = warnAbove > 0 && rounded > warnAbove
        LogStore.append(label: "TIMER", message: "\(name): \(rounded)s" + (slow ? " SLOW: over \(warnAbove)s" : ""),
                        level: slow ? .warning : .info)
        return .result(value: rounded)
    }
}

struct StartRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Debug Run"
    static let description = IntentDescription("Marks the start of a shortcut run. Every log entry after this is tagged with the shortcut name and a short run ID. With Trace Mode on, every later DebugKit action also logs a numbered step. Returns the run ID.")

    @Parameter(title: "Shortcut Name") var name: String
    @Parameter(title: "Trace Mode", default: false) var trace: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Start debug run for \(\.$name)") {
            \.$trace
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let id = LogStore.startRun(name: name, trace: trace)
        LogStore.append(label: "RUN", message: trace ? "Started (trace on)" : "Started")
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
        let secs = r3(r.seconds)
        LogStore.append(label: "RUN", message: "Finished \(r.tag) in \(secs)s" + (r.steps > 0 ? ", \(r.steps) traced steps" : ""))
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
        LogStore.step("Count Run")
        let s = LogStore.countRun(name, failed: failed)
        return .result(value: s.runs)
    }
}

struct GetRunStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Run Stats"
    static let description = IntentDescription("Returns run and failure counts per name, most failing first.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        LogStore.step("Get Run Stats")
        return .result(value: LogStore.statsText())
    }
}

struct RetryCounterIntent: AppIntent {
    static let title: LocalizedStringResource = "Retry Counter"
    static let description = IntentDescription("Counts attempts for a name and logs an error once it passes the maximum, to catch infinite retry loops. Returns the attempt number. Turn on Reset to start over.")

    @Parameter(title: "Name", default: "retry") var name: String
    @Parameter(title: "Maximum", default: 3) var maximum: Int
    @Parameter(title: "Reset", default: false) var reset: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Count retry for \(\.$name)") {
            \.$maximum
            \.$reset
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        LogStore.step("Retry Counter")
        let n = LogStore.retry(name, reset: reset)
        if reset {
            LogStore.append(label: "RETRY", message: "\(name): reset")
        } else if n > maximum {
            LogStore.append(label: "RETRY", message: "\(name): attempt \(n) exceeds maximum \(maximum)", level: .error)
        } else {
            LogStore.append(label: "RETRY", message: "\(name): attempt \(n) of \(maximum)")
        }
        return .result(value: n)
    }
}

struct HealthCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Health Check"
    static let description = IntentDescription("Tests that DebugKit can store data, write files and show notifications. Logs and returns a short report.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        LogStore.step("Health Check")
        let storage = LogStore.storageWorks()
        var files = false
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = dir.appendingPathComponent(".healthcheck")
            files = ((try? Data("ok".utf8).write(to: url)) != nil)
            try? FileManager.default.removeItem(at: url)
        }
        let notif = await Notifier.statusText()
        let notifOK = notif == "allowed" || notif == "provisional"
        let report = "Storage: \(storage ? "OK" : "FAILED")\nFiles: \(files ? "OK" : "FAILED")\nNotifications: \(notif)\nLog entries: \(LogStore.load().count) of \(LogStore.maxEntries)"
        LogStore.append(label: "HEALTH", message: report, level: (storage && files && notifOK) ? .info : .warning)
        return .result(value: report)
    }
}

// MARK: - Reading and managing the log

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
        LogStore.step("Get Debug Log")
        return .result(value: LogStore.text(last: count, minLevel: minimumLevel, contains: contains))
    }
}

struct SearchLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Debug Log"
    static let description = IntentDescription("Returns log entries whose message, label, group or run tag contains your text.")

    @Parameter(title: "Text") var query: String
    @Parameter(title: "Max Entries", default: 50) var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search log for \(\.$query)") {
            \.$count
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        LogStore.step("Search Debug Log")
        return .result(value: LogStore.text(last: count, minLevel: nil, contains: query))
    }
}

struct ExportLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Debug Log to File"
    static let description = IntentDescription("Saves the full log as DebugKit-log (txt, json or csv, visible in Files under DebugKit) and returns it as a file you can save or share. Save the returned file to iCloud Drive to keep it after a reinstall.")

    @Parameter(title: "Format", default: .text) var format: ExportFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Export log as \(\.$format)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        LogStore.step("Export Debug Log")
        let r = try LogStore.exportToDocuments(format)
        let type: UTType
        switch format {
        case .text: type = .plainText
        case .json: type = .json
        case .csv: type = .commaSeparatedText
        }
        return .result(value: IntentFile(data: r.data, filename: r.name, type: type))
    }
}

struct ConfigureLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Configure Debug Log"
    static let description = IntentDescription("Sets how many entries the log keeps and, optionally, deletes entries older than a number of days (0 turns auto-expire off). Pinned entries are never removed. Returns how many entries were deleted now.")

    @Parameter(title: "Max Entries", default: 1000) var maxEntries: Int
    @Parameter(title: "Delete Older Than (days)", default: 0) var days: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Keep \(\.$maxEntries) log entries, expire after \(\.$days) days")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        LogStore.step("Configure Debug Log")
        LogStore.maxEntries = maxEntries
        LogStore.expireDays = days
        let removed = days > 0 ? LogStore.expire(days: days) : 0
        LogStore.append(label: "CONFIG", message: "Keep \(LogStore.maxEntries) entries, expire after \(days) days, removed \(removed)")
        return .result(value: removed)
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
