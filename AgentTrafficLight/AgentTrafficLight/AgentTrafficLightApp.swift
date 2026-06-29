import SwiftUI

@main
struct AgentTrafficLightApp: App {
    @StateObject private var store = StatusStore()

    var body: some Scene {
        MenuBarExtra {
            ForEach(store.lines, id: \.self) { Text($0) }
            Divider()
            Button("Очистить ⚠️") { store.clearErrors() }
            Button("Выход") { NSApplication.shared.terminate(nil) }
        } label: {
            Text(store.label)
        }
    }
}
