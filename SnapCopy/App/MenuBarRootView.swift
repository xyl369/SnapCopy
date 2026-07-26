import SwiftUI
import AppKit

struct MenuBarRootView: View {
    @EnvironmentObject private var flow: AppFlow

    var body: some View {
        Text(flow.status).font(.caption).foregroundStyle(.secondary)
        Divider()
        Button("Screenshot ⌥Z") { flow.startScreenshot() }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
