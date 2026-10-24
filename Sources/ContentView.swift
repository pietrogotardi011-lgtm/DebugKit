import SwiftUI

struct ContentView: View {
    @State private var entries: [LogEntry] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List(Array(entries.reversed())) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text("[\(e.label)]  \(e.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(e.message)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            .overlay {
                if entries.isEmpty {
                    Text("No log entries yet.\nUse the DebugKit actions in Shortcuts.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Debug Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        LogStore.clear()
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

    private func reload() { entries = LogStore.load() }
}
