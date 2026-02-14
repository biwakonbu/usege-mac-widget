import AppKit
import SwiftUI

struct MenuBarMenuView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            ForEach(store.providerSnapshots) { snapshot in
                ProviderRowView(snapshot: snapshot)
            }

            Divider()

            actionButtons
        }
        .padding(12)
        .frame(width: 420)
        .onAppear {
            store.startIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("usege")
                .font(.headline)
            Text("Cost tracking: OFF")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Today: \(store.totalDeltaDayUSD >= 0 ? "+" : "")\(store.totalDeltaDayUSD, format: .currency(code: "USD"))")
                .foregroundStyle(store.totalDeltaDayUSD >= 0 ? .green : .red)
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var statusLine: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        if let lastSyncAt = store.lastSyncAt {
            return "\(store.statusMessage) / 最終同期: \(formatter.localizedString(for: lastSyncAt, relativeTo: Date()))"
        }
        return store.statusMessage
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Sync Now") {
                    store.syncNow()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Codex Usage") {
                    NSWorkspace.shared.open(Provider.codex.sourceURL)
                }
            }

            HStack(spacing: 8) {
                Button("Open Z.ai") {
                    NSWorkspace.shared.open(Provider.zai.sourceURL)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProviderRowView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if let errorMessage = snapshot.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(deltaText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle((snapshot.deltaDayUSD ?? 0) >= 0 ? .green : .red)

                Text(limitText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deltaText: String {
        guard let delta = snapshot.deltaDayUSD else {
            return "Today N/A"
        }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(delta.formatted(.currency(code: "USD")))"
    }

    private var limitText: String {
        let limit5h = snapshot.rateLimit5h.map { String(format: "%.1f%%", $0) } ?? "N/A"
        let limit1w = snapshot.rateLimit1w.map { String(format: "%.1f%%", $0) } ?? "N/A"
        return "5h: \(limit5h) / 1w: \(limit1w)"
    }

    private var statusText: String {
        switch snapshot.status {
        case .ok:
            return "OK"
        case .stale:
            return "STALE"
        case .missing:
            return "未同期"
        case .error:
            return snapshot.errorCode?.rawValue ?? "ERROR"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .ok:
            return .green
        case .stale:
            return .orange
        case .missing:
            return .secondary
        case .error:
            return .red
        }
    }
}
