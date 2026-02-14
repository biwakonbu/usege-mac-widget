import SwiftUI
import WidgetKit

struct UsegeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct UsegeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsegeWidgetEntry {
        UsegeWidgetEntry(date: Date(), snapshot: sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsegeWidgetEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        completion(UsegeWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsegeWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        let entry = UsegeWidgetEntry(date: Date(), snapshot: snapshot)
        let next = Date().addingTimeInterval(AppConfig.syncIntervalSeconds)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var sampleSnapshot: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            providers: [
                ProviderSnapshot(
                    provider: .codex,
                    displayName: "Codex",
                    costUSD: 0,
                    deltaDayUSD: 1.2,
                    rateLimit5h: 31.0,
                    rateLimit1w: 58.0,
                    capturedAt: Date(),
                    stale: false,
                    status: .ok,
                    errorCode: nil,
                    errorMessage: nil
                )
            ],
            totalCostUSD: 0,
            totalDeltaDayUSD: 1.2,
            staleCount: 0
        )
    }
}

struct UsegeWidgetView: View {
    var entry: UsegeWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("usege")
                    .font(.headline)
                Spacer()
                Text(entry.snapshot.generatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Cost tracking OFF")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Today \(entry.snapshot.totalDeltaDayUSD >= 0 ? "+" : "")\(entry.snapshot.totalDeltaDayUSD, format: .currency(code: "USD"))")
                .font(.caption)
                .foregroundStyle(entry.snapshot.totalDeltaDayUSD >= 0 ? .green : .red)

            Divider()

            ForEach(Array(entry.snapshot.providers.prefix(3))) { provider in
                HStack {
                    Text(provider.displayName)
                        .font(.caption)
                    Spacer()
                    Text(deltaText(for: provider))
                        .font(.caption.monospacedDigit())
                }
            }

            if entry.snapshot.staleCount > 0 {
                Text("stale: \(entry.snapshot.staleCount)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func deltaText(for provider: ProviderSnapshot) -> String {
        guard let delta = provider.deltaDayUSD else {
            return "Today N/A"
        }
        let sign = delta >= 0 ? "+" : ""
        return "Today \(sign)\(delta.formatted(.currency(code: "USD")))"
    }
}

struct UsegeWidget: Widget {
    let kind: String = "UsegeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsegeWidgetProvider()) { entry in
            UsegeWidgetView(entry: entry)
        }
        .configurationDisplayName("usege")
        .description("AI usage summary")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct UsegeWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsegeWidget()
    }
}
