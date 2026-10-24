import Foundation

enum Inspector {
    static func report(for s: String) -> String {
        if s.isEmpty {
            return "EMPTY: nothing was passed in (empty text). The previous action probably returned nothing."
        }
        var lines: [String] = []
        lines.append("Characters: \(s.count)")
        lines.append("Lines: \(s.components(separatedBy: .newlines).count)")

        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            lines.append("WARNING: only whitespace/newlines")
        } else if t != s {
            lines.append("WARNING: leading/trailing whitespace or newline")
        }

        var kinds: [String] = []
        if Double(t) != nil {
            kinds.append("number")
        } else if t.contains(","), Double(t.replacingOccurrences(of: ",", with: ".")) != nil {
            kinds.append("number written with a comma decimal (Shortcuts may fail to treat it as a number)")
        }
        if let u = URL(string: t), u.scheme != nil, u.host != nil { kinds.append("URL") }
        if ISO8601DateFormatter().date(from: t) != nil { kinds.append("ISO date") }
        if let d = t.data(using: .utf8) {
            if (try? JSONSerialization.jsonObject(with: d)) != nil {
                kinds.append("valid JSON")
            } else if t.hasPrefix("{") || t.hasPrefix("[") {
                kinds.append("looks like JSON but is INVALID")
            }
        }
        lines.append("Looks like: " + (kinds.isEmpty ? "plain text" : kinds.joined(separator: ", ")))

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
