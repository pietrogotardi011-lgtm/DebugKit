import AppIntents
import Foundation

struct LogMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Debug Message"
    static let description = IntentDescription("Adds a timestamped message to the DebugKit log.")

    @Parameter(title: "Message") var message: String
    @Parameter(title: "Label", default: "Shortcut") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$message) as \(\.$label)")
    }

    func perform() async throws -> some IntentResult {
        LogStore.append(label: label, message: message)
        return .result()
    }
}

struct InspectValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Inspect Value"
    static let description = IntentDescription("Reports what a value really contains: length, type guess, hidden whitespace and odd characters. Also logs the report.")

    @Parameter(title: "Value") var value: String
    @Parameter(title: "Label", default: "Inspect") var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Inspect \(\.$value)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let report = Inspector.report(for: value)
        LogStore.append(label: label, message: report)
        return .result(value: report)
    }
}

struct FailWithMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Fail With Message"
    static let description = IntentDescription("Stops the shortcut with your own specific error message when the condition is true.")

    @Parameter(title: "Message") var message: String
    @Parameter(title: "Fail", default: true) var condition: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Fail with \(\.$message) if \(\.$condition)")
    }

    func perform() async throws -> some IntentResult {
        if condition {
            LogStore.append(label: "FAIL", message: message)
            throw DebugError(message: message)
        }
        return .result()
    }
}

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

struct GetLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Debug Log"
    static let description = IntentDescription("Returns the most recent log entries as text.")

    @Parameter(title: "Entries", default: 20) var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get last \(\.$count) log entries")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: LogStore.text(last: count))
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
