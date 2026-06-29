import SwiftUI

@main
struct AgentTrafficLightApp: App {
    @StateObject private var store = StatusStore()

    var body: some Scene {
        MenuBarExtra {
            if store.attention.isEmpty {
                Text("Nothing needs you 💤")
            } else {
                ForEach(store.attention) { item in
                    Button("\(item.icon) [\(item.agent)] \(item.label)") {
                        store.focus(item)
                    }
                }
            }
            Divider()
            Button("Clear ⚠️") { store.clearErrors() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            Text(store.label)
        }
    }
}
