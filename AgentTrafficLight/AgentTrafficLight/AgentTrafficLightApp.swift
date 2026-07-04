import SwiftUI

@main
struct AgentTrafficLightApp: App {
    @StateObject private var store = StatusStore()

    var body: some Scene {
        MenuBarExtra {
            if store.attention.isEmpty {
                Text("No active agents 💤")
            } else {
                ForEach(store.attention) { item in
                    Button {
                        store.focus(item)
                    } label: {
                        Label {
                            Text("\(item.icon) \(item.label)")
                        } icon: {
                            Image(item.agent == "Codex" ? "CodexLogo" : "ClaudeLogo")
                                .renderingMode(.original)
                                .accessibilityLabel(item.agent)
                        }
                    }
                }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            Text(store.label)
        }
    }
}
