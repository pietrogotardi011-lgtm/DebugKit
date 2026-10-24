import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
    }
}

private func levelColor(_ l: LogLevel) -> Color {
    switch l {
    case .error: return .red
    case .warning: return .orange
    case .info: return .secondary
    }
}

struct EntryRow: View {
    let entry: LogEntry

    var body: some View {
        let lvl = entry.level ?? .info
        VStack(alignment: .leading, spacing: 4) {
            Text(header(lvl))
                .font(.caption)
                .foregroundStyle(levelColor(lvl))
            Text(entry.message)
                .font(.system(.footnote, design: .monospaced))
        }
    }

    private func header(_ lvl: LogLevel) -> String {
        var s = "\(lvl.rawValue.uppercased())  [\(entry.label)]  \(entry.date.formatted(date: .omitted, time: .standard))"
        if let c = entry.context { s += "  \(c)" }
        return s
    }
}

struct LogView: View {
    @State private var entries: [LogEntry] = []
    @State private var search = ""
    @State private var minLevel = 0
    @Environment(\.scenePhase) private var scenePhase

    private var filtered: [LogEntry] {
        entries.filter { e in
            guard (e.level ?? .info).rank >= minLevel else { return false }
            if search.isEmpty { return true }
            let q = search.lowercased()
            return e.message.lowercased().contains(q)
                || e.label.lowercased().contains(q)
                || (e.context ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Level", selection: $minLevel) {
                    Text("All").tag(0)
                    Text("Warnings+").tag(1)
                    Text("Errors").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                List(Array(filtered.reversed())) { e in
                    EntryRow(entry: e)
                }
                .overlay {
                    if filtered.isEmpty {
                        Text("No log entries.\nUse the DebugKit actions in Shortcuts.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Debug Log")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: LogStore.format(filtered))
                    Button {
                        UIPasteboard.general.string = LogStore.format(filtered)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        LogStore.clear()
                        reload()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .refreshable { reload() }
            .onAppear(perform: reload)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reload() }
            }
        }
    }

    private func reload() { entries = LogStore.load() }
}

struct StatsView: View {
    @State private var stats: [(name: String, stat: RunStat)] = []
    @State private var levelCounts: [Int] = [0, 0, 0]
    @State private var errorsByShortcut: [(name: String, count: Int)] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Log summary") {
                    LabeledContent("Info", value: "\(levelCounts[0])")
                    LabeledContent("Warnings", value: "\(levelCounts[1])")
                    LabeledContent("Errors", value: "\(levelCounts[2])")
                }
                Section("Errors by shortcut") {
                    if errorsByShortcut.isEmpty {
                        Text("None yet. Use Start Debug Run so entries carry a shortcut name.")
                            .foregroundStyle(Color.secondary)
                    }
                    ForEach(errorsByShortcut, id: \.name) { item in
                        LabeledContent(item.name, value: "\(item.count)")
                    }
                }
                Section("Run counters (most failing first)") {
                    if stats.isEmpty {
                        Text("None yet. Use the Count Run action.")
                            .foregroundStyle(Color.secondary)
                    }
                    ForEach(stats, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline)
                            Text("\(item.stat.runs) runs, \(item.stat.fails) failed")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset counters", role: .destructive) {
                        LogStore.clearStats()
                        reload()
                    }
                }
            }
            .refreshable { reload() }
            .onAppear(perform: reload)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reload() }
            }
        }
    }

    private func reload() {
        stats = LogStore.allStats()
            .sorted { $0.value.fails > $1.value.fails }
            .map { (name: $0.key, stat: $0.value) }

        let entries = LogStore.load()
        var counts = [0, 0, 0]
        var byShortcut: [String: Int] = [:]
        for e in entries {
            let lvl = e.level ?? .info
            counts[lvl.rank] += 1
            if lvl == .error, let ctx = e.context {
                let name = ctx.components(separatedBy: "#").first ?? ctx
                byShortcut[name, default: 0] += 1
            }
        }
        levelCounts = counts
        errorsByShortcut = byShortcut.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) }
    }
}
