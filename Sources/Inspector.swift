import Foundation

enum Inspector {
    // MARK: numbers
    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    /// Parses numbers. USA = 1,234.56 ; Brazilian = 1.234,56 ; Auto tries USA first, then Brazilian.
    /// Currency symbols ($, US$, R$, EUR, GBP signs) and % are ignored.
    static func parseNumber(_ raw: String, format: NumberFormat = .usa) -> Double? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var sign = 1.0
        if t.hasPrefix("-") { sign = -1; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        for sym in ["US$", "R$", "$", "\u{20AC}", "\u{00A3}"] where t.hasPrefix(sym) {
            t = String(t.dropFirst(sym.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if t.hasSuffix("%") { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }

        let usa = "^([0-9]{1,3}(,[0-9]{3})+|[0-9]+)(\\.[0-9]+)?$|^\\.[0-9]+$"
        let br = "^([0-9]{1,3}(\\.[0-9]{3})+|[0-9]+)(,[0-9]+)?$|^,[0-9]+$"

        func asUSA() -> Double? {
            guard matches(t, usa) else { return nil }
            return Double(t.replacingOccurrences(of: ",", with: ""))
        }
        func asBR() -> Double? {
            guard matches(t, br) else { return nil }
            return Double(t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        }
        let v: Double?
        switch format {
        case .usa: v = asUSA()
        case .brazilian: v = asBR()
        case .auto: v = asUSA() ?? asBR()
        }
        return v.map { $0 * sign }
    }

    static func evaluate(_ value: String, _ op: AssertOp, _ expected: String, format: NumberFormat = .usa) -> Bool {
        let a = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        let na = parseNumber(a, format: format)
        let nb = parseNumber(b, format: format)
        switch op {
        case .equals:
            if let x = na, let y = nb { return x == y }
            return a == b
        case .notEquals:
            if let x = na, let y = nb { return x != y }
            return a != b
        case .contains: return a.localizedCaseInsensitiveContains(b)
        case .greaterThan:
            if let x = na, let y = nb { return x > y }
            return false
        case .lessThan:
            if let x = na, let y = nb { return x < y }
            return false
        case .isEmpty: return a.isEmpty
        case .isNotEmpty: return !a.isEmpty
        }
    }

    // MARK: lists
    static func evaluateList(_ items: [String], _ op: ListOp, _ expected: String, format: NumberFormat = .usa) -> (ok: Bool, detail: String) {
        let e = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = items.count
        let want = Int(e) ?? parseNumber(e, format: format).map { Int($0) }
        switch op {
        case .countEquals:
            guard let w = want else { return (false, "'\(e)' is not a number") }
            return (n == w, "list has \(n) items, expected exactly \(w)")
        case .countGreaterThan:
            guard let w = want else { return (false, "'\(e)' is not a number") }
            return (n > w, "list has \(n) items, expected more than \(w)")
        case .countLessThan:
            guard let w = want else { return (false, "'\(e)' is not a number") }
            return (n < w, "list has \(n) items, expected fewer than \(w)")
        case .contains:
            let hit = items.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == e }
            return (hit, hit ? "found '\(e)' in \(n) items" : "'\(e)' not found in \(n) items")
        case .doesNotContain:
            let hit = items.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == e }
            return (!hit, hit ? "'\(e)' is in the list" : "'\(e)' correctly absent from \(n) items")
        case .isEmpty: return (n == 0, "list has \(n) items")
        case .isNotEmpty: return (n > 0, "list has \(n) items")
        }
    }

    // MARK: types
    static func typeName(_ s: String, format: NumberFormat = .usa) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "empty" }
        if ["true", "false", "yes", "no"].contains(t.lowercased()) { return "boolean" }
        if parseNumber(t, format: format) != nil { return "number" }
        if dateFormatMatched(t) != nil || ISO8601DateFormatter().date(from: t) != nil { return "date" }
        if let d = t.data(using: .utf8), (t.hasPrefix("{") || t.hasPrefix("[")),
           (try? JSONSerialization.jsonObject(with: d)) != nil { return "json" }
        if let u = URL(string: t), u.scheme != nil, u.host != nil { return "url" }
        if t.components(separatedBy: .newlines).filter({ !$0.isEmpty }).count > 1 { return "list" }
        return "text"
    }

    // MARK: dates
    static let dateFormats = ["MM/dd/yyyy", "MM/dd/yyyy HH:mm", "MM/dd/yyyy h:mm a", "MM-dd-yyyy",
                              "MMM d, yyyy", "MMMM d, yyyy", "yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss"]

    static func parseDate(_ s: String, pattern: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.isLenient = false
        f.dateFormat = pattern
        guard let d = f.date(from: s) else { return nil }
        // round trip catches impossible dates such as 02/30/2026 that lenient parsing might shift
        return f.string(from: d) == s ? d : (padless(s, pattern) ? d : nil)
    }

    private static func padless(_ s: String, _ pattern: String) -> Bool {
        // allow 1/5/2026 for MM/dd/yyyy style patterns
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.isLenient = false
        f.dateFormat = pattern.replacingOccurrences(of: "MM", with: "M").replacingOccurrences(of: "dd", with: "d")
        guard let d = f.date(from: s) else { return false }
        return f.string(from: d) == s
    }

    static func dateFormatMatched(_ s: String) -> String? {
        for fmt in dateFormats where parseDate(s, pattern: fmt) != nil { return fmt }
        return nil
    }

    static func validateDate(_ s: String, pattern: String) -> (ok: Bool, message: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return (false, "Invalid date: input is empty") }
        if parseDate(t, pattern: pattern) != nil { return (true, "Valid date for \(pattern): \(t)") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        f.isLenient = true
        if f.date(from: t) != nil {
            return (false, "Invalid date: '\(t)' looks like \(pattern) but that date does not exist (check month/day)")
        }
        if let other = dateFormatMatched(t) {
            return (false, "Invalid date: '\(t)' does not match \(pattern); it matches \(other) instead")
        }
        return (false, "Invalid date: '\(t)' does not match \(pattern)")
    }

    // MARK: regex
    static func regexMatch(_ text: String, pattern: String) -> (ok: Bool, message: String) {
        let re: NSRegularExpression
        do { re = try NSRegularExpression(pattern: pattern) }
        catch { return (false, "Invalid pattern '\(pattern)': \(error.localizedDescription)") }
        let ns = text as NSString
        let found = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if found.isEmpty { return (false, "No match for /\(pattern)/ in text of \(ns.length) characters") }
        let first = ns.substring(with: found[0].range)
        return (true, "Matched /\(pattern)/ \(found.count) time(s); first: '\(first)'")
    }

    // MARK: diff
    static func diff(_ a: String, _ b: String) -> (same: Bool, text: String) {
        if a == b { return (true, "No differences") }
        let x = a.components(separatedBy: "\n")
        let y = b.components(separatedBy: "\n")
        var lcs = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                lcs[i][j] = x[i] == y[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [String] = []
        var i = 0, j = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { out.append("- \(show(x[i]))"); i += 1 }
            else { out.append("+ \(show(y[j]))"); j += 1 }
        }
        while i < x.count { out.append("- \(show(x[i]))"); i += 1 }
        while j < y.count { out.append("+ \(show(y[j]))"); j += 1 }
        return (false, out.joined(separator: "\n"))
    }

    private static func show(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: "\\t").replacingOccurrences(of: " ", with: "\u{00B7}")
    }

    // MARK: JSON
    static func validateJSON(_ s: String) -> (ok: Bool, message: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return (false, "Invalid JSON: input is empty") }
        guard let d = t.data(using: .utf8) else { return (false, "Invalid JSON: text is not valid UTF-8") }
        do {
            let obj = try JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
            if let dict = obj as? [String: Any] { return (true, "Valid JSON: object with \(dict.count) keys") }
            if let arr = obj as? [Any] { return (true, "Valid JSON: array with \(arr.count) items") }
            return (true, "Valid JSON: single value")
        } catch {
            let ns = error as NSError
            let desc = (ns.userInfo["NSDebugDescription"] as? String) ?? ns.localizedDescription
            var where_ = ""
            if let idx = ns.userInfo["NSJSONSerializationErrorIndex"] as? Int, idx <= t.utf8.count {
                let prefix = String(decoding: Array(t.utf8.prefix(idx)), as: UTF8.self)
                let line = prefix.components(separatedBy: "\n").count
                let col = (prefix.components(separatedBy: "\n").last ?? "").count + 1
                where_ = " (line \(line), column \(col))"
            }
            return (false, "Invalid JSON\(where_): \(desc)")
        }
    }

    // MARK: inspect report
    static func report(for s: String, format: NumberFormat = .usa) -> String {
        if s.isEmpty {
            return "EMPTY: nothing was passed in (empty text). The previous action probably returned nothing."
        }
        var lines: [String] = []
        lines.append("Characters: \(s.count)")
        let allLines = s.components(separatedBy: .newlines)
        lines.append("Lines: \(allLines.count)")

        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            lines.append("WARNING: only whitespace/newlines")
        } else if t != s {
            lines.append("WARNING: leading/trailing whitespace or newline")
        }

        var kinds: [String] = []
        var extra: [String] = []
        let nonEmptyLines = allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if nonEmptyLines.count > 1 {
            kinds.append("list-like: \(nonEmptyLines.count) items (Shortcuts joins lists into lines)")
        }

        if let n = parseNumber(t, format: format) {
            if t.hasPrefix("$") || t.hasPrefix("US$") || t.hasPrefix("R$") || t.hasPrefix("\u{20AC}") || t.hasPrefix("\u{00A3}") {
                kinds.append("currency, value \(n)")
            } else if t.hasSuffix("%") {
                kinds.append("percentage, value \(n)")
            } else {
                kinds.append("number, value \(n)")
            }
            if Double(t) == nil {
                extra.append("NOTE: Shortcuts itself may not treat '\(t)' as a number; strip symbols/separators first")
            }
        } else {
            let other: NumberFormat = format == .usa ? .brazilian : .usa
            if format != .auto, let n = parseNumber(t, format: other) {
                kinds.append("number in \(other == .brazilian ? "Brazilian" : "USA") format (value \(n))")
                extra.append("WARNING: Number Format is \(format == .usa ? "USA" : "Brazilian"), so this is NOT read as a number")
            }
        }

        if let u = URL(string: t), u.scheme != nil, u.host != nil { kinds.append("URL") }

        if ISO8601DateFormatter().date(from: t) != nil {
            kinds.append("ISO date")
        } else if let fmt = dateFormatMatched(t) {
            kinds.append("date (\(fmt))")
            if matches(t, "^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}") {
                let parts = t.prefix(10).split(separator: "/").compactMap { Int($0) }
                if parts.count >= 2, parts[0] <= 12, parts[1] <= 12, parts[0] != parts[1] {
                    extra.append("NOTE: ambiguous date; read as USA month/day/year")
                }
            }
        }

        if let d = t.data(using: .utf8) {
            if (try? JSONSerialization.jsonObject(with: d)) != nil, t.hasPrefix("{") || t.hasPrefix("[") {
                kinds.append("valid JSON")
            } else if t.hasPrefix("{") || t.hasPrefix("[") {
                kinds.append("looks like JSON but is INVALID")
            }
        }
        if ["true", "false", "yes", "no"].contains(t.lowercased()) { kinds.append("boolean-like text") }
        lines.append("Looks like: " + (kinds.isEmpty ? "plain text" : kinds.joined(separator: "; ")))
        lines.append(contentsOf: extra)

        let odd: [(String, Set<UInt32>)] = [
            ("zero-width characters", [0x200B, 0x200C, 0x200D, 0xFEFF]),
            ("non-breaking spaces", [0x00A0]),
            ("curly quotes", [0x2018, 0x2019, 0x201C, 0x201D]),
        ]
        for (name, set) in odd {
            let n = s.unicodeScalars.filter { set.contains($0.value) }.count
            if n > 0 { lines.append("WARNING: \(n) \(name)") }
        }

        let preview = s.count > 80 ? String(s.prefix(80)) + "..." : s
        lines.append("Preview: \(preview.replacingOccurrences(of: "\n", with: "\\n"))")
        return lines.joined(separator: "\n")
    }
}
