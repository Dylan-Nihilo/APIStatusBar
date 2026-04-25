import SwiftUI

@main
struct APIStatusBarApp: App {
    var body: some Scene {
        MenuBarExtra("APIStatusBar", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            Text("Hello, NOVA")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
