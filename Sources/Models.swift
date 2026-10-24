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

enum ListOp: String, AppEnum {
    case countEquals, countGreaterThan, countLessThan, contains, doesNotContain, isEmpty, isNotEmpty

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "List Check")
    static let caseDisplayRepresentations: [ListOp: DisplayRepresentation] = [
        .countEquals: DisplayRepresentation(title: "has exactly N items"),
        .countGreaterThan: DisplayRepresentation(title: "has more than N items"),
        .countLessThan: DisplayRepresentation(title: "has fewer than N items"),
        .contains: DisplayRepresentation(title: "contains item"),
        .doesNotContain: DisplayRepresentation(title: "does not contain item"),
        .isEmpty: DisplayRepresentation(title: "is empty"),
        .isNotEmpty: DisplayRepresentation(title: "is not empty"),
    ]
}

enum NumberFormat: String, AppEnum {
    case usa, brazilian, auto

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Number Format")
    static let caseDisplayRepresentations: [NumberFormat: DisplayRepresentation] = [
        .usa: DisplayRepresentation(title: "USA (1,234.56)"),
        .brazilian: DisplayRepresentation(title: "Brazilian (1.234,56)"),
        .auto: DisplayRepresentation(title: "Auto-detect"),
    ]
}

enum ExportFormat: String, AppEnum {
    case text, json, csv

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Export Format")
    static let caseDisplayRepresentations: [ExportFormat: DisplayRepresentation] = [
        .text: DisplayRepresentation(title: "Text"),
        .json: DisplayRepresentation(title: "JSON"),
        .csv: DisplayRepresentation(title: "CSV"),
    ]

    var ext: String {
        switch self {
        case .text: return "txt"
        case .json: return "json"
        case .csv: return "csv"
        }
    }
}

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var label: String
    var message: String
    var level: LogLevel?
    var context: String?
    var group: String? = nil
    var pinned: Bool? = nil
}

struct RunStat: Codable {
    var runs = 0
    var fails = 0
    var last: Date?
}

struct RunSummary: Identifiable {
    var id: String { tag }
    let tag: String
    let count: Int
    let errors: Int
    let warnings: Int
    let start: Date
    let end: Date
    var duration: Double { end.timeIntervalSince(start) }
}

struct DebugError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
