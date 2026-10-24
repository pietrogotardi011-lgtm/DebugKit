import AppIntents
import Foundation

enum LogLevel: String, Codable, CaseIterable, AppEnum {
    case info, warning, error

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Log Level")
    static let caseDisplayRepresentations: [LogLevel: DisplayRepresentation] = [
        .info: DisplayRepresentation(title: "Info"),
        .warning: DisplayRepresentation(title: "Warning"),
        .error: DisplayRepresentation(title: "Error"),
    ]

    var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }
}

enum AssertOp: String, AppEnum {
    case equals, notEquals, contains, greaterThan, lessThan, isEmpty, isNotEmpty

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Check")
    static let caseDisplayRepresentations: [AssertOp: DisplayRepresentation] = [
        .equals: DisplayRepresentation(title: "equals"),
        .notEquals: DisplayRepresentation(title: "does not equal"),
        .contains: DisplayRepresentation(title: "contains"),
        .greaterThan: DisplayRepresentation(title: "is greater than"),
        .lessThan: DisplayRepresentation(title: "is less than"),
        .isEmpty: DisplayRepresentation(title: "is empty"),
        .isNotEmpty: DisplayRepresentation(title: "is not empty"),
    ]
}

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var label: String
    var message: String
    var level: LogLevel?
    var context: String?
}

struct RunStat: Codable {
    var runs = 0
    var fails = 0
    var last: Date?
}

struct DebugError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
