import Foundation

enum Inspector {
    /// Parses numbers written US style (1,234.56) or Brazilian style (1.234,56 / 3,5).
    static func parseNumber(_ raw: String) -> Double? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("R$") { t = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if t.hasSuffix("%") { t = String(t.dropLast()) }
        let lastComma = t.lastIndex(of: ",")
        let lastDot = t.lastIndex(of: ".")
        if let c = lastComma, let d = lastDot {
            if c > d {
                t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                t = t.replacingOccurrences(of: ",", with: "")
            }
        } else if lastComma != nil {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        return Double(t)
    }

    static func evaluate(_ value: String, _ op: AssertOp, _ expected: String) -> Bool {
        let a = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        let na = parseNumber(a)
        let nb = parseNumber(b)
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
            return (false, "Invalid JSON: \(desc)")
        }
    }

    static func report(for s: String) -> String {
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
        let nonEmptyLines = allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if nonEmptyLines.count > 1 {
            kinds.append("list-like: \(nonEmptyLines.count) items (Shortcuts joins lists into lines)")
        }
        if Double(t) != nil {
            kinds.append("number")
        } else if t.range(of: "^-?[0-9]{1,3}(\\.[0-9]{3})+(,[0-9]+)?$", options: .regularExpression) != nil {
            kinds.append("number in Brazilian format (dot thousands, comma decimal); Shortcuts may not read it as a number")
        } else if t.contains(","), Double(t.replacingOccurrences(of: ",", with: ".")) != nil {
            kinds.append("number with comma decimal (Shortcuts may fail to treat it as a number)")
        } else if t.hasPrefix("R$"), parseNumber(t) != nil {
            kinds.append("currency (R$)")
        } else if t.hasSuffix("%"), parseNumber(t) != nil {
            kinds.append("percentage")
        }
        if let u = URL(string: t), u.scheme != nil, u.host != nil { kinds.append("URL") }
        if ISO8601DateFormatter().date(from: t) != nil {
            kinds.append("ISO date")
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            for fmt in ["dd/MM/yyyy", "dd/MM/yyyy HH:mm", "dd-MM-yyyy", "yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss"] {
                f.dateFormat = fmt
                if f.date(from: t) != nil { kinds.append("date (\(fmt))"); break }
            }
        }
        if let d = t.data(using: .utf8) {
            if (try? JSONSerialization.jsonObject(with: d)) != nil {
                kinds.append("valid JSON")
            } else if t.hasPrefix("{") || t.hasPrefix("[") {
                kinds.append("looks like JSON but is INVALID")
            }
        }
        lines.append("Looks like: " + (kinds.isEmpty ? "plain text" : kinds.joined(separator: "; ")))

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
