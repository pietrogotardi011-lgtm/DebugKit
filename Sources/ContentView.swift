import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    var body: some View {
        TabView {
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            RunsView()
                .tabItem { Label("Runs", systemImage: "clock.arrow.circlepath") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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

private func labelColor(_ label: String) -> Color {
    let hue = label.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
    return Color(hue: Double(hue) / 360.0, saturation: 0.65, brightness: 0.85)
}

struct EntryRow: View {
    let entry: LogEntry

    var body: some View {
        let lvl = entry.level ?? .info
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(labelColor(entry.label))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if entry.pinned ?? false {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.yellow)
                    }
                    Text(header(lvl))
                        .font(.caption)
                        .foregroundStyle(levelColor(lvl))
                }
                Text(entry.message)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
    }

    private func header(_ lvl: LogLevel) -> String {
        var s = "\(lvl.rawValue.uppercased())  [\(entry.label)]  \(entry.date.formatted(date: .omitted, time: .standard))"
        if let c = entry.context { s += "  \(c)" }
        if let g = entry.group { s += "  {\(g)}" }
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
                || (e.group ?? "").lowercased().contains(q)
        }
    }

    private var ordered: [LogEntry] {
        let newest = Array(filtered.reversed())
        return newest.filter { $0.pinned ?? false } + newest.filter { !($0.pinned ?? false) }
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

                List(ordered) { e in
                    EntryRow(entry: e)
                        .swipeActions(edge: .leading) {
                            Button {
                                LogStore.togglePin(e.id)
                                reload()
                            } label: {
                                Label((e.pinned ?? false) ? "Unpin" : "Pin", systemImage: "pin")
                            }
                            .tint(.yellow)
                        }
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
                    Menu {
                        ShareLink("Share as text", item: LogStore.export(filtered, as: .text))
                        ShareLink("Share as JSON", item: LogStore.export(filtered, as: .json))
                        ShareLink("Share as CSV", item: LogStore.export(filtered, as: .csv))
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
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

struct RunsView: View {
    @State private var runs: [RunSummary] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List(runs) { r in
                NavigationLink {
                    RunDetailView(tag: r.tag)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.tag).font(.headline)
                        Text("\(r.count) entries, \(r.errors) errors, \(r.warnings) warnings, \(String(format: "%.2f", r.duration))s")
                            .font(.caption)
                            .foregroundStyle(r.errors > 0 ? Color.red : Color.secondary)
                        Text(r.end.formatted(date: .abbreviated, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .overlay {
                if runs.isEmpty {
                    Text("No runs yet.\nStart your shortcut with Start Debug Run.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondary)
                }
            }
            .navigationTitle("Runs")
            .refreshable { reload() }
            .onAppear(perform: reload)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reload() }
            }
        }
    }

    private func reload() { runs = LogStore.runs() }
}

struct RunDetailView: View {
    let tag: String

    var body: some View {
        let entries = LogStore.entries(forRun: tag)
        List(entries) { e in
            EntryRow(entry: e)
        }
        .navigationTitle(tag)
        .toolbar {
            ShareLink(item: LogStore.format(entries))
        }
    }
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

struct SettingsView: View {
    @State private var limit = LogStore.maxEntries
    @State private var days = LogStore.expireDays
    @State private var notifStatus = "checking..."
    @State private var confirmClear = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    LabeledContent("Permission", value: notifStatus)
                    Button("Ask for permission") {
                        Notifier.requestPermission()
                        Task { try? await Task.sleep(nanoseconds: 1_000_000_000); await refreshStatus() }
                    }
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section("Log size") {
                    Stepper("Keep \(limit) entries", value: $limit, in: 100...5000, step: 100)
                        .onChange(of: limit) { _, v in LogStore.maxEntries = v }
                    Stepper(days == 0 ? "Auto-delete: off" : "Auto-delete after \(days) days", value: $days, in: 0...365)
                        .onChange(of: days) { _, v in LogStore.expireDays = v }
                    Text("Pinned entries (swipe right on an entry) are never deleted.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Section("Data") {
                    Button("Clear everything", role: .destructive) { confirmClear = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete the log, counters, timers and retries?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear everything", role: .destructive) { LogStore.clearEverything() }
            }
            .task { await refreshStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshStatus() } }
            }
        }
    }

    private func refreshStatus() async { notifStatus = await Notifier.statusText().components(separatedBy: " (").first ?? "unknown" }
}
