import SwiftUI

@main
struct UsegeApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        MenuBarExtra("usege", systemImage: "chart.bar.xaxis") {
            MenuBarMenuView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("usege settings")
                .padding()
                .frame(width: 240, height: 120)
        }
    }
}
